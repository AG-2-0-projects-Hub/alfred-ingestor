import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/aurora_background.dart';
import '../widgets/drop_zone.dart';
import '../widgets/glass_panel.dart';
import '../widgets/voice_recorder.dart';
import '../widgets/file_status_list.dart';
import '../widgets/conflict_questionnaire.dart';
import '../widgets/add_property_walkthrough_panel.dart';
import '../widgets/training_wait_dialog.dart';

class AddPropertyScreen extends StatefulWidget {
  final bool showWalkthrough;
  final bool isDev;
  const AddPropertyScreen({
    super.key,
    this.showWalkthrough = false,
    this.isDev = false,
  });

  @override
  State<AddPropertyScreen> createState() => _AddPropertyScreenState();
}

class _AddPropertyScreenState extends State<AddPropertyScreen> {
  final _nicknameController = TextEditingController();
  final _urlController = TextEditingController();
  final _scrollController = ScrollController();
  final _urlSectionKey = GlobalKey();
  final _uploadSectionKey = GlobalKey();
  final _trainSectionKey = GlobalKey();
  WalkthroughScreen? _walkthroughScreen;
  late final String _propertyId;
  String? _resolvedPropertyId;
  bool _isIngesting = false;
  bool _isMerging = false;
  StreamSubscription<List<Map<String, dynamic>>>? _propertySub;
  // Guards the auto-merge-on-Ingested trigger below so a realtime row update
  // (which can fire more than once) doesn't queue a second merge call.
  bool _autoMergeTriggered = false;
  // Same guard for the dev-mode "Files Ingested" dialog.
  bool _ingestedDialogShown = false;
  // Signals when the whole non-dev ingest+merge chain has concluded, one way
  // or another — merge now fires from _subscribeToProperty's listener rather
  // than being awaited inline in _startIngest, so this is what lets
  // _startIngest still wait for the real end of the chain before it hides
  // the training-wait dialog (TrainingWaitDialog's own contract: shown for
  // the whole ingest+merge span, not just one request). Completed by
  // _runMerge's finally, or immediately if ingest itself lands on
  // Ingest_Error with nothing to merge.
  Completer<void>? _flowCompleter;
  // True once the host taps TrainingWaitDialog's "Continue in background" —
  // guards _startIngest's two Navigator...pop() calls so they don't try to
  // pop a dialog that's already gone (which would pop whatever route is now
  // on top instead, e.g. this screen itself).
  bool _waitDialogDismissed = false;
  // Single list, tracked from upload through ingestion completion — status
  // updates in place (queued → processing → done/error) rather than a second
  // "Files Ingested" list appearing below a frozen first one.
  final List<Map<String, String>> _filesToIngest = [];
  String? _ingestedMarkdown;
  String? _officialPropertyName;
  String? _heroImageUrl;
  String? _propertyStatus;
  Map<String, dynamic>? _masterJson;
  // True once the host submitted conflict resolutions but hasn't yet clicked
  // "Update Knowledge" — used to retitle the status badge.
  bool _resolutionsSubmitted = false;

  static const _postMergeStatuses = {
    'Merged',
    'Conflict_Pending',
    'Trained',
    'Fully_Trained',
  };

  @override
  void initState() {
    super.initState();
    _propertyId = _generateUuidV4();
    _urlController.addListener(() => setState(() {}));
    if (widget.showWalkthrough) {
      _walkthroughScreen = WalkthroughScreen.url;
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _urlController.dispose();
    _scrollController.dispose();
    _propertySub?.cancel();
    super.dispose();
  }

  // The screen previously only knew a run had finished when its own in-flight
  // HTTP call resolved — if that connection dropped or stalled past its own
  // read timeout, the screen was stuck showing "Ingesting" forever, every
  // file read as failed, and (for non-dev) the auto-chained merge never even
  // ran, even though the backend kept working and finished for real.
  // Watching the row directly means the UI, the per-file labels, and the
  // non-dev auto-merge chain all follow the real backend state regardless of
  // what happens to any single request. Mirrors edit_property_screen.dart's
  // _subscribeToProperty, confirmed live 2026-09-15 on a real retrain.
  void _subscribeToProperty(String propertyId) {
    _propertySub?.cancel();
    _propertySub = Supabase.instance.client
        .from('properties')
        .stream(primaryKey: ['id'])
        .eq('id', propertyId)
        .listen((rows) {
      if (!mounted || rows.isEmpty) return;
      final row = rows.first;
      final status = row['status'] as String?;
      final fingerprints =
          row['file_fingerprints'] as Map<String, dynamic>? ?? {};
      final ingested = row['ingested_markdown'] as String?;
      final scraped = row['scraped_markdown'] as String?;
      final batchConcluded = status != 'Ingesting' && status != 'Training';
      setState(() {
        _propertyStatus = status;
        _ingestedMarkdown = ingested ?? _ingestedMarkdown;
        _masterJson =
            (row['master_json'] as Map<String, dynamic>?) ?? _masterJson;
        // A file can still succeed on a later backend-side retry after this
        // browser's own connection stopped watching — file_fingerprints is
        // the authoritative record of what actually made it in. Never show a
        // failure word for a file that isn't actually confirmed failed yet:
        // while the batch is still running, an unresolved file just stays
        // "Processing…"; only once the run has genuinely concluded and it's
        // still missing do we call it failed — one, final verdict per file.
        for (var i = 0; i < _filesToIngest.length; i++) {
          final f = _filesToIngest[i];
          final succeededFile = fingerprints.containsKey(f['file']);
          if (succeededFile && f['status'] != 'done') {
            _filesToIngest[i] = {'file': f['file']!, 'status': 'done', 'message': ''};
          } else if (!succeededFile &&
              batchConcluded &&
              (f['status'] == 'queued' || f['status'] == 'processing')) {
            _filesToIngest[i] = {
              'file': f['file']!,
              'status': 'error',
              'message': "Couldn't be processed — try again",
            };
          }
        }
        if (batchConcluded) _isIngesting = false;
        if (status != 'Ingested') _isMerging = false;
      });
      if (_officialPropertyName == null && scraped != null) {
        final name = _parseOfficialName(scraped);
        if (name != null) {
          setState(() => _officialPropertyName = name);
          _getHeroImageUrl(propertyId).then((url) {
            if (mounted) setState(() => _heroImageUrl = url);
          });
        }
      }
      if (widget.isDev) {
        if (status == 'Ingested' &&
            !_ingestedDialogShown &&
            (ingested?.isNotEmpty ?? false)) {
          _ingestedDialogShown = true;
          _showIngestedDialog(
              _officialPropertyName ?? _nicknameController.text.trim());
        }
        if (status != 'Ingested') _ingestedDialogShown = false;
        return;
      }
      // Train Now (User mode): no manual "run Merge next" step — chain
      // straight into it, same eligibility the Dev-mode Merge button uses.
      if (status == 'Ingested' && !_autoMergeTriggered && !_isMerging) {
        _autoMergeTriggered = true;
        _runMerge();
      } else if (status == 'Ingest_Error' &&
          _flowCompleter != null &&
          !_flowCompleter!.isCompleted) {
        // Nothing usable came out of ingest — no merge will ever fire to
        // complete the chain, so signal done here, or _startIngest's wait
        // for it would just sit until the 4-minute safety timeout.
        _flowCompleter!.complete();
      }
      if (status != 'Ingested') _autoMergeTriggered = false;
    });
  }

  GlobalKey _keyFor(WalkthroughScreen screen) => switch (screen) {
        WalkthroughScreen.url => _urlSectionKey,
        WalkthroughScreen.upload => _uploadSectionKey,
        WalkthroughScreen.train => _trainSectionKey,
      };

  void _goToWalkthroughScreen(WalkthroughScreen screen) {
    setState(() => _walkthroughScreen = screen);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keyFor(screen).currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: 0.1);
      }
    });
  }

  void _dismissWalkthrough() => setState(() => _walkthroughScreen = null);

  Widget _walkthroughHighlight({
    required WalkthroughScreen screen,
    required Widget child,
  }) {
    final active = _walkthroughScreen == screen;
    return AnimatedContainer(
      key: _keyFor(screen),
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active ? context.palette.primary : Colors.transparent,
          width: 2,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: context.palette.primary.withValues(alpha: 0.25),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: child,
    );
  }

  String _generateUuidV4() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  void _onFileAdded(String filename) {
    setState(() {
      _filesToIngest.add({'file': filename, 'status': 'processing', 'message': ''});
    });
  }

  void _onFileResult(String filename, bool success) {
    setState(() {
      final idx = _filesToIngest.indexWhere((e) => e['file'] == filename);
      if (idx >= 0) {
        _filesToIngest[idx] = {
          'file': filename,
          'status': success ? 'queued' : 'error',
          'message': success ? '' : 'Upload failed',
        };
      }
    });
  }

  Future<void> _startIngest() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || _isIngesting) return;

    setState(() {
      _isIngesting = true;
      _waitDialogDismissed = false;
      _resolvedPropertyId = null;
      _ingestedMarkdown = null;
      _officialPropertyName = null;
      _heroImageUrl = null;
      _propertyStatus = null;
      _masterJson = null;
      _autoMergeTriggered = false;
      _ingestedDialogShown = false;
    });

    // Start watching the row immediately, using the ID this client already
    // generated (initState), rather than waiting for the backend to echo it
    // back via the '(system)'/'property_id' SSE event below. If the
    // connection drops or never delivers even that first event -- the exact
    // scenario this whole realtime backstop exists for -- waiting for the
    // echo meant the backstop never activated at all (confirmed live
    // 2026-09-15: browser lost the stream before any event arrived, screen
    // had zero way to learn the backend kept working). The backend resolves
    // the canonical property_id (a rename onto an existing same-named
    // property) before it inserts the row or emits anything, so _propertyId
    // is already correct for the common case; _handleSseEvent below still
    // re-subscribes if the resolved ID ever differs (the rename case).
    _flowCompleter = Completer<void>();
    _subscribeToProperty(_propertyId);

    // Train Now (User mode) can take a couple of minutes across scrape +
    // ingest + merge — show the wait dialog for that whole span so it doesn't
    // read as a frozen screen. Dev mode keeps its existing separate
    // Ingest/Merge buttons and completion dialog instead.
    final showWaitDialog = !widget.isDev;
    if (showWaitDialog && mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: AppTheme.trainingBarrierColor,
        builder: (_) => TrainingWaitDialog(
          onRunInBackground: () => setState(() => _waitDialogDismissed = true),
        ),
      );
    }

    final String backendUrl;
    try {
      backendUrl = ApiClient.backendUrl;
    } on ConfigurationException catch (e) {
      _showError(e.userMessage);
      if (showWaitDialog && mounted && !_waitDialogDismissed) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      setState(() => _isIngesting = false);
      return;
    }
    // Attach the auth token so backend stamps owner_id on the property row.
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;

    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse('$backendUrl/api/ingest'))
        ..headers['Content-Type'] = 'application/json';
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      request.body = jsonEncode({
        'property_id': _propertyId,
        'property_name': _nicknameController.text.trim(),
        'airbnb_url': url,
      });

      // Connection-level timeout — without it, a backend that never responds
      // at all (vs. streaming slowly) left "Ingesting…" hanging forever: only
      // the stream-of-chunks below had a timeout, and that timer never starts
      // until a response begins.
      final response =
          await client.send(request).timeout(const Duration(seconds: 20));
      await for (final chunk in response.stream
          .transform(utf8.decoder)
          .timeout(const Duration(seconds: 90),
              onTimeout: (sink) => sink.close())) {
        for (final line in chunk.split('\n')) {
          if (line.startsWith('data: ')) {
            final raw = line.substring(6).trim();
            if (raw.isEmpty) continue;
            try {
              _handleSseEvent(jsonDecode(raw) as Map<String, dynamic>);
            } catch (_) {}
          }
        }
      }
      // Any file still 'queued'/'processing' here means this browser's own
      // connection ended before hearing back — not that the file failed. The
      // backend keeps working regardless; _subscribeToProperty's listener
      // (started above, as soon as the resolved property_id arrived) resolves
      // each file to its real final state once the property row updates.

      final effectiveId = _resolvedPropertyId ?? _propertyId;
      final result = await Supabase.instance.client
          .from('properties')
          .select('ingested_markdown, status')
          .eq('id', effectiveId)
          .maybeSingle();

      // Everything else (ingested markdown/status/master_json, per-file
      // done/error labels, hero image + official name, the dev "ingested"
      // dialog, and non-dev's auto-chained merge) is driven by
      // _subscribeToProperty's realtime listener instead of here, so it all
      // still happens even if this specific request never makes it back
      // (dropped connection, this browser's own read timeout, etc). This
      // read only decides whether to surface an immediate error toast.
      final resultStatus = result?['status'] as String?;
      final resultIngested = result?['ingested_markdown'] as String?;
      final succeeded = resultIngested != null && resultIngested.isNotEmpty;
      final stillRunning =
          resultStatus == 'Ingesting' || resultStatus == 'Training';

      if (!succeeded && !stillRunning) {
        // Surface a visible error if the ingest didn't succeed. Picks the
        // most recent backend error event when one was emitted (e.g.
        // "(setup)" / "(unhandled)" / "(scrape)" / per-file errors). Falls
        // back to a generic message if the stream closed without emitting
        // any error.
        final errorEvents =
            _filesToIngest.where((s) => s['status'] == 'error').toList();
        if (errorEvents.isNotEmpty) {
          final last = errorEvents.last;
          final where = last['file'] ?? '';
          final msg = last['message'] ?? '';
          _showError(
            where.toString().isNotEmpty
                ? 'Ingest failed at $where: $msg'
                : 'Ingest failed: $msg',
          );
        } else {
          _showError(
              'Ingest could not complete. Please try again, or contact support if it persists.');
        }
      }

      // The training-wait dialog is meant to span the whole ingest+merge
      // chain (TrainingWaitDialog's own doc comment), not just this request's
      // own SSE read — merge now fires from _subscribeToProperty's listener
      // once the row shows 'Ingested', not from an inline await here, so
      // wait for it to actually signal done before falling through to the
      // dialog-hide in `finally`. Skip the wait if the row was never even
      // created (this request never reached the backend at all) — nothing
      // will ever complete it. Capped so a genuinely stuck backend can't trap
      // the dialog open forever.
      if (!widget.isDev && result != null) {
        await _flowCompleter?.future.timeout(
          const Duration(minutes: 4),
          onTimeout: () {},
        );
      }
    } on TimeoutException {
      _showError("Couldn't reach Alfred. Check your connection and try again.");
    } on ApiException catch (e) {
      _showError(e.userMessage);
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('Failed to fetch') || errStr.contains('ClientException')) {
        await Future.delayed(const Duration(milliseconds: 400));
        _showError("Couldn't reach Alfred. Check your connection and try again.");
      } else {
        _showError('Ingest failed: $e');
      }
    } finally {
      client.close();
      if (showWaitDialog && mounted && !_waitDialogDismissed) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      setState(() => _isIngesting = false);
    }
  }

  void _handleSseEvent(Map<String, dynamic> event) {
    final file = event['file'] as String? ?? '';
    final status = event['status'] as String? ?? '';
    final message = event['message'] as String? ?? '';

    if (status == 'heartbeat' || status == 'stream_closed') return;

    if (file == '(system)' && status == 'property_id') {
      setState(() => _resolvedPropertyId = message);
      _subscribeToProperty(message);
      return;
    }

    setState(() {
      final idx = _filesToIngest.indexWhere((s) => s['file'] == file);
      if (idx >= 0) {
        _filesToIngest[idx] = {'file': file, 'status': status, 'message': message};
      } else {
        _filesToIngest.add({'file': file, 'status': status, 'message': message});
      }
    });
  }

  String? _parseOfficialName(String? markdown) {
    if (markdown == null) return null;
    final match = RegExp(r'\*\*Property Name:\*\*\s*(.+)').firstMatch(markdown);
    final name = match?.group(1)?.trim();
    // Gemini writes this literal placeholder when it can't find a real title —
    // treat it as "no name" so callers fall back to the host's nickname instead
    // of displaying the placeholder as if it were real data.
    if (name == null || name.toLowerCase().startsWith('not specified')) {
      return null;
    }
    return name;
  }

  Future<String?> _getHeroImageUrl(String propertyId) async {
    try {
      return await Supabase.instance.client.storage
          .from('Property_assets')
          .createSignedUrl('$propertyId/hero_image/main.jpg', 3600);
    } catch (_) {
      return null;
    }
  }

  Future<void> _runMerge() async {
    final id = _resolvedPropertyId ?? _propertyId;
    final prevStatus = _propertyStatus;
    setState(() => _isMerging = true);
    try {
      final data = await ApiClient.postJson(
        '/api/merge/$id',
        const {},
        // Merge runs Gemini conflict detection over all sources — can take >60s
        // on Render free tier first-hit, especially with multiple uploaded files.
        timeout: const Duration(seconds: 120),
      );
      final newStatus = data['status'] as String?;
      final newMasterJson = data['master_json'] as Map<String, dynamic>?;
      setState(() {
        _propertyStatus = newStatus;
        _masterJson = newMasterJson;
      });
      if (newStatus == 'Conflict_Pending') {
        final report = (newMasterJson?['conflict_report'] as List<dynamic>?) ?? [];
        await _showConflictDialog(report.length);
      } else {
        await _maybeShowTrainedDialog(prevStatus, newStatus);
      }
    } on ApiException catch (e) {
      _showError(e.userMessage);
    } catch (e) {
      _showError('Merge failed: $e');
    } finally {
      setState(() => _isMerging = false);
      if (_flowCompleter != null && !_flowCompleter!.isCompleted) {
        _flowCompleter!.complete();
      }
    }
  }

  void _onResolved(String status, Map<String, dynamic> masterJson) {
    final prevStatus = _propertyStatus;
    setState(() {
      _propertyStatus = status;
      _masterJson = masterJson;
      _resolutionsSubmitted = false;
    });
    _maybeShowTrainedDialog(prevStatus, status);
  }

  Future<void> _maybeShowTrainedDialog(
      String? prevStatus, String? newStatus) async {
    // Fire on Trained (conflict-resolved path) OR Merged with no conflicts
    // (no-conflict path — terminal state on this screen).
    const triggerStatuses = {'Trained', 'Merged'};
    if (!triggerStatuses.contains(newStatus)) return;
    if (prevStatus == newStatus) return;
    final name =
        _officialPropertyName ?? _nicknameController.text.trim();
    await _showTrainedDialog(name);
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: context.palette.danger,
      duration: const Duration(seconds: 8),
    ));
  }

  Future<void> _showIngestedDialog(String propertyName) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) => Dialog(
        // Opaque surface backing for the dialog. GlassPanel paints a translucent
        // highlight gradient that overrides its own solid `tint`, so a fully
        // transparent dialog let the dimmed barrier bleed through and crushed
        // text contrast. Backing it with the solid surface keeps the soft glass
        // sheen on top while staying readable.
        backgroundColor: context.palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: GlassPanel(
            radius: 24,
            blurSigma: AppTheme.glassBlurSigmaHeavy,
            // Light sheen over the opaque dialog backing above (see Dialog).
            tint: context.palette.glassTintStrong,
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [context.palette.primary, context.palette.accent],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: context.palette.primary.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 34),
                ),
                const SizedBox(height: 18),
                Text(
                  propertyName.isNotEmpty ? propertyName : 'Files Ingested',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w300,
                      color: context.palette.textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Files ingested successfully.',
                  style: GoogleFonts.inter(
                      fontSize: 15,
                      height: 1.5,
                      color: context.palette.textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Next, run Merge to build Alfred’s master knowledge base. If conflicts are detected between your listing and uploaded documents, you’ll be asked to resolve them before training.',
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color: context.palette.textSecondary,
                      height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Center(
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Review Details'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showConflictDialog(int conflictCount) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) => Dialog(
        // Opaque surface backing for the dialog. GlassPanel paints a translucent
        // highlight gradient that overrides its own solid `tint`, so a fully
        // transparent dialog let the dimmed barrier bleed through and crushed
        // text contrast. Backing it with the solid surface keeps the soft glass
        // sheen on top while staying readable.
        backgroundColor: context.palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: GlassPanel(
            radius: 24,
            blurSigma: AppTheme.glassBlurSigmaHeavy,
            // Light sheen over the opaque dialog backing above (see Dialog).
            tint: context.palette.glassTintStrong,
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.palette.warningContainer,
                    boxShadow: [
                      BoxShadow(
                        color: context.palette.warning.withValues(alpha: 0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(Icons.tune_rounded,
                      color: context.palette.warning, size: 32),
                ),
                const SizedBox(height: 18),
                Text(
                  'Almost there — $conflictCount ${conflictCount == 1 ? 'conflict' : 'conflicts'} found',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w300,
                      color: context.palette.textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Alfred merged your information but found $conflictCount ${conflictCount == 1 ? 'point' : 'points'} where your listing and uploaded documents disagree. Review each one and choose the version Alfred should use.',
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color: context.palette.textSecondary,
                      height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Center(
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Resolve Conflicts'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showTrainedDialog(String propertyName) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) => Dialog(
        // Opaque surface backing for the dialog. GlassPanel paints a translucent
        // highlight gradient that overrides its own solid `tint`, so a fully
        // transparent dialog let the dimmed barrier bleed through and crushed
        // text contrast. Backing it with the solid surface keeps the soft glass
        // sheen on top while staying readable.
        backgroundColor: context.palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: GlassPanel(
            radius: 24,
            blurSigma: AppTheme.glassBlurSigmaHeavy,
            // Light sheen over the opaque dialog backing above (see Dialog).
            tint: context.palette.glassTintStrong,
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [context.palette.primary, context.palette.accent],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: context.palette.primary.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 34),
                ),
                const SizedBox(height: 18),
                Text(
                  propertyName.isNotEmpty
                      ? propertyName
                      : 'Property Ready',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w300,
                      color: context.palette.textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Alfred is now trained and ready to take over conversations.',
                  style: GoogleFonts.inter(
                      fontSize: 15,
                      height: 1.5,
                      color: context.palette.textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'He’ll respond on autopilot to incoming guest messages. You can review or intervene anytime from the Dashboard.',
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color: context.palette.textSecondary,
                      height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Center(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Back to Dashboard'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrainingTipsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.palette.successContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.success.withValues(alpha: 0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded,
                  size: 16, color: context.palette.success),
              const SizedBox(width: 8),
              Text('What trains Alfred best',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.palette.success)),
            ],
          ),
          const SizedBox(height: 8),
          for (final tip in kAlfredTrainingTips)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('•  $tip',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      color: context.palette.textSecondary,
                      height: 1.4)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(kAlfredTrainingTipsClosing,
                style: GoogleFonts.inter(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: context.palette.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final label = switch (status) {
      'Ingested' => 'Ingested — Ready to Merge',
      'Merged' => 'Merged',
      'Conflict_Pending' => _resolutionsSubmitted
          ? 'Conflicts Resolved — Pending Update'
          : 'Conflicts Pending Review',
      'Trained' => 'Trained',
      'Fully_Trained' => 'Fully Trained',
      // Any other backend status (e.g. Ingest_Error, a real expected status
      // per setup_status.dart) previously showed the raw enum verbatim —
      // humanize instead of falling through unmapped.
      _ => status.replaceAll('_', ' '),
    };
    // Soft-fill using semantic container tokens (ui-ux-pro-max §6 color-semantic).
    final (bg, fg) = switch (status) {
      'Ingested' => (context.palette.warningContainer, context.palette.warning),
      'Merged' || 'Trained' => (context.palette.successContainer, context.palette.success),
      'Conflict_Pending' => (context.palette.warningContainer, context.palette.warning),
      'Fully_Trained' => (context.palette.primaryContainer, context.palette.onPrimaryContainer),
      _ when status.contains('Error') =>
        (context.palette.dangerContainer, context.palette.danger),
      _ => (context.palette.surfaceAlt, context.palette.textSecondary),
    };
    return Row(
      children: [
        Text('Status:',
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: context.palette.textPrimary)),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg)),
        ),
      ],
    );
  }

  Widget _buildMasterJsonViewer() {
    if (_masterJson == null) return const SizedBox.shrink();
    final prettyJson = const JsonEncoder.withIndent('  ').convert(_masterJson);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Master JSON',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 16),
              tooltip: 'Copy JSON',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: prettyJson));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('JSON copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 400),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(8)),
          child: SingleChildScrollView(
            child: SelectableText(
              prettyJson,
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.5,
                  color: Color(0xFFD4D4D4)),
            ),
          ),
        ),
      ],
    );
  }

  MarkdownStyleSheet _markdownStyleSheet(BuildContext context) {
    final palette = context.palette;
    final cs = Theme.of(context).colorScheme;
    return MarkdownStyleSheet(
      p: TextStyle(color: palette.textPrimary, fontSize: 13, height: 1.6),
      strong: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
      em: TextStyle(color: palette.textPrimary, fontStyle: FontStyle.italic),
      h1: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w300, color: palette.textPrimary),
      h2: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w500, color: palette.textPrimary),
      h3: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w500, color: palette.textPrimary),
      code: TextStyle(
        color: cs.secondary,
        fontFamily: 'monospace',
        fontSize: 12,
        backgroundColor: palette.surfaceAlt,
      ),
      codeblockDecoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      blockquote: TextStyle(color: palette.textSecondary, fontStyle: FontStyle.italic),
      blockquoteDecoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: cs.primary, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.all(12),
      listBullet: TextStyle(color: palette.textPrimary),
      a: TextStyle(color: cs.primary, decoration: TextDecoration.underline),
    );
  }

  @override
  Widget build(BuildContext context) {
    // !_isMerging guards Train Now's auto-chained merge (User mode) — without
    // it the button re-enables the moment ingest finishes, while merge is
    // still silently running in the background. The airbnb. check is a
    // lightweight format guard — previously any non-empty text (a typo, a
    // random link) triggered the full multi-minute Train Now flow before
    // failing with a generic scrape error.
    final urlText = _urlController.text.trim();
    final canIngest = urlText.isNotEmpty &&
        urlText.toLowerCase().contains('airbnb.') &&
        !_isIngesting &&
        !_isMerging;
    final trainingInProgress = _isIngesting || (!widget.isDev && _isMerging);
    final effectiveId = _resolvedPropertyId ?? _propertyId;
    final conflictReport = _masterJson?['conflict_report'] as List<dynamic>?;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: AppBar(
              backgroundColor: context.palette.glassTint,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              title: Text('Add Property',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w300,
                      fontSize: 18,
                      color: context.palette.primary)),
              leading: BackButton(
                color: context.palette.primary,
                // Previously abandoned an in-progress ingest/merge with zero
                // confirmation, likely leaving the property half-created.
                onPressed: () async {
                  if (!trainingInProgress) {
                    Navigator.of(context).pop();
                    return;
                  }
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: context.palette.surface,
                      title: const Text('Leave while training?'),
                      content: const Text(
                          "Alfred is still learning this property. Leaving now "
                          "won't stop it, but you'll need to check back to see "
                          "how it went."),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Stay'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Leave'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && mounted) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
        AuroraBackground(
        intensity: 0.45,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(
              24, kToolbarHeight + 24, 24, 48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: GlassPanel(
                radius: 24,
                blurSigma: AppTheme.glassBlurSigmaHeavy,
                tint: context.palette.glassTintStrong,
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                _walkthroughHighlight(
                  screen: WalkthroughScreen.url,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _nicknameController,
                        decoration: const InputDecoration(
                          labelText: 'Nickname (Optional)',
                          hintText: 'e.g. Beach House Malibu',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _urlController,
                        decoration: const InputDecoration(
                          labelText: 'Airbnb URL *',
                          hintText: 'https://www.airbnb.com/rooms/...',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.url,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                _walkthroughHighlight(
                  screen: WalkthroughScreen.upload,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Upload Files',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      if (_walkthroughScreen == null) ...[
                        _buildTrainingTipsCard(context),
                        const SizedBox(height: 12),
                      ],
                      DropZoneWidget(
                        propertyId: _propertyId,
                        onFileAdded: _onFileAdded,
                        onFileResult: _onFileResult,
                        // Excludes error/timeout entries so a failed upload
                        // can be re-dropped under the same filename instead of
                        // being permanently rejected as "already in the queue"
                        // with no recovery short of renaming the file.
                        isDuplicate: (filename) => _filesToIngest.any((e) =>
                            e['file'] == filename &&
                            e['status'] != 'error' &&
                            e['status'] != 'timeout'),
                      ),
                      const SizedBox(height: 16),
                      VoiceRecorderWidget(
                        propertyId: _propertyId,
                        onFileAdded: _onFileAdded,
                        onRecordingResult: _onFileResult,
                      ),
                    ],
                  ),
                ),
                if (_filesToIngest.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Files',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  FileStatusList(
                    statuses: _filesToIngest,
                    // Only removable before Train Now starts -- once ingest
                    // is running this list is a read-only status display.
                    onRemove: _isIngesting
                        ? null
                        : (index) =>
                            setState(() => _filesToIngest.removeAt(index)),
                  ),
                ],
                const SizedBox(height: 28),
                _walkthroughHighlight(
                  screen: WalkthroughScreen.train,
                  child: FilledButton(
                    onPressed: canIngest ? _startIngest : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.2),
                    ),
                    child: trainingInProgress
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5, color: Colors.white)),
                              const SizedBox(width: 12),
                              // Non-dev never sees "Ingesting" — Train Now is a
                              // single continuous step from their side.
                              Text(!widget.isDev
                                  ? 'Training...'
                                  : (_isIngesting ? 'Ingesting...' : 'Training...')),
                            ],
                          )
                        : Text(widget.isDev ? 'INGEST NOW' : 'TRAIN NOW'),
                  ),
                ),
                if (_ingestedMarkdown != null &&
                    _ingestedMarkdown!.isNotEmpty) ...[
                  const SizedBox(height: 40),
                  const Divider(),
                  const SizedBox(height: 20),
                  if (_heroImageUrl != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        _heroImageUrl!,
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_officialPropertyName != null) ...[
                    Text(_officialPropertyName!,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 24,
                            fontWeight: FontWeight.w300,
                            color: context.palette.textPrimary)),
                    const SizedBox(height: 4),
                  ],
                  if (widget.isDev) ...[
                    Text('Extracted Knowledge',
                        style: TextStyle(
                            fontSize: 13,
                            color: context.palette.textSecondary,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: context.palette.surfaceAlt,
                        border: Border.all(color: context.palette.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: MarkdownBody(
                        data: _ingestedMarkdown!,
                        selectable: true,
                        styleSheet: _markdownStyleSheet(context),
                      ),
                    ),
                  ],
                ],
                if (_propertyStatus != null) ...[
                  const SizedBox(height: 40),
                  const Divider(),
                  const SizedBox(height: 20),
                  _buildStatusBadge(_propertyStatus!),
                  // Only offer merge when files were actually ingested (not just scraped).
                  // User mode never reaches this state — Train Now already chained the
                  // merge automatically — so this button is Dev-only.
                  if (widget.isDev &&
                      _propertyStatus == 'Ingested' &&
                      (_ingestedMarkdown?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _isMerging ? null : _runMerge,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        backgroundColor: context.palette.primary,
                        textStyle: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1.2),
                      ),
                      child: _isMerging
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white)),
                                SizedBox(width: 12),
                                Text('Merging...'),
                              ],
                            )
                          : const Text('MERGE NOW'),
                    ),
                  ],
                  // Conflict resolution comes first — it's the action the host
                  // needs to take before the JSON below it becomes meaningful.
                  if (_propertyStatus == 'Conflict_Pending' &&
                      conflictReport != null &&
                      conflictReport.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Text('Resolve Conflicts',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    ConflictQuestionnaireWidget(
                      key: ValueKey(conflictReport.length),
                      propertyId: effectiveId,
                      conflictReport: conflictReport,
                      onResolved: _onResolved,
                      onAnswersSubmitted: () =>
                          setState(() => _resolutionsSubmitted = true),
                    ),
                  ],
                  if (_postMergeStatuses.contains(_propertyStatus)) ...[
                    if (widget.isDev) ...[
                      const SizedBox(height: 24),
                      _buildMasterJsonViewer(),
                    ],
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.dashboard_outlined, size: 18),
                      label: const Text('Back to Dashboard'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: context.palette.primary,
                        side: BorderSide(
                            color: context.palette.primaryContainer, width: 1.5),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 16),
              ],
                ),
              ),
            ),
          ),
        ),
        ),
        if (_walkthroughScreen != null && MediaQuery.of(context).size.width >= 1000)
          Positioned(
            right: 24,
            top: kToolbarHeight + 40,
            width: 300,
            child: AddPropertyWalkthroughPanel(
              current: _walkthroughScreen!,
              onScreenChange: _goToWalkthroughScreen,
              onDismiss: _dismissWalkthrough,
            ),
          ),
        ],
      ),
    );
  }
}
