import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  // Same guard for the dev-mode "Files Ingested" dialog.
  bool _ingestedDialogShown = false;
  // True once ingest_heartbeat_at has gone stale while status is still one
  // of the "live" set (Ingesting/Ingested/Merging) — the background worker
  // (Phase 2, 2026-09-16) has genuinely gone quiet, not just slow. Drives the
  // Resume Training affordance instead of an indefinite spinner.
  bool _isStalled = false;
  bool _resuming = false;
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

  // Phase 2 (2026-09-16): file/scrape/merge processing all runs in background
  // Cloud Tasks workers now (routers/ingest_worker.py), not inside the
  // /api/ingest request — so this realtime listener on the property row is
  // the ONLY source of truth for progress, not a fallback for a dropped SSE
  // connection. ingest_files (jsonb, per-file state/attempts/error) replaces
  // the old file_fingerprints-presence heuristic: failures are recorded
  // directly by the backend now instead of being inferred from absence once
  // the batch looked concluded. Merge also fires automatically server-side
  // once ingest completes (routers/ingest_worker.run_merge_step) — this
  // screen no longer calls /api/merge itself for the Train Now chain.
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
      final ingestFiles = row['ingest_files'] as Map<String, dynamic>? ?? {};
      final heartbeat = row['ingest_heartbeat_at'] as String?;
      final ingested = row['ingested_markdown'] as String?;
      final scraped = row['scraped_markdown'] as String?;
      const liveStatuses = {'Ingesting', 'Ingested', 'Merging'};
      final stillLive = liveStatuses.contains(status);
      final stalled = stillLive && _heartbeatStale(heartbeat);
      setState(() {
        _propertyStatus = status;
        _ingestedMarkdown = ingested ?? _ingestedMarkdown;
        _masterJson =
            (row['master_json'] as Map<String, dynamic>?) ?? _masterJson;
        _isStalled = stalled;
        _applyIngestFiles(ingestFiles);
        if (!stillLive) _isIngesting = false;
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
      }
      // The wait dialog spans the whole ingest+merge chain regardless of
      // dev/non-dev now (both auto-chain server-side) — complete the
      // Completer, and therefore close the dialog, once the run reaches a
      // real terminal state OR is confirmed stalled. Stalling used to be
      // detected by a fixed 6-minute client-side timer; this is the real
      // backend signal instead, so it can fire earlier (a genuine hang) or
      // never (a run that's just slow but still alive).
      const terminalStatuses = {
        'Merged', 'Conflict_Pending', 'Trained', 'Fully_Trained', 'Ingest_Error',
      };
      if (_flowCompleter != null &&
          !_flowCompleter!.isCompleted &&
          (terminalStatuses.contains(status) || stalled)) {
        _flowCompleter!.complete();
      }
    });
  }

  // Replaces each _filesToIngest entry with its authoritative state from the
  // backend's ingest_files map. Entries not yet present in ingest_files
  // (e.g. still mid-upload, Train Now not clicked yet) are left untouched.
  void _applyIngestFiles(Map<String, dynamic> ingestFiles) {
    for (final entry in ingestFiles.entries) {
      final name = entry.key;
      final info = entry.value as Map<String, dynamic>? ?? {};
      final state = info['state'] as String? ?? 'pending';
      final attempts = info['attempts'] as int? ?? 1;
      final error = info['error'] as String?;
      final status = switch (state) {
        'pending' => 'queued',
        'running' => 'processing',
        'done' => 'done',
        'skipped' => 'already_in_db',
        'failed' => 'error',
        _ => 'queued',
      };
      final message = switch (state) {
        'failed' => error ?? "Couldn't be processed — try again",
        'running' when attempts > 1 => 'Retrying (attempt $attempts)…',
        _ => '',
      };
      final idx = _filesToIngest.indexWhere((f) => f['file'] == name);
      final row = {'file': name, 'status': status, 'message': message};
      if (idx >= 0) {
        _filesToIngest[idx] = row;
      } else {
        _filesToIngest.add(row);
      }
    }
  }

  bool _heartbeatStale(String? heartbeatIso) {
    if (heartbeatIso == null) return true;
    final ts = DateTime.tryParse(heartbeatIso);
    if (ts == null) return true;
    // Matches ingest_worker.py's STALE_HEARTBEAT_S — same threshold the
    // backend watchdog uses, so the UI and the automatic recovery agree on
    // when a run is genuinely stuck vs. just slow.
    return DateTime.now().toUtc().difference(ts.toUtc()) >
        const Duration(seconds: 90);
  }

  Future<void> _resumeTraining() async {
    if (_resuming) return;
    setState(() => _resuming = true);
    final id = _resolvedPropertyId ?? _propertyId;
    try {
      final session = Supabase.instance.client.auth.currentSession;
      await ApiClient.postJson(
        '/api/ingest/$id/resume',
        const {},
        bearer: session?.accessToken,
      );
      // No local state update here on purpose — _subscribeToProperty's
      // listener picks up the resumed run's progress the moment the backend
      // writes it, same as every other state change on this screen.
    } on ApiException catch (e) {
      _showError(e.userMessage);
    } catch (e) {
      _showError('Resume failed: $e');
    } finally {
      if (mounted) setState(() => _resuming = false);
    }
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
      _isStalled = false;
      _waitDialogDismissed = false;
      _resolvedPropertyId = null;
      _ingestedMarkdown = null;
      _officialPropertyName = null;
      _heroImageUrl = null;
      _propertyStatus = null;
      _masterJson = null;
      _ingestedDialogShown = false;
    });

    // Start watching the row immediately, using the ID this client already
    // generated (initState) — the dispatcher resolves the canonical
    // property_id (a rename onto an existing same-named property) before it
    // even mints a run, so _propertyId is already correct for the common
    // case; the POST response below still re-subscribes if the resolved ID
    // ever differs (the rename case).
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

    // Phase 2 (2026-09-16): POST /api/ingest is now a bounded, sub-second
    // dispatcher — it mints a background run and returns immediately. All
    // actual file/scrape/merge processing happens in Cloud Tasks workers and
    // is observed entirely through _subscribeToProperty's realtime listener
    // (started above), not through this request's own response. This
    // replaces the old SSE-stream read plus its three separate client-side
    // timeouts (20s connect / 90s stream / 6min completer) with one plain
    // POST whose only job is confirming the dispatch itself succeeded.
    try {
      final session = Supabase.instance.client.auth.currentSession;
      final data = await ApiClient.postJson(
        '/api/ingest',
        {
          'property_id': _propertyId,
          'property_name': _nicknameController.text.trim(),
          'airbnb_url': url,
        },
        bearer: session?.accessToken,
        timeout: const Duration(seconds: 20),
      );
      final resolvedId = data['property_id'] as String?;
      if (resolvedId != null && resolvedId != _propertyId) {
        setState(() => _resolvedPropertyId = resolvedId);
        _subscribeToProperty(resolvedId);
      }
      // Wait for the real end of the chain — a genuine terminal status, or a
      // confirmed-stale heartbeat (_subscribeToProperty completes this in
      // both cases; see its own comment). No client-side cap needed: the
      // backend's own watchdog is what used to be a blind 6-minute timer.
      await _flowCompleter?.future;
    } on ApiException catch (e) {
      _showError(e.userMessage);
    } catch (e) {
      _showError("Couldn't reach Alfred. Check your connection and try again.");
    } finally {
      if (showWaitDialog && mounted && !_waitDialogDismissed) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (_isStalled && mounted) {
        _showInfo(
            "This is taking longer than usual. Alfred is still working -- you can resume it from this screen or check back on the dashboard.");
      }
      setState(() => _isIngesting = false);
    }
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

  // Non-error status update -- distinct from _showError's danger styling so
  // "still working, nothing's wrong" never reads as a failure.
  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: context.palette.accent,
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

  // Item 3 (recovery for a genuinely stuck backend) + item 1 (partial-failure
  // summary), Phase 2, 2026-09-16. Two independent conditions, both resolved
  // via the same /resume endpoint: a stalled run (heartbeat gone quiet) needs
  // a way to un-stick it; a finished run with some files failed needs a
  // visible summary plus a real retry, not a silent gap the host only
  // notices later. Returns an empty box when neither applies.
  Widget _buildRecoveryBanner(BuildContext context) {
    final failedCount =
        _filesToIngest.where((f) => f['status'] == 'error').length;
    if (!_isStalled && failedCount == 0) return const SizedBox.shrink();

    final palette = context.palette;
    final String headline;
    final String subtext;
    if (_isStalled) {
      headline = 'Taking longer than usual';
      subtext = "Alfred's still working on this, but it's been quiet longer "
          'than expected. You can resume it now instead of waiting.';
    } else {
      final total = _filesToIngest.length;
      headline = failedCount == 1
          ? "1 of $total file couldn't be processed"
          : '$failedCount of $total files couldn\'t be processed';
      subtext = 'Alfred retried automatically before giving up on these. '
          'You can try again.';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.warningContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.warning.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: palette.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(headline,
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtext,
                      style: GoogleFonts.inter(
                          fontSize: 12, color: palette.textSecondary)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 32,
                    child: OutlinedButton(
                      onPressed: _resuming ? null : _resumeTraining,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.warning,
                        side: BorderSide(color: palette.warning),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      child: _resuming
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: palette.warning),
                            )
                          : Text(_isStalled ? 'Resume Training' : 'Retry',
                              style: GoogleFonts.inter(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
                _buildRecoveryBanner(context),
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
