import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  // The specific route this screen's own wait dialog was pushed as — closed
  // via popTrainingWaitDialog (removeRoute), not a blind Navigator.pop(),
  // since dashboard_screen.dart can now independently push its own result
  // dialog on the same root navigator while this dialog is still open; a
  // blind pop() here could close that one instead and strand this one.
  Route<void>? _waitDialogRoute;
  // Single list, tracked from upload through ingestion completion — status
  // updates in place (queued → processing → done/error) rather than a second
  // "Files Ingested" list appearing below a frozen first one.
  final List<Map<String, String>> _filesToIngest = [];
  String? _ingestedMarkdown;
  String? _propertyStatus;
  Map<String, dynamic>? _masterJson;
  StreamSubscription<List<Map<String, dynamic>>>? _propertySub;
  // Polling backstop alongside _propertySub — see _subscribeToProperty.
  Timer? _pollTimer;
  // Spans the whole ingest+merge chain for the wait dialog (Phase 2,
  // 2026-09-16 — merge now fires server-side automatically, so this screen
  // no longer needs its old two-separate-dialogs-per-phase handling).
  Completer<void>? _flowCompleter;
  // True once ingest_heartbeat_at has gone stale while status is still live
  // (Ingesting/Ingested/Merging) — see _heartbeatStale.
  bool _isStalled = false;
  bool _resuming = false;

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
    _pollTimer?.cancel();
    super.dispose();
  }

  // Phase 2 (2026-09-16): file/scrape/merge processing all runs in background
  // Cloud Tasks workers now (routers/ingest_worker.py), not inside the
  // /api/ingest request — so this realtime listener on the property row is
  // the ONLY source of truth for progress, not a fallback for a dropped
  // connection/reload. ingest_files (jsonb, per-file state/attempts/error)
  // replaces the old file_fingerprints-presence heuristic: failures are
  // recorded directly by the backend now instead of inferred from absence
  // once the batch looked concluded. Merge also fires automatically
  // server-side once ingest completes — this screen no longer calls
  // /api/merge itself for the User-mode chain (Dev keeps its manual button).
  void _subscribeToProperty() {
    _propertySub = Supabase.instance.client
        .from('properties')
        .stream(primaryKey: ['id'])
        .eq('id', _propertyId)
        .listen((rows) {
      if (rows.isEmpty) return;
      _applyPropertyRow(rows.first);
    });
  }

  // Polling backstop, added 2026-09-16 after a real live run on
  // add_property_screen.dart: a realtime subscription can silently never
  // deliver a single event for a run's whole duration, with zero
  // client-visible error — confirmed live (backend finished completely and
  // correctly; the screen watching it sat frozen the entire time). Started
  // alongside _startIngest, stopped once the run concludes — see
  // add_property_screen.dart's _subscribeToProperty for the full writeup.
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      // _resuming added 2026-09-17 -- _resumeTraining reuses this same
      // backstop now that it also waits on _flowCompleter.
      if (!mounted || !(_isIngesting || _resuming)) {
        _pollTimer?.cancel();
        return;
      }
      try {
        final row = await Supabase.instance.client
            .from('properties')
            .select()
            .eq('id', _propertyId)
            .maybeSingle();
        if (row != null) _applyPropertyRow(row);
      } catch (_) {
        // Best-effort backstop only — the next tick retries.
      }
    });
  }

  void _applyPropertyRow(Map<String, dynamic> row) {
    if (!mounted) return;
    final status = row['status'] as String?;
    final raw = row['file_fingerprints'] as Map<String, dynamic>? ?? {};
    final ingestFiles = row['ingest_files'] as Map<String, dynamic>? ?? {};
    final heartbeat = row['ingest_heartbeat_at'] as String?;
    const liveStatuses = {'Ingesting', 'Ingested', 'Merging'};
    final stillLive = liveStatuses.contains(status);
    final stalled = stillLive && _heartbeatStale(heartbeat);
    setState(() {
      _propertyStatus = status;
      _existingFiles = raw.map((k, v) => MapEntry(k, v.toString()));
      _masterJson = row['master_json'] as Map<String, dynamic>?;
      _ingestedMarkdown = row['ingested_markdown'] as String? ?? _ingestedMarkdown;
      _isStalled = stalled;
      _applyIngestFiles(ingestFiles);
      if (!stillLive) _isIngesting = false;
      if (status != 'Ingested') _isMerging = false;
    });
    const terminalStatuses = {
      'Merged', 'Conflict_Pending', 'Trained', 'Fully_Trained', 'Ingest_Error',
    };
    if (_flowCompleter != null &&
        !_flowCompleter!.isCompleted &&
        (terminalStatuses.contains(status) || stalled)) {
      _flowCompleter!.complete();
      _pollTimer?.cancel();
    }
  }

  // Replaces each _filesToIngest entry with its authoritative state from the
  // backend's ingest_files map. Entries not yet present in ingest_files
  // (e.g. still mid-upload, before Re-ingest is clicked) are left untouched.
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
      final entryRow = {'file': name, 'status': status, 'message': message};
      if (idx >= 0) {
        _filesToIngest[idx] = entryRow;
      } else {
        _filesToIngest.add(entryRow);
      }
    }
  }

  bool _heartbeatStale(String? heartbeatIso) {
    if (heartbeatIso == null) return true;
    final ts = DateTime.tryParse(heartbeatIso);
    if (ts == null) return true;
    // Matches ingest_worker.py's STALE_HEARTBEAT_S.
    return DateTime.now().toUtc().difference(ts.toUtc()) >
        const Duration(seconds: 90);
  }

  // Founder feedback, 2026-09-17: this used to fire silently -- tap it and
  // nothing visible happened while the backend actually re-dispatched work
  // in the background, indistinguishable from the button doing nothing at
  // all. Now mirrors _startIngest's wait-dialog + completer pattern so
  // there's always a visible "Alfred is working on it" signal, closing only
  // once the real outcome (a genuine terminal status, or a fresh stall) is
  // known -- never immediately after the dispatch call returns.
  Future<void> _resumeTraining() async {
    if (_resuming) return;
    setState(() {
      _resuming = true;
      _isStalled = false;
    });
    _flowCompleter = Completer<void>();
    _startPolling();
    _showTrainingWaitDialog();
    try {
      final session = Supabase.instance.client.auth.currentSession;
      await ApiClient.postJson(
        '/api/ingest/$_propertyId/resume',
        const {},
        bearer: session?.accessToken,
      );
      await _flowCompleter?.future;
    } on ApiException catch (e) {
      _showError(e.userMessage, onRetry: e.retry ? _resumeTraining : null);
    } catch (e) {
      _showError('Resume failed: $e', onRetry: _resumeTraining);
    } finally {
      _hideTrainingWaitDialog();
      if (_isStalled && mounted) {
        _showInfo(
            "This is taking longer than usual. Alfred is still working -- you can resume it below or check back later.");
      }
      if (mounted) setState(() => _resuming = false);
    }
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
    _waitDialogRoute = pushTrainingWaitDialog(
      context,
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
    popTrainingWaitDialog(context, _waitDialogRoute);
    _waitDialogRoute = null;
  }

  Future<void> _startIngest() async {
    if (_isIngesting) return;

    setState(() {
      _isIngesting = true;
      _isStalled = false;
      _ingestedMarkdown = null;
      _propertyStatus = null;
      _masterJson = null;
    });
    // Spans the whole ingest+merge chain now (merge fires server-side
    // automatically — see _subscribeToProperty) rather than each phase
    // showing/hiding its own dialog.
    _flowCompleter = Completer<void>();
    _startPolling();
    _showTrainingWaitDialog();

    // Phase 2 (2026-09-16): POST /api/ingest is now a bounded, sub-second
    // dispatcher — it mints a background run and returns immediately. All
    // actual file/scrape/merge processing happens in Cloud Tasks workers and
    // is observed entirely through _subscribeToProperty's realtime listener,
    // not through this request's own response. Replaces the old SSE-stream
    // read plus its 20s/90s client-side timeouts with one plain POST.
    try {
      final session = Supabase.instance.client.auth.currentSession;
      await ApiClient.postJson(
        '/api/ingest',
        {
          'property_id': _propertyId,
          'property_name': _nicknameController.text.trim(),
          'airbnb_url': widget.property['airbnb_url'] as String? ?? '',
        },
        bearer: session?.accessToken,
        timeout: const Duration(seconds: 20),
      );
      // Wait for the real end of the chain — a genuine terminal status, or a
      // confirmed-stale heartbeat (_subscribeToProperty completes this in
      // both cases). No client-side cap needed: the backend's own watchdog
      // is what used to be handled by a blind timeout here.
      await _flowCompleter?.future;
    } on ApiException catch (e) {
      _showError(e.userMessage, onRetry: e.retry ? _startIngest : null);
    } catch (e) {
      _showError("Couldn't reach Alfred. Check your connection and try again.",
          onRetry: _startIngest);
    } finally {
      _hideTrainingWaitDialog();
      if (_isStalled && mounted) {
        _showInfo(
            "This is taking longer than usual. Alfred is still working -- you can resume it below or check back later.");
      }
      if (mounted) setState(() => _isIngesting = false);
    }
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
      _showError(e.userMessage, onRetry: e.retry ? _runMerge : null);
    } catch (e) {
      _showError('Merge failed: $e', onRetry: _runMerge);
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

  // Phase 3 (2026-09-16) — item 2's "request never reaches the backend"
  // messaging was present but not legible: RequestTimeoutException/
  // ServerException's own userMessage literally says "Tap retry" while this
  // SnackBar had no tappable retry at all (matches chat_screen.dart's
  // _showApiError pattern now). onRetry is optional so most call sites are
  // unaffected; pass it when the failure is plausibly transient.
  void _showError(String msg, {VoidCallback? onRetry}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: context.palette.danger,
      action: onRetry == null
          ? null
          : SnackBarAction(
              label: 'Retry', textColor: Colors.white, onPressed: onRetry),
    ));
  }

  // Non-error status update -- distinct from _showError's danger styling so
  // "still working, nothing's wrong" never reads as a failure.
  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: context.palette.accent));
  }

  // Item 1 (partial-failure summary), Phase 2, 2026-09-16 — a run can finish
  // (status past 'Ingesting') with some individual files failed; the guided
  // banner above only reacts to the whole-run 'Ingest_Error' status, so this
  // is the visible, non-blocking counterpart for a partial failure. The
  // stalled case is handled by nextStepFor's isStalled branch instead (shown
  // above, not here) so the two don't double up.
  Widget _buildFailedFilesBanner(BuildContext context) {
    if (_isStalled || _isIngesting) return const SizedBox.shrink();
    final failedCount =
        _filesToIngest.where((f) => f['status'] == 'error').length;
    if (failedCount == 0) return const SizedBox.shrink();
    final palette = context.palette;
    final total = _filesToIngest.length;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
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
                  Text(
                    failedCount == 1
                        ? "1 of $total file couldn't be processed"
                        : '$failedCount of $total files couldn\'t be processed',
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Alfred retried automatically before giving up on these. You can try again.',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: palette.textSecondary),
                  ),
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
                          : Text('Retry',
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

  static const _trainedStatuses = {'Trained', 'Active', 'Resolved', 'Merged'};

  void _handleNextStepAction(SetupStep step) {
    // Dispatch per-status action: for most steps, the screen itself is the action
    // (user uploads files, clicks RE-INGEST, or resolves conflicts here)
    final status = _propertyStatus ?? '';
    // Stalled (Phase 2, 2026-09-16) applies across every live status
    // uniformly — checked first so it isn't shadowed by a status-specific
    // branch below (e.g. 'Ingested' would otherwise route into
    // _confirmAndMerge instead of actually resuming the stuck run).
    if (_isStalled) {
      _resumeTraining();
      return;
    }
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
                // show an explicit processing state instead, UNLESS the run is
                // confirmed stalled (Phase 2, 2026-09-16), in which case fall
                // through to nextStepFor so its isStalled branch (Resume
                // Training) renders instead of an indefinite spinner.
                Builder(builder: (ctx) {
                  final step = (_isIngesting || _isMerging) && !_isStalled
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
                          isStalled: _isStalled,
                          isDev: widget.isDev,
                        );
                  var displayStep = step;
                  // The shared nextStepFor()'s 'Resolve' action is real in
                  // the drawer (navigates here) but a confirmed no-op on this
                  // screen itself, since _handleNextStepAction has nothing to
                  // do for Conflict_Pending -- the conflicts panel is already
                  // visible right below. Overridden here only (not in
                  // nextStepFor) so the drawer's own working button is
                  // untouched. Founder-specified copy, 2026-09-19.
                  if (displayStep != null && _propertyStatus == 'Conflict_Pending') {
                    displayStep = SetupStep(
                      headline: displayStep.headline,
                      subtext: 'A few items disagree between your files. '
                          'Scroll down to review and resolve them.',
                      actionLabel: '',
                      icon: displayStep.icon,
                      accent: displayStep.accent,
                    );
                  }
                  if (displayStep == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: SetupStatusBanner(
                      step: displayStep,
                      onAction: () => _handleNextStepAction(displayStep!),
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
                _buildFailedFilesBanner(context),

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
