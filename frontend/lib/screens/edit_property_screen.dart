import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/setup_status.dart';
import '../widgets/drop_zone.dart';
import '../widgets/file_thumbnail.dart';
import '../widgets/setup_status_banner.dart';
import '../widgets/voice_recorder.dart';
import '../widgets/file_status_list.dart';
import '../widgets/conflict_questionnaire.dart';
import '../widgets/training_wait_dialog.dart';

class EditPropertyScreen extends StatefulWidget {
  final Map<String, dynamic> property;
  final bool isDev;

  const EditPropertyScreen({
    super.key,
    required this.property,
    this.isDev = false,
  });

  @override
  State<EditPropertyScreen> createState() => _EditPropertyScreenState();
}

class _EditPropertyScreenState extends State<EditPropertyScreen> {
  late final TextEditingController _nicknameController;
  late final String _propertyId;
  late Map<String, String> _existingFiles;
  final Set<String> _deletedFiles = {};
  bool _isIngesting = false;
  bool _isMerging = false;
  bool _isDeletingFile = false;
  // True once the host taps TrainingWaitDialog's "Continue in background" —
  // guards _hideTrainingWaitDialog's pop() so it doesn't try to pop a dialog
  // that's already gone.
  bool _waitDialogDismissed = false;
  // Tracks whether a TrainingWaitDialog is actually on screen right now —
  // needed once User-mode ingest auto-chains into merge (each phase used to
  // show/hide its own dialog independently, one click apart; chaining them
  // means the ingest phase may already have closed its dialog before the
  // outer finally runs). Without this, _hideTrainingWaitDialog's pop() could
  // fire with no dialog left to pop, closing the whole screen instead.
  bool _waitDialogOpen = false;
  // Single list, tracked from upload through ingestion completion — status
  // updates in place (queued → processing → done/error) rather than a second
  // "Files Ingested" list appearing below a frozen first one.
  final List<Map<String, String>> _filesToIngest = [];
  String? _ingestedMarkdown;
  String? _propertyStatus;
  Map<String, dynamic>? _masterJson;
  StreamSubscription<List<Map<String, dynamic>>>? _propertySub;
  // Guards the auto-merge-on-Ingested trigger below so a realtime row update
  // (which can fire more than once) doesn't queue a second merge call.
  bool _autoMergeTriggered = false;

  static const _postMergeStatuses = {
    'Merged',
    'Conflict_Pending',
    'Trained',
    'Fully_Trained',
  };

  @override
  void initState() {
    super.initState();
    _propertyId = widget.property['id'] as String;
    _nicknameController = TextEditingController(
        text: widget.property['name'] as String? ?? '');
    final raw = widget.property['file_fingerprints'] as Map<String, dynamic>? ?? {};
    _existingFiles = raw.map((k, v) => MapEntry(k, v.toString()));
    _propertyStatus = widget.property['status'] as String?;
    _masterJson = widget.property['master_json'] as Map<String, dynamic>?;
    _subscribeToProperty();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _propertySub?.cancel();
    super.dispose();
  }

  // The screen previously only knew a run had finished when its own
  // in-flight ingest/merge HTTP call resolved — if that connection dropped
  // (or the host reloaded mid-run) the screen was stuck showing "Processing"
  // forever even though the backend had actually finished. Watching the row
  // directly means the UI follows the real state regardless of what happens
  // to any single request.
  void _subscribeToProperty() {
    _propertySub = Supabase.instance.client
        .from('properties')
        .stream(primaryKey: ['id'])
        .eq('id', _propertyId)
        .listen((rows) {
      if (!mounted || rows.isEmpty) return;
      final row = rows.first;
      final status = row['status'] as String?;
      final raw = row['file_fingerprints'] as Map<String, dynamic>? ?? {};
      setState(() {
        _propertyStatus = status;
        _existingFiles = raw.map((k, v) => MapEntry(k, v.toString()));
        _masterJson = row['master_json'] as Map<String, dynamic>?;
        _ingestedMarkdown = row['ingested_markdown'] as String? ?? _ingestedMarkdown;
        // A file can still succeed on a later backend-side retry after this
        // browser's own connection stopped watching (seen live 2026-09-15) —
        // file_fingerprints is the authoritative record. Never show a failure
        // word for a file that isn't actually confirmed failed yet: while the
        // batch is still 'Ingesting', an unresolved file just stays
        // "Processing…"; only once the whole run has genuinely finished
        // (status left 'Ingesting') and it's still missing do we call it
        // failed — the host should only ever see one, final verdict per file.
        final batchConcluded = status != 'Ingesting' && status != 'Training';
        for (var i = 0; i < _filesToIngest.length; i++) {
          final f = _filesToIngest[i];
          final succeeded = _existingFiles.containsKey(f['file']);
          if (succeeded && f['status'] != 'done') {
            _filesToIngest[i] = {'file': f['file']!, 'status': 'done', 'message': ''};
          } else if (!succeeded &&
              batchConcluded &&
              (f['status'] == 'queued' || f['status'] == 'processing')) {
            _filesToIngest[i] = {
              'file': f['file']!,
              'status': 'error',
              'message': "Couldn't be processed — try again",
            };
          }
        }
        // A stuck local call (dropped connection) never clears these on its
        // own once the row shows a resolved status — clear them here too.
        // Merge has no distinct in-progress status server-side (status stays
        // 'Ingested' throughout), so any status change away from it means
        // whatever merge was running — local or stale — has concluded.
        if (status != 'Ingesting' && status != 'Training') _isIngesting = false;
        if (status != 'Ingested') _isMerging = false;
      });
      if (!widget.isDev &&
          status == 'Ingested' &&
          !_autoMergeTriggered &&
          !_isMerging) {
        _autoMergeTriggered = true;
        _confirmAndMerge();
      }
      if (status != 'Ingested') _autoMergeTriggered = false;
    });
  }

  Future<void> _deleteExistingFile(String filename) async {
    setState(() => _isDeletingFile = true);
    try {
      await Supabase.instance.client.storage
          .from('Property_assets')
          .remove(['$_propertyId/user_uploads/$filename']);
    } catch (_) {
      // Storage delete may fail if file doesn't exist — continue anyway
    }
    try {
      final updated = Map<String, String>.from(_existingFiles)..remove(filename);
      await Supabase.instance.client
          .from('properties')
          .update({'file_fingerprints': updated})
          .eq('id', _propertyId);
      if (mounted) setState(() {
        _existingFiles = updated;
        _deletedFiles.add(filename);
      });
    } catch (e) {
      _showError('Failed to remove file: $e');
    } finally {
      if (mounted) setState(() => _isDeletingFile = false);
    }
  }

  Future<void> _confirmDeleteFile(String filename) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove File'),
        content: Text(
            'Remove "$filename" from this property? The file\'s extracted content will remain until you re-ingest.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: context.palette.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _deleteExistingFile(filename);
  }

  void _onFileAdded(String filename) {
    setState(() {
      final idx = _filesToIngest.indexWhere((e) => e['file'] == filename);
      final entry = {'file': filename, 'status': 'processing', 'message': ''};
      // Update in place if this filename is already in the list (e.g. from a
      // completed previous batch, now no longer cleared away) rather than
      // adding a second row for the same file.
      if (idx >= 0) {
        _filesToIngest[idx] = entry;
      } else {
        _filesToIngest.add(entry);
      }
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

  // Shown for the duration of a User-mode Retry (ingest) or Merge run — each
  // is its own guided-banner click/wait here (unlike Add Property's single
  // continuous Train Now), so each gets its own popup around its own span.
  // Dev mode keeps its plain button spinner, no popup.
  void _showTrainingWaitDialog() {
    if (widget.isDev || !mounted) return;
    _waitDialogDismissed = false;
    _waitDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: AppTheme.trainingBarrierColor,
      builder: (_) => TrainingWaitDialog(
        onRunInBackground: () => _waitDialogDismissed = true,
      ),
    );
  }

  void _hideTrainingWaitDialog() {
    if (widget.isDev || !mounted || _waitDialogDismissed || !_waitDialogOpen) {
      return;
    }
    _waitDialogOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _startIngest() async {
    if (_isIngesting) return;

    setState(() {
      _isIngesting = true;
      _ingestedMarkdown = null;
      _propertyStatus = null;
      _masterJson = null;
    });
    _showTrainingWaitDialog();

    // Previously fell back to 'http://localhost:8000' if BACKEND_URL was
    // unset, bypassing ApiClient's fail-loud config guard — matches
    // add_property_screen.dart's _startIngest pattern now.
    final String backendUrl;
    try {
      backendUrl = ApiClient.backendUrl;
    } on ConfigurationException catch (e) {
      _showError(e.userMessage);
      _hideTrainingWaitDialog();
      if (mounted) setState(() => _isIngesting = false);
      return;
    }
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
        'airbnb_url': widget.property['airbnb_url'] as String? ?? '',
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
      // connection ended before hearing back — not that the file failed.
      // The backend keeps working regardless (confirmed live 2026-09-15:
      // a file that looked "timed out" here had actually succeeded by the
      // time the batch finished). Leaving it as "Processing…" instead of
      // guessing "Timeout" avoids telling the host something failed when it
      // hasn't been confirmed either way — _subscribeToProperty's listener
      // resolves it to its real final state once the property row updates.

      final result = await Supabase.instance.client
          .from('properties')
          .select('ingested_markdown, status, master_json, file_fingerprints')
          .eq('id', _propertyId)
          .maybeSingle();

      if (result != null) {
        final raw = result['file_fingerprints'] as Map<String, dynamic>? ?? {};
        if (mounted) {
          setState(() {
            _ingestedMarkdown = result['ingested_markdown'] as String?;
            _propertyStatus = result['status'] as String?;
            _masterJson = result['master_json'] as Map<String, dynamic>?;
            _existingFiles = raw.map((k, v) => MapEntry(k, v.toString()));
            // _filesToIngest is intentionally left as-is here (not cleared) —
            // its entries now show each file's final done/error/timeout status
            // from this run, which the host needs to see, especially on a
            // partial failure. _existingFiles above remains the authoritative
            // "what's actually stored" list regardless. (Any stale error/
            // timeout label gets reconciled by _subscribeToProperty's
            // listener once the row updates.)
          });
        }
        // Retrain (User mode) auto-chains into merge once the property row
        // itself shows 'Ingested' — handled by _subscribeToProperty's
        // listener, not here, so it still fires even if this specific call
        // never makes it back (dropped connection, reload, etc.).
      }
    } on TimeoutException {
      _showError("Couldn't reach Alfred. Check your connection and try again.");
    } catch (e) {
      _showError('Ingest failed: $e');
    } finally {
      client.close();
      _hideTrainingWaitDialog();
      if (mounted) setState(() => _isIngesting = false);
    }
  }

  void _handleSseEvent(Map<String, dynamic> event) {
    final file = event['file'] as String? ?? '';
    final status = event['status'] as String? ?? '';
    final message = event['message'] as String? ?? '';
    if (status == 'heartbeat' || status == 'stream_closed') return;
    if (file == '(system)') return;
    setState(() {
      final idx = _filesToIngest.indexWhere((s) => s['file'] == file);
      final entry = {'file': file, 'status': status, 'message': message};
      if (idx >= 0) {
        _filesToIngest[idx] = entry;
      } else {
        _filesToIngest.add(entry);
      }
    });
  }

  // Guards the transition into merge: a permanently-failed file (exhausted
  // its retries) still lets the batch as a whole reach "Ingested" server-side
  // (backend/routers/ingest.py — partial failures don't block training), but
  // that file's content silently never makes it in. Surface that instead of
  // letting it pass unnoticed.
  bool get _hasFailedFiles => _filesToIngest
      .any((f) => f['status'] == 'error' || f['status'] == 'timeout');

  // Returns true if it's fine to proceed to merge — either nothing failed,
  // or the host explicitly chose to continue anyway.
  Future<bool> _confirmFailedFiles() async {
    if (!_hasFailedFiles) return true;
    final failedNames = _filesToIngest
        .where((f) => f['status'] == 'error' || f['status'] == 'timeout')
        .map((f) => f['file'])
        .join(', ');
    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Some files didn't finish"),
        content: Text(
            '$failedNames couldn\'t be processed and won\'t be included. '
            'Continue training with what succeeded, or go back and retry '
            'the file first?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Go Back')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return proceed == true;
  }

  // Dev's manual "Merge Now" button / a non-dev fallback from the guided
  // banner — either way, still gate on failed files first.
  Future<void> _confirmAndMerge() async {
    if (!await _confirmFailedFiles()) return;
    await _runMerge();
  }

  Future<void> _runMerge() async {
    setState(() => _isMerging = true);
    _showTrainingWaitDialog();
    try {
      final data = await ApiClient.postJson(
        '/api/merge/$_propertyId',
        const {},
        // Merge runs Gemini conflict detection over all sources — can take >60s
        // on Render free tier first-hit, especially with multiple uploaded files.
        timeout: const Duration(seconds: 120),
      );
      setState(() {
        _propertyStatus = data['status'] as String?;
        _masterJson = data['master_json'] as Map<String, dynamic>?;
      });
    } on ApiException catch (e) {
      _showError(e.userMessage);
    } catch (e) {
      _showError('Merge failed: $e');
    } finally {
      _hideTrainingWaitDialog();
      if (mounted) setState(() => _isMerging = false);
    }
  }

  void _onResolved(String status, Map<String, dynamic> masterJson) {
    setState(() {
      _propertyStatus = status;
      _masterJson = masterJson;
    });
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: context.palette.danger));
  }

  static const _trainedStatuses = {'Trained', 'Active', 'Resolved', 'Merged'};

  void _handleNextStepAction(SetupStep step) {
    // Dispatch per-status action: for most steps, the screen itself is the action
    // (user uploads files, clicks RE-INGEST, or resolves conflicts here)
    final status = _propertyStatus ?? '';
    if (_trainedStatuses.contains(status) &&
        _filesToIngest.any((f) => f['status'] == 'queued')) {
      // Same re-ingest call as the Ingest_Error retry below — a newly added
      // file on an already-trained property needs the identical trigger.
      _startIngest();
    } else if (status == 'Scraped') {
      // With the manual RE-INGEST button hidden (User mode), this is the only
      // way to kick off ingestion once files are queued — a no-op before that.
      if (_filesToIngest.any((f) => f['status'] == 'queued')) _startIngest();
    } else if (status == 'Ingested') {
      _confirmAndMerge();
    } else if (status == 'Ingest_Error') {
      _startIngest();
    }
    // Conflict_Pending: conflicts panel is visible below; Merged: no train endpoint yet
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
    final canIngest = _filesToIngest.any((f) => f['status'] == 'queued') && !_isIngesting;
    final conflictReport = _masterJson?['conflict_report'] as List<dynamic>?;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Property'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Guided next-step banner. _isIngesting/_isMerging null out
                // _propertyStatus for the duration of the call (see _startIngest/
                // _runMerge), so nextStepFor() alone would go blank mid-flight —
                // show an explicit processing state instead.
                Builder(builder: (ctx) {
                  final step = _isIngesting || _isMerging
                      ? SetupStep(
                          headline: _isIngesting
                              ? 'Processing files…'
                              : 'Building the master profile…',
                          subtext: _isIngesting
                              ? 'Alfred is reading your files. This usually takes 30–60 seconds.'
                              : 'Merging your data into one profile. This can take a moment.',
                          actionLabel: '',
                          icon: Icons.hourglass_top_rounded,
                          accent: (c) => Theme.of(c).colorScheme.secondary,
                          isProcessing: true,
                        )
                      : nextStepFor(
                          _propertyStatus ?? '',
                          hasMasterJson: _masterJson != null,
                          hasQueuedFiles: _filesToIngest
                              .any((f) => f['status'] == 'queued'),
                          isDev: widget.isDev,
                        );
                  if (step == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: SetupStatusBanner(
                      step: step,
                      onAction: () => _handleNextStepAction(step),
                    ),
                  );
                }),

                // Property name (editable)
                TextField(
                  controller: _nicknameController,
                  decoration: const InputDecoration(
                    labelText: 'Property Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                // Airbnb URL (clickable)
                if ((widget.property['airbnb_url'] as String?)?.isNotEmpty ?? false)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => launchUrl(
                        Uri.parse(widget.property['airbnb_url'] as String),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.property['airbnb_url'] as String,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.open_in_new_rounded,
                              size: 12,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Existing files
                const SizedBox(height: 16),
                Text('Ingested Files',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (_existingFiles.isEmpty && _deletedFiles.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('No files ingested yet.',
                        style: TextStyle(color: context.palette.textSecondary, fontSize: 13)),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: context.palette.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        // Active files
                        ..._existingFiles.entries.map((e) {
                          return ListTile(
                            dense: true,
                            leading: FileThumbnail(
                              propertyId: _propertyId,
                              fileName: e.key,
                              size: 32,
                            ),
                            title: Text(e.key,
                                style: const TextStyle(fontSize: 13)),
                            trailing: _isDeletingFile
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2))
                                : IconButton(
                                    icon: Icon(Icons.delete_outline,
                                        size: 18, color: context.palette.danger),
                                    tooltip: 'Remove file',
                                    onPressed: () => _confirmDeleteFile(e.key),
                                  ),
                          );
                        }),
                        // Deleted files (visual tombstones)
                        ..._deletedFiles.map((filename) {
                          return ListTile(
                            dense: true,
                            leading: Icon(Icons.remove_circle_outline,
                                size: 18, color: context.palette.danger),
                            title: Text(
                              filename,
                              style: TextStyle(
                                fontSize: 13,
                                color: context.palette.textMuted,
                                decoration: TextDecoration.lineThrough,
                                decorationColor: context.palette.textMuted,
                              ),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: context.palette.dangerContainer,
                                border: Border.all(color: context.palette.danger.withValues(alpha: 0.4)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('Removed',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: context.palette.danger,
                                      fontWeight: FontWeight.w500)),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),

                // Out-of-date warning banner
                if (_deletedFiles.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.palette.warningContainer,
                      border: Border.all(color: context.palette.warning.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: context.palette.warning, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'The knowledge database still contains data extracted from removed files. '
                            'Add new files below and re-ingest to keep the knowledge base up to date.',
                            style: TextStyle(
                                fontSize: 12, color: context.palette.warning),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Add new files
                const SizedBox(height: 24),
                Text('Add New Files',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                DropZoneWidget(
                  propertyId: _propertyId,
                  onFileAdded: _onFileAdded,
                  onFileResult: _onFileResult,
                ),
                const SizedBox(height: 16),
                VoiceRecorderWidget(
                  propertyId: _propertyId,
                  onFileAdded: _onFileAdded,
                  onRecordingResult: _onFileResult,
                ),
                if (_filesToIngest.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  FileStatusList(statuses: _filesToIngest),
                ],

                // Re-ingest button — Dev only; User mode drives this from the
                // guided banner above instead (see _handleNextStepAction).
                if (widget.isDev) ...[
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: canIngest ? _startIngest : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.4),
                    ),
                    child: _isIngesting
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5, color: Colors.white)),
                              SizedBox(width: 12),
                              Text('Ingesting...'),
                            ],
                          )
                        : const Text('RE-INGEST'),
                  ),
                ],

                if (widget.isDev &&
                    _ingestedMarkdown != null &&
                    _ingestedMarkdown!.isNotEmpty) ...[
                  const SizedBox(height: 40),
                  const Divider(),
                  const SizedBox(height: 20),
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
                if (_propertyStatus != null) ...[
                  const SizedBox(height: 40),
                  const Divider(),
                  const SizedBox(height: 20),
                  // Dev only — User mode's banner already chains straight into
                  // merge from _handleNextStepAction's 'Ingested' case.
                  if (widget.isDev &&
                      _propertyStatus == 'Ingested' &&
                      (_ingestedMarkdown?.isNotEmpty ?? false)) ...[
                    FilledButton(
                      onPressed: _isMerging ? null : _confirmAndMerge,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        backgroundColor: context.palette.primary,
                        textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.4),
                      ),
                      child: _isMerging
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5, color: Colors.white)),
                                SizedBox(width: 12),
                                Text('Merging...'),
                              ],
                            )
                          : const Text('MERGE NOW'),
                    ),
                  ],
                  // Conflict resolution first — the action — then the JSON below.
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
                      propertyId: _propertyId,
                      conflictReport: conflictReport,
                      onResolved: _onResolved,
                    ),
                  ],
                  if (_postMergeStatuses.contains(_propertyStatus)) ...[
                    // Non-dev previously had no completion state here at all —
                    // once a retrain finished, the whole block below was
                    // isDev-gated, leaving them on the form with no signal it
                    // was done and no way back.
                    if (!widget.isDev) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.palette.accentContainer,
                          border: Border.all(color: context.palette.accent.withValues(alpha: 0.4)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_rounded, color: context.palette.accent, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text('Alfred is up to date with your latest files.',
                                  style: TextStyle(color: context.palette.textPrimary, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.dashboard_outlined, size: 18),
                        label: const Text('Back to Dashboard'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          foregroundColor: context.palette.primary,
                          side: BorderSide(color: context.palette.primaryContainer, width: 1.5),
                        ),
                      ),
                    ],
                    if (widget.isDev && _masterJson != null) ...[
                      const SizedBox(height: 24),
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
                              final jsonStr = const JsonEncoder.withIndent('  ')
                                  .convert(_masterJson);
                              Clipboard.setData(ClipboardData(text: jsonStr));
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
                            const JsonEncoder.withIndent('  ').convert(_masterJson),
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                height: 1.5,
                                color: Color(0xFFD4D4D4)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
