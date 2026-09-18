import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'voice_recorder.dart';
import 'file_status_list.dart';
import 'conflict_questionnaire.dart';
import 'generate_guest_link_dialog.dart';
import 'archived_chats_dialog.dart';
import '../screens/edit_property_screen.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/setup_status.dart';
import '../utils/walkthrough_prefs.dart';
import 'setup_status_banner.dart';
import 'training_wait_dialog.dart';
import 'walkthrough_highlight.dart';
import 'walkthrough_tip_panel.dart';

class PropertyDetailDrawer extends StatefulWidget {
  final Map<String, dynamic> property;
  final VoidCallback onRefresh;
  final bool isDev;

  const PropertyDetailDrawer({
    super.key,
    required this.property,
    required this.onRefresh,
    this.isDev = false,
  });

  @override
  State<PropertyDetailDrawer> createState() => _PropertyDetailDrawerState();
}

class _PropertyDetailDrawerState extends State<PropertyDetailDrawer>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  // Kept in sync with _tabController's length via _syncTabControllerForConflict
  // — see that method for why this can't just be recomputed inline in build().
  bool _hasConflict = false;
  late Map<String, dynamic> _property;
  String? _heroUrl;
  bool _heroLoaded = false;

  // Knowledge tab state
  final _knowledgeController = TextEditingController();
  bool _addingKnowledge = false;
  bool _knowledgeSuccess = false;
  String? _knowledgeError;

  // Knowledge base chat state
  final _kbChatController = TextEditingController();
  final List<Map<String, String>> _kbHistory = [];
  bool _kbQuerying = false;

  // Voice path state (reuses voice recorder + file status)
  final List<Map<String, String>> _voiceStatuses = [];

  // Guest welcome language toggle
  bool _savingWelcomeEnglish = false;

  // Automated Learning state
  List<Map<String, dynamic>> _learnedKnowledge = [];
  bool _loadingLearned = false;
  bool _learnedLoaded = false;
  int? _editingLearnedIndex;
  final _editProblemCtrl = TextEditingController();
  final _editSolutionCtrl = TextEditingController();
  // After Accept, a card lingers in the review queue for a few seconds showing
  // an Undo, then moves to the Vault. Keyed by the entry's resolved_at.
  final Set<String> _acceptGrace = {};
  final Map<String, Timer> _acceptTimers = {};
  // Vault delete gets the same brief Undo before the row is actually removed.
  final Set<String> _deleteGrace = {};
  final Map<String, Timer> _deleteTimers = {};
  static const _graceDuration = Duration(seconds: 3);

  // Live property subscription while the drawer is open. Without this, the
  // dashboard's stream updates the underlying property but the drawer keeps
  // showing stale status / banner state.
  StreamSubscription<List<Map<String, dynamic>>>? _propStream;

  // Part B of the User-mode post-training walkthrough — rebuilt 2026-09-11
  // using a real Overlay entry (see _wtOverlay below) instead of nesting the
  // tip panel inside this drawer's showGeneralDialog route, which is the one
  // structural difference from the two panels (dashboard Step 0, Add
  // Property) that never hit the still-unexplained text rendering bug the
  // old inline-docked version had. Step 1 (of 5) was verified live via
  // Playwright before the rest were added — see walkthrough.md for the copy.
  int? _wtStep;
  static const _wtStepCount = 5;
  static const _wtReadyStatuses = {'Trained', 'Active', 'Resolved', 'Merged'};
  final _wtDrawerKey = GlobalKey();
  final _wtManageKey = GlobalKey();
  final _wtAddKnowledgeKey = GlobalKey();
  final _wtLearningKey = GlobalKey();
  final _wtChatKey = GlobalKey();
  final _wtDockLink = LayerLink();
  OverlayEntry? _wtOverlay;
  // Drives the overlay entry's content directly, instead of relying on
  // OverlayEntry.markNeedsBuild() — confirmed unreliable here: the highlight
  // below (plain setState) updated correctly on Next/Back, but the overlay's
  // own text stayed stale even after markNeedsBuild() calls and a 3s wait.
  // A ValueListenableBuilder inside the entry is the documented-safe pattern.
  final _wtStepNotifier = ValueNotifier<int?>(null);
  // "+ Show walkthrough again" switch state — true while either half (this
  // property's Settings walkthrough, or the global Guest Link walkthrough)
  // hasn't been seen yet. Loaded async since both live in SharedPreferences;
  // null until the first load resolves. See _loadReplayPending/_toggleReplayWalkthrough.
  bool? _wtReplayPending;

  @override
  void initState() {
    super.initState();
    _property = Map<String, dynamic>.from(widget.property);
    _hasConflict = _property['Conflict_status'] == 'pending';
    // Dev: Overview, Files, Knowledge(, Resolve). User: Overview, Knowledge(,
    // Resolve) — the Files tab folds into Overview's file summary card instead.
    _tabController = TabController(
      length: (widget.isDev ? 3 : 2) + (_hasConflict ? 1 : 0),
      vsync: this,
    );
    _loadHeroUrl();
    _subscribeProperty();
    // Guaranteed fresh fetch on open, independent of realtime's connection
    // timing -- see the comment on _refreshProperty itself for why this was
    // added 2026-09-17.
    _refreshProperty();
    _maybeStartWalkthrough();
    _loadReplayPending();
  }

  Future<void> _maybeStartWalkthrough() async {
    if (widget.isDev) return;
    final status = _property['status'] as String? ?? '';
    if (!_wtReadyStatuses.contains(status)) return;
    final seen = await WalkthroughPrefs.isPostTrainingSeen(_property['id'] as String);
    if (seen || !mounted) return;
    // The tip panel explaining each highlighted step is hidden below this
    // width (see _ensureWtOverlayInserted's own screenW < 1000 check) — never
    // start the walkthrough state at all on a narrow viewport, rather than
    // starting it with highlighted/locked UI and no visible explanation or
    // way to progress.
    if (MediaQuery.sizeOf(context).width < 1000) return;
    _setWtStep(0);
  }

  Future<void> _loadReplayPending() async {
    if (widget.isDev) return;
    final settingsSeen = await WalkthroughPrefs.isPostTrainingSeen(_property['id'] as String);
    final guestLinkSeen = await WalkthroughPrefs.isGuestLinkWalkthroughSeen();
    if (mounted) setState(() => _wtReplayPending = !(settingsSeen && guestLinkSeen));
  }

  // Single point of mutation for _wtStep — keeps the highlight (plain
  // setState, drives the normal widget tree) and the docked panel's own
  // ValueNotifier (drives the Overlay entry, see _wtStepNotifier) in sync.
  void _setWtStep(int? step) {
    setState(() => _wtStep = step);
    _wtStepNotifier.value = step;
  }

  // (tab index, anchor key, title, body) for each of the 5 steps — tab index
  // is User mode's own numbering (Overview=0, Knowledge=1; there's no Files
  // tab to account for here since that only exists in Dev mode).
  (int, GlobalKey, String, String) _wtStepInfo(int step) {
    final name = _property['name'] as String? ?? 'this property';
    switch (step) {
      case 0:
        return (
          0,
          _wtDrawerKey,
          "I've learned $name — here's what's next",
          "This is where you'll come back anytime: add more detail, see what I "
              "picked up on my own, or ask me something to check my work.",
        );
      case 1:
        return (
          0,
          _wtManageKey,
          'Add or swap files anytime',
          "Tap Manage to upload more — a new house manual, an updated WiFi "
              "photo, anything. I'll fold it in without starting over.",
        );
      case 2:
        return (
          1,
          _wtAddKnowledgeKey,
          'Tell me something directly',
          "Type it, or record a voice note — parking rules, a fix for the "
              "shower, whatever's easiest. I'll add it to what I already know.",
        );
      case 3:
        return (
          1,
          _wtLearningKey,
          'I flag what I learn on my own',
          "Every real guest conversation teaches me something — I'll surface "
              "it here for your OK before it sticks.",
        );
      default:
        return (
          1,
          _wtChatKey,
          'Double-check me anytime',
          "Ask me something here, the same way a guest would. It's the "
              "fastest way to see exactly what I'd tell them — before they ever ask.",
        );
    }
  }

  void _wtGoToStep(int step) {
    _setWtStep(step);
    final (tabIndex, key, _, _) = _wtStepInfo(step);
    _tabController.animateTo(tabIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.1,
        );
      }
    });
  }

  void _wtNext() {
    if (_wtStep == null) return;
    if (_wtStep! >= _wtStepCount - 1) {
      _wtFinish();
    } else {
      _wtGoToStep(_wtStep! + 1);
    }
  }

  void _wtBack() {
    if (_wtStep == null || _wtStep == 0) return;
    _wtGoToStep(_wtStep! - 1);
  }

  void _wtFinish() {
    _setWtStep(null);
    WalkthroughPrefs.markPostTrainingSeen(_property['id'] as String);
  }

  // "+ Show walkthrough again" switch. One control for both halves: turning
  // it on resets BOTH the Settings walkthrough (this property) and the Guest
  // Link walkthrough (global) and sends the host back to the dashboard, where
  // Step 0 now points at both +Guest and Settings again — see
  // dashboard_screen.dart's _showStep0Hint. Each dedicated walkthrough then
  // starts on its own the next time its real entry point opens
  // (_maybeStartWalkthrough here, GenerateGuestLinkDialog's own equivalent for
  // Guest Link) — no need to drive either one directly from here. Turning it
  // off cancels/dismisses both at once, same as closing today.
  Future<void> _toggleReplayWalkthrough(bool value) async {
    if (!value) {
      await WalkthroughPrefs.markPostTrainingSeen(_property['id'] as String);
      await WalkthroughPrefs.markGuestLinkWalkthroughSeen();
      if (!mounted) return;
      if (_wtStep != null) _setWtStep(null);
      setState(() => _wtReplayPending = false);
      return;
    }
    await WalkthroughPrefs.resetPostTrainingWalkthrough(_property['id'] as String);
    await WalkthroughPrefs.resetGuestLinkWalkthrough();
    if (!mounted) return;
    setState(() => _wtReplayPending = true);
    Navigator.of(context).pop();
  }

  // Inserts the docked tip panel as a real Overlay entry
  // (Overlay.of(context, rootOverlay: true)) rather than nesting it inside
  // this drawer's own showGeneralDialog route — see the class-level comment
  // on _wtStep for why. Inserted once and left in place (its own
  // ValueListenableBuilder decides what to render, including hiding itself
  // entirely) rather than inserted/removed per step change — simpler, and
  // sidesteps needing OverlayEntry.markNeedsBuild() at all. Desktop-only
  // (matches the removed version's gate); narrow viewports just get the
  // highlight with no panel, a known gap carried over from before, not fixed
  // by this rebuild.
  void _ensureWtOverlayInserted() {
    if (_wtOverlay != null) return;
    final entry = OverlayEntry(builder: (overlayContext) {
      return ValueListenableBuilder<int?>(
        valueListenable: _wtStepNotifier,
        builder: (_, step, __) {
          final screenW = MediaQuery.of(overlayContext).size.width;
          if (step == null || screenW < 1000) return const SizedBox.shrink();
          final (_, _, title, body) = _wtStepInfo(step);
          return Positioned(
            width: 300,
            child: CompositedTransformFollower(
              link: _wtDockLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.topRight,
              offset: const Offset(-20, 56),
              child: WalkthroughTipPanel(
                stepIndex: step,
                stepCount: _wtStepCount,
                title: title,
                body: body,
                onBack: step > 0 ? _wtBack : null,
                onNext: _wtNext,
                onClose: _wtFinish,
                isLast: step == _wtStepCount - 1,
                pointerSide: WalkthroughPointerSide.right,
                pointerCenter: 56,
              ),
            ),
          );
        },
      );
    });
    _wtOverlay = entry;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Overlay.of(context, rootOverlay: true).insert(entry);
    });
  }

  Widget _wtHighlight({required int step, required GlobalKey key, required Widget child}) {
    return WalkthroughHighlight(
      key: key,
      active: _wtStep == step,
      child: child,
    );
  }

  // The walkthrough tip panel that used to render here was removed — see
  // walkthrough.md for its full copy/structure, kept for a future rebuild.

  @override
  void dispose() {
    _wtOverlay?.remove();
    _wtOverlay = null;
    _wtStepNotifier.dispose();
    _tabController.dispose();
    _knowledgeController.dispose();
    _kbChatController.dispose();
    _editProblemCtrl.dispose();
    _editSolutionCtrl.dispose();
    for (final t in _acceptTimers.values) {
      t.cancel();
    }
    for (final t in _deleteTimers.values) {
      t.cancel();
    }
    _propStream?.cancel();
    super.dispose();
  }

  void _subscribeProperty() {
    _propStream = Supabase.instance.client
        .from('properties')
        .stream(primaryKey: ['id'])
        .eq('id', _property['id'] as String)
        .listen((rows) {
          if (!mounted || rows.isEmpty) return;
          setState(() {
            _property = <String, dynamic>{..._property, ...rows.first};
            _syncTabControllerForConflict(
                _property['Conflict_status'] == 'pending');
          });
        });
  }

  // TabController.length is immutable once created, but the tab count
  // depends on _hasConflict, which can flip live — either because this
  // drawer's own Resolve tab just cleared it (_onResolved) or because the
  // realtime subscription above replaced _property with a row where it
  // changed (resolved/created elsewhere). Without this, TabBar/TabBarView
  // throw a tab-count assertion the instant the tab list and the controller's
  // length disagree. Must be called from inside the same setState that
  // changes Conflict_status so the rebuild sees the new controller and the
  // new tab list together.
  void _syncTabControllerForConflict(bool newHasConflict) {
    if (newHasConflict == _hasConflict) return;
    final newLength = (widget.isDev ? 3 : 2) + (newHasConflict ? 1 : 0);
    final oldController = _tabController;
    _tabController = TabController(
      length: newLength,
      vsync: this,
      initialIndex: oldController.index.clamp(0, newLength - 1),
    );
    oldController.dispose();
    _hasConflict = newHasConflict;
  }

  Future<void> _loadHeroUrl() async {
    try {
      final url = await Supabase.instance.client.storage
          .from('Property_assets')
          .createSignedUrl('${_property['id']}/hero_image/main.jpg', 3600);
      if (mounted) setState(() => _heroUrl = url);
    } catch (_) {}
    if (mounted) setState(() => _heroLoaded = true);
  }

  // Was dead code (flutter analyze: unused_element) until 2026-09-17 --
  // wired into initState below. Root cause of a real live-found bug: this
  // drawer only ever trusted whatever snapshot the dashboard happened to
  // hand it in widget.property, self-correcting only once _subscribeProperty
  // below's realtime channel delivered its first event -- a real timing gap
  // (dashboard's own async refresh after returning from EditPropertyScreen,
  // or the realtime channel's own connection handshake) that let a
  // freshly-reopened drawer briefly show a fully-resolved property as still
  // "Conflict_Pending" with the stale Resolve banner/tab still active.
  Future<void> _refreshProperty() async {
    try {
      final data = await Supabase.instance.client
          .from('properties')
          .select(
              'id, name, status, airbnb_url, created_at, master_json, file_fingerprints, Conflict_status, scrape_retry')
          .eq('id', _property['id'] as String)
          .single();
      if (mounted) {
        setState(() {
          // Merge, not replace -- this select is a narrow column list, and
          // _property holds other fields (ingest_heartbeat_at, curated_photos,
          // etc.) that a wholesale replace would silently drop.
          _property = <String, dynamic>{..._property, ...data};
          _syncTabControllerForConflict(_property['Conflict_status'] == 'pending');
        });
      }
      widget.onRefresh();
    } catch (_) {}
  }

  Future<void> _addKnowledge() async {
    final text = _knowledgeController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _addingKnowledge = true;
      _knowledgeError = null;
    });

    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;

    // Was a raw http.post with a dotenv.env['BACKEND_URL'] ?? 'http://localhost:8000'
    // fallback (bypassing ApiClient's fail-loud config guard) and no timeout —
    // ApiClient.postJson resolves BACKEND_URL itself and times out/retries.
    try {
      final data = await ApiClient.postJson(
        '/api/ingest/add-knowledge',
        {'property_id': _property['id'], 'text': text},
        bearer: token,
      );
      final updatedJson = data['master_json'];
      if (mounted) {
        setState(() {
          _knowledgeController.clear();
          _knowledgeSuccess = true;
          _knowledgeError = null;
          if (updatedJson != null) {
            _property['master_json'] = updatedJson;
          }
        });
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => _knowledgeSuccess = false);
        });
      }
    } on ApiException catch (e) {
      setState(() => _knowledgeError = e.userMessage);
    } catch (e) {
      setState(() =>
          _knowledgeError = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _addingKnowledge = false);
    }
  }

  void _onVoiceFileAdded(String filename) {
    setState(() {
      _voiceStatuses.add({'file': filename, 'status': 'processing', 'message': ''});
    });
  }

  void _onVoiceFileResult(String filename, bool success) {
    setState(() {
      final idx = _voiceStatuses.indexWhere((e) => e['file'] == filename);
      if (idx >= 0) {
        _voiceStatuses[idx] = {
          'file': filename,
          'status': success ? 'queued' : 'error',
          'message': success ? '' : 'Upload failed',
        };
      }
    });
    if (success) _triggerVoiceIngest(filename);
  }

  Future<void> _triggerVoiceIngest(String filename) async {
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;

    // Was a raw http.post with the same BACKEND_URL-fallback + no-timeout
    // pattern as _addKnowledge above — same ApiClient.postJson fix.
    try {
      final data = await ApiClient.postJson(
        '/api/ingest/add-knowledge',
        {
          'property_id': _property['id'],
          'storage_path': '${_property['id']}/user_uploads/$filename',
        },
        bearer: token,
      );
      final updatedJson = data['master_json'];
      if (mounted) {
        setState(() {
          final idx = _voiceStatuses.indexWhere((e) => e['file'] == filename);
          if (idx >= 0) {
            _voiceStatuses[idx] = {
              'file': filename,
              'status': 'done',
              'message': '',
            };
          }
          if (updatedJson != null) {
            _property['master_json'] = updatedJson;
          }
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          final idx = _voiceStatuses.indexWhere((e) => e['file'] == filename);
          if (idx >= 0) {
            _voiceStatuses[idx] = {
              'file': filename,
              'status': 'error',
              'message': e.userMessage,
            };
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          final idx = _voiceStatuses.indexWhere((e) => e['file'] == filename);
          if (idx >= 0) {
            _voiceStatuses[idx] = {
              'file': filename,
              'status': 'error',
              'message': 'Something went wrong. Please try again.',
            };
          }
        });
      }
    }
  }

  Future<void> _queryKnowledgeBase() async {
    final q = _kbChatController.text.trim();
    if (q.isEmpty || _kbQuerying) return;

    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;

    setState(() {
      _kbQuerying = true;
      _kbHistory.add({'q': q, 'a': ''});
      _kbChatController.clear();
    });

    // Was a raw http.post with the same BACKEND_URL-fallback + no-timeout
    // pattern as _addKnowledge above — same ApiClient.postJson fix.
    try {
      final data = await ApiClient.postJson(
        '/api/ingest/query-knowledge',
        {'property_id': _property['id'], 'question': q},
        bearer: token,
      );
      if (mounted) {
        final answer = data['answer'] as String? ?? '';
        setState(() {
          _kbHistory[_kbHistory.length - 1] = {'q': q, 'a': answer};
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _kbHistory[_kbHistory.length - 1] = {'q': q, 'a': e.userMessage};
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _kbHistory[_kbHistory.length - 1] = {
            'q': q,
            'a': 'Something went wrong. Please try again.',
          };
        });
      }
    } finally {
      if (mounted) setState(() => _kbQuerying = false);
    }
  }

  void _onResolved(String status, Map<String, dynamic> masterJson) {
    setState(() {
      _property['status'] = status;
      _property['master_json'] = masterJson;
      _property['Conflict_status'] = null;
      _syncTabControllerForConflict(false);
    });
    widget.onRefresh();
  }

  Future<void> _loadLearnedKnowledge() async {
    if (_loadingLearned) return;
    setState(() => _loadingLearned = true);
    try {
      final result = await Supabase.instance.client
          .from('properties')
          .select('learned_knowledge')
          .eq('id', _property['id'] as String)
          .single();
      if (mounted) {
        setState(() {
          _learnedKnowledge = List<Map<String, dynamic>>.from(
              result['learned_knowledge'] as List? ?? []);
          _learnedLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _learnedLoaded = true);
    } finally {
      if (mounted) setState(() => _loadingLearned = false);
    }
  }

  Future<void> _toggleWelcomeAlsoEnglish(bool value) async {
    final previous = _property['welcome_also_english'] == true;
    setState(() {
      _property['welcome_also_english'] = value;
      _savingWelcomeEnglish = true;
    });
    try {
      await Supabase.instance.client
          .from('properties')
          .update({
            'welcome_also_english': value,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', _property['id'] as String);
    } catch (e) {
      if (mounted) {
        setState(() => _property['welcome_also_english'] = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to update welcome setting: $e'),
              backgroundColor: context.palette.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _savingWelcomeEnglish = false);
    }
  }

  Future<void> _writeLearned(List<Map<String, dynamic>> updated) async {
    await Supabase.instance.client
        .from('properties')
        .update({
          'learned_knowledge': updated,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', _property['id'] as String);
    if (mounted) setState(() => _learnedKnowledge = updated);
  }

  // Stable-ish key for a learned entry (resolved_at is set once at creation).
  String _learnedKey(Map<String, dynamic> e, int index) =>
      (e['resolved_at'] as String?) ?? 'idx_$index';

  // Entries still awaiting review: not reviewed yet, or in the post-accept
  // grace window (briefly shown with Undo before moving to the Vault).
  List<MapEntry<int, Map<String, dynamic>>> get _pendingLearned {
    final out = <MapEntry<int, Map<String, dynamic>>>[];
    for (var i = 0; i < _learnedKnowledge.length; i++) {
      final e = _learnedKnowledge[i];
      if (e['reviewed'] != true || _acceptGrace.contains(_learnedKey(e, i))) {
        out.add(MapEntry(i, e));
      }
    }
    return out;
  }

  // Accepted entries that have settled into the Vault (not in the grace window).
  List<MapEntry<int, Map<String, dynamic>>> get _vaultLearned {
    final out = <MapEntry<int, Map<String, dynamic>>>[];
    for (var i = 0; i < _learnedKnowledge.length; i++) {
      final e = _learnedKnowledge[i];
      if (e['reviewed'] == true && !_acceptGrace.contains(_learnedKey(e, i))) {
        out.add(MapEntry(i, e));
      }
    }
    return out;
  }

  Future<void> _acceptLearned(int index) async {
    final key = _learnedKey(_learnedKnowledge[index], index);
    final updated = List<Map<String, dynamic>>.from(_learnedKnowledge);
    updated[index] = {...updated[index], 'reviewed': true};
    await _writeLearned(updated);
    // Keep the card in the review queue with an Undo for a few seconds, then
    // let it settle into the Vault.
    _acceptTimers[key]?.cancel();
    if (mounted) setState(() => _acceptGrace.add(key));
    _acceptTimers[key] = Timer(_graceDuration, () {
      _acceptTimers.remove(key);
      if (mounted) setState(() => _acceptGrace.remove(key));
    });
  }

  // Vault delete with a brief Undo: the row shows "Removing… Undo" for a few
  // seconds, then the entry is actually removed from learned_knowledge. onChange
  // refreshes the open Vault dialog (guarded — it's a no-op once closed).
  void _beginVaultDelete(String key, {VoidCallback? onChange}) {
    _deleteTimers[key]?.cancel();
    if (mounted) setState(() => _deleteGrace.add(key));
    onChange?.call();
    _deleteTimers[key] = Timer(_graceDuration, () async {
      _deleteTimers.remove(key);
      final updated = List<Map<String, dynamic>>.from(_learnedKnowledge)
        ..removeWhere((e) => (e['resolved_at'] as String?) == key);
      await _writeLearned(updated);
      if (mounted) setState(() => _deleteGrace.remove(key));
      onChange?.call();
    });
  }

  void _undoVaultDelete(String key, {VoidCallback? onChange}) {
    _deleteTimers.remove(key)?.cancel();
    if (mounted) setState(() => _deleteGrace.remove(key));
    onChange?.call();
  }

  Future<void> _undoAccept(int index) async {
    final key = _learnedKey(_learnedKnowledge[index], index);
    _acceptTimers.remove(key)?.cancel();
    final updated = List<Map<String, dynamic>>.from(_learnedKnowledge);
    updated[index] = {...updated[index], 'reviewed': false};
    await _writeLearned(updated);
    if (mounted) setState(() => _acceptGrace.remove(key));
  }

  Future<void> _saveLearned(int index) async {
    final updated = List<Map<String, dynamic>>.from(_learnedKnowledge);
    updated[index] = {
      ...updated[index],
      'problem_summary': _editProblemCtrl.text.trim(),
      'solution_summary': _editSolutionCtrl.text.trim(),
      'reviewed': true,
    };
    await _writeLearned(updated);
    if (mounted) setState(() => _editingLearnedIndex = null);
  }

  Future<void> _discardLearned(int index) async {
    // Previously had no confirmation at all — one accidental tap permanently
    // threw away a real, auto-detected suggestion with no undo (unlike
    // Accept, which gets a grace-period Undo). Now routed through the same
    // confirm dialog the Vault's own delete already uses, for consistency.
    final confirmed = await _confirmDelete(
      'Discard this suggestion?',
      "Alfred picked this up from a real guest conversation. Discarding it "
          "can't be undone — Alfred won't suggest it again.",
      confirmLabel: 'Discard',
    );
    if (!confirmed) return;
    final updated = List<Map<String, dynamic>>.from(_learnedKnowledge)
      ..removeAt(index);
    await _writeLearned(updated);
  }

  Future<bool> _confirmDelete(String title, String body,
      {String confirmLabel = 'Delete'}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: context.palette.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // The Vault: everything Alfred has learned (accepted entries), where the host
  // can review the full history and delete anything unwanted (with a brief Undo).
  void _showKnowledgeVault() {
    bool dialogOpen = true;
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            void safeRefresh() {
              if (dialogOpen) setDialogState(() {});
            }

            final entries = _vaultLearned;
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 18, color: context.palette.accent),
                  const SizedBox(width: 8),
                  const Text('Knowledge Vault'),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: entries.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Nothing here yet. Accepted learning entries live here — '
                          'you can review or remove them anytime.',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: context.palette.textMuted),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: entries.map((p) {
                          final index = p.key;
                          final entry = p.value;
                          final key = _learnedKey(entry, index);
                          final deleting = _deleteGrace.contains(key);
                          final category = entry['category'] as String? ?? 'other';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              border: Border.all(color: Colors.green.shade200),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        category,
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    if (deleting) ...[
                                      Text('Removing…',
                                          style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: Colors.red.shade600)),
                                      TextButton.icon(
                                        onPressed: () => _undoVaultDelete(key,
                                            onChange: safeRefresh),
                                        icon: const Icon(Icons.undo_rounded, size: 14),
                                        label: const Text('Undo'),
                                        style: TextButton.styleFrom(
                                          foregroundColor:
                                              context.palette.textSecondary,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          textStyle:
                                              GoogleFonts.inter(fontSize: 12),
                                        ),
                                      ),
                                    ] else
                                      IconButton(
                                        tooltip: 'Delete',
                                        visualDensity: VisualDensity.compact,
                                        icon: Icon(Icons.delete_outline_rounded,
                                            size: 18, color: Colors.red.shade600),
                                        onPressed: () async {
                                          if (await _confirmDelete(
                                            'Delete this entry?',
                                            "This permanently removes it from "
                                                "this property's learned "
                                                "knowledge. Alfred will no "
                                                "longer use it to answer guests.",
                                          )) {
                                            _beginVaultDelete(key,
                                                onChange: safeRefresh);
                                          }
                                        },
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Opacity(
                                  opacity: deleting ? 0.5 : 1.0,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Q: ${entry['problem_summary'] ?? ''}',
                                          style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: context.palette.textPrimary,
                                              height: 1.4)),
                                      const SizedBox(height: 4),
                                      Text('A: ${entry['solution_summary'] ?? ''}',
                                          style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: context.palette.textSecondary,
                                              height: 1.4)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) => dialogOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    // Reads the field kept in sync by _syncTabControllerForConflict, not a
    // fresh recompute — build() must agree with _tabController.length, and
    // those two are set together at every Conflict_status mutation site.
    final hasConflict = _hasConflict;
    final screenW = MediaQuery.of(context).size.width;
    final drawerW = screenW < 600 ? screenW : 440.0;

    final drawer = Material(
      elevation: 0,
      color: context.palette.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.palette.surface,
          boxShadow: context.palette.drawerShadow,
        ),
        child: SizedBox(
          width: drawerW,
          height: double.infinity,
          child: Column(
            children: [
              _buildHeader(),
              TabBar(
                controller: _tabController,
                tabs: [
                  const Tab(text: 'Overview'),
                  if (widget.isDev) const Tab(text: 'Files'),
                  const Tab(text: 'Knowledge'),
                  if (hasConflict)
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 14, color: context.palette.warning),
                          const SizedBox(width: 4),
                          const Text('Resolve'),
                        ],
                      ),
                    ),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOverviewTab(),
                    if (widget.isDev) _buildFilesTab(),
                    _buildKnowledgeTab(),
                    if (hasConflict) _buildResolveTab(),
                  ],
                ),
              ),
              _buildBottomActions(),
            ],
          ),
        ),
      ),
    );

    _ensureWtOverlayInserted();
    if (_wtStep == null) return drawer;
    return CompositedTransformTarget(
      link: _wtDockLink,
      child: _wtHighlight(step: 0, key: _wtDrawerKey, child: drawer),
    );
  }

  Widget _buildHeader() {
    final name = _property['name'] as String? ?? 'Property';
    final status = _property['status'] as String? ?? '';
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [context.palette.primaryDark, context.palette.primary, context.palette.accent],
          stops: const [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: context.palette.primary.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 8, 20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25), width: 1),
            ),
            child: Icon(Icons.home_work_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (status.isNotEmpty)
                  Text(
                    status,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded,
                color: Colors.white, size: 20),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    final status = _property['status'] as String? ?? '';
    final airbnbUrl = _property['airbnb_url'] as String? ?? '';
    final createdAt = _property['created_at'] as String? ?? '';
    final setupStep = nextStepFor(
      status,
      hasMasterJson: _property['master_json'] != null,
      isDev: widget.isDev,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (setupStep != null)
            SetupStatusBanner(
              step: setupStep,
              compact: true,
              onAction: () {
                final nav = Navigator.of(context);
                final refresh = widget.onRefresh;
                // pushReplacement, not pop()+push(): closing the drawer's own
                // dialog route and opening EditPropertyScreen must be one
                // atomic swap, or the drawer route can survive underneath and
                // reappear (stale) when EditPropertyScreen is later popped.
                nav.pushReplacement(MaterialPageRoute(
                  builder: (_) => EditPropertyScreen(
                    property: _property,
                    isDev: widget.isDev,
                  ),
                )).then((_) => refresh());
              },
            ),
          // Hero image
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: _heroLoaded && _heroUrl != null
                  ? Image.network(_heroUrl!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _heroPlaceholder())
                  : _heroLoaded
                      ? _heroPlaceholder()
                      : ColoredBox(color: context.palette.primaryContainer),
            ),
          ),
          const SizedBox(height: 16),
          // Scrape-quality failsafe (2026-09-17): status may genuinely be
          // Trained/Merged underneath, but a real unresolved issue (an
          // unreadable Airbnb link) exists -- this row must not read as
          // "all done" while that's true, same reasoning as the dashboard
          // card's badge override. _scrapeLinkRetrying takes priority since
          // there's nothing to flag while Alfred is already re-checking.
          _infoRow(
            'Status',
            _scrapeLinkRetrying
                ? 'Processing'
                : _scrapeLinkNeedsAttention
                    ? 'Needs Attention'
                    : status,
          ),
          if (airbnbUrl.isNotEmpty)
            _airbnbUrlRow(airbnbUrl),
          if (createdAt.isNotEmpty)
            _infoRow('Added', _formatDate(createdAt)),
          const SizedBox(height: 8),
          _buildWelcomeLanguageSetting(),
          if (!widget.isDev && _wtReadyStatuses.contains(status))
            _buildReplayWalkthroughSetting(),
          if (!widget.isDev) ...[
            const SizedBox(height: 16),
            _buildFilesSummaryCard(),
          ],
        ],
      ),
    );
  }

  // User-mode stand-in for the Files tab (Dev keeps that tab as-is). Files
  // rarely change once a property is trained, so this stays a single summary
  // row rather than the always-visible list Dev sees — "Manage" opens the
  // same Edit Property screen the Files tab's own button already used.
  Widget _buildFilesSummaryCard() {
    final fingerprints =
        _property['file_fingerprints'] as Map<String, dynamic>? ?? {};
    final count = fingerprints.length;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.palette.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: context.palette.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.folder_outlined,
                size: 17, color: context.palette.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count == 0
                  ? 'No files yet'
                  : '$count ${count == 1 ? 'file' : 'files'} on record',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: context.palette.textPrimary,
              ),
            ),
          ),
          _wtHighlight(
            step: 1,
            key: _wtManageKey,
            child: OutlinedButton(
              onPressed: () {
                final nav = Navigator.of(context);
                final refresh = widget.onRefresh;
                // pushReplacement, not pop()+push() -- see the matching
                // comment on the SetupStatusBanner action above.
                nav.pushReplacement(MaterialPageRoute(
                  builder: (_) => EditPropertyScreen(
                    property: _property,
                    isDev: widget.isDev,
                  ),
                )).then((_) => refresh());
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                foregroundColor: context.palette.primary,
                side: BorderSide(color: context.palette.primaryContainer, width: 1.5),
                textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              child: const Text('Manage'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeLanguageSetting() {
    final palette = context.palette;
    final alsoEnglish = _property['welcome_also_english'] == true;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message:
                  'Alfred greets guests in the property\'s local language by '
                  'default. Turn this on to also send the welcome in English.',
              waitDuration: const Duration(milliseconds: 300),
              child: Text(
                '+ English welcome',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _savingWelcomeEnglish
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Switch(
                  value: alsoEnglish,
                  activeThumbColor: palette.primary,
                  onChanged: _toggleWelcomeAlsoEnglish,
                ),
        ],
      ),
    );
  }

  Widget _buildReplayWalkthroughSetting() {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: 'Replays the setup tips shown right after this '
                  'property finished training — both the Settings walkthrough '
                  'and the guest link walkthrough.',
              waitDuration: const Duration(milliseconds: 300),
              child: Text(
                '+ Show walkthrough again',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: _wtReplayPending ?? false,
            activeThumbColor: palette.primary,
            onChanged: _toggleReplayWalkthrough,
          ),
        ],
      ),
    );
  }

  // Scrape-quality failsafe (2026-09-17) — true once the background retry has
  // exhausted itself (see migrations/2026-09-17_scrape_retry.sql). Alfred
  // trained fine on the uploaded files, but couldn't confirm the Airbnb
  // listing after two tries; the host needs a way to fix/re-check the link,
  // which the URL row otherwise has no edit affordance for at all.
  bool get _scrapeLinkNeedsAttention {
    final retry = _property['scrape_retry'] as Map<String, dynamic>?;
    return retry != null && retry['attempts'] != null && retry['next_retry_at'] == null;
  }

  bool get _scrapeLinkRetrying =>
      (_property['scrape_retry'] as Map<String, dynamic>?)?['retrying'] == true;

  // 'unreachable' (the fetch itself failed) vs 'low_completeness' (the page
  // loaded but was empty/wrong) read differently to a host — the former
  // reads as "this link is broken", the latter as "loaded but incomplete".
  // Founder-specified copy (2026-09-19): this leads the sentence that's
  // followed by ": $currentUrl" in _showFixLinkDialog, not a standalone line.
  String get _scrapeLinkIssueReason {
    final retry = _property['scrape_retry'] as Map<String, dynamic>?;
    final reason = retry?['reason'] as String?;
    return reason == 'unreachable'
        ? "The current link doesn't seem to work"
        : "Alfred couldn't fully read this link";
  }

  // The specific route the wait dialog below is pushed as -- closed via
  // popTrainingWaitDialog (removeRoute), not a blind Navigator.pop(), since
  // dashboard_screen.dart can independently push its own result dialog on
  // the same root navigator; a blind pop() here could close that one instead
  // and strand this one on screen.
  Route<void>? _retryWaitDialogRoute;

  Future<void> _retryScrapeLink(String newUrl) async {
    // Founder feedback, live-tested: submitting a fix previously gave zero
    // feedback beyond a brief message, then the screen just sat there with
    // no signal anything was happening. Same wait-dialog experience as the
    // original Train Now flow, reused rather than duplicated — this only
    // spans the dispatch call itself (a sub-second POST); the dashboard's
    // "Processing" badge (driven by scrape_retry.retrying) carries the
    // actual in-flight signal after this closes.
    if (mounted) {
      _retryWaitDialogRoute = pushTrainingWaitDialog(
        context,
        builder: (_) => const TrainingWaitDialog(
          headline: 'Alfred is retraining with your new link',
          subtext: 'This only takes a moment. Check the dashboard for the result.',
        ),
      );
    }
    final session = Supabase.instance.client.auth.currentSession;
    try {
      await ApiClient.postJson(
        '/api/ingest/${_property['id']}/retry-scrape',
        {'airbnb_url': newUrl},
        bearer: session?.accessToken,
      );
      if (mounted) {
        // Awaited -- popTrainingWaitDialog's route stays on the stack for a
        // ~200ms fade before it's actually removed (see its own doc comment).
        // Firing this drawer's own Navigator.pop() before that finishes made
        // pop() close whatever's CURRENTLY topmost, which was still the
        // fading wait dialog, not the drawer -- confirmed live (2026-09-19)
        // as the cause of both the abrupt cut and the drawer never closing.
        await popTrainingWaitDialog(context, _retryWaitDialogRoute);
        _retryWaitDialogRoute = null;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Retrying — Alfred will check the listing again shortly.")),
        );
        // Founder feedback, 2026-09-17: return straight to the dashboard on
        // a successful dispatch instead of leaving the host sitting on this
        // drawer — the dashboard's own card/badge and (once training
        // actually finishes) the trained/conflict popup are what carry the
        // rest of the signal from here. Only on success: an error leaves the
        // host in place so they can see the message and retry.
        Navigator.of(context, rootNavigator: true).pop();
      }
    } on ApiException catch (e) {
      if (mounted) {
        await popTrainingWaitDialog(context, _retryWaitDialogRoute);
        _retryWaitDialogRoute = null;
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.userMessage)));
      }
    } catch (e) {
      if (mounted) {
        await popTrainingWaitDialog(context, _retryWaitDialogRoute);
        _retryWaitDialogRoute = null;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not retry. Please try again.')),
        );
      }
    }
  }

  Future<void> _showFixLinkDialog(String currentUrl) async {
    // Deliberately opens empty, not pre-filled with the URL that just
    // failed — pre-filling it invites a blind Retry tap without the host
    // actually checking/fixing anything. The current (possibly broken) URL
    // is shown as a hint instead, for reference only.
    final controller = TextEditingController();
    // Retry is only enabled once the host has actually typed/pasted
    // something — even re-pasting the exact same URL is a deliberate act
    // that means "I checked it, try again", unlike a blank submit which
    // would silently reuse the old (possibly still-broken) link with no
    // signal the host looked at it at all.
    final newUrl = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Submit a working Airbnb link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Founder-specified copy (2026-09-19): the reason and the
              // current link collapse into one sentence, not two separate
              // lines as before.
              Text('$_scrapeLinkIssueReason: $currentUrl',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              const Text(
                'Verify the new link loads correctly in your browser, then paste it below.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Airbnb URL',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              // Same format guard as the Add Property URL field — without it,
              // gibberish input still enabled Retry and burned a real
              // resume/re-scrape cycle on something that was never going to
              // work (confirmed live: typing "eewfaf" enabled Retry).
              onPressed: controller.text.trim().toLowerCase().contains('airbnb.')
                  ? () => Navigator.of(ctx).pop(controller.text.trim())
                  : null,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
    if (newUrl != null && newUrl.isNotEmpty) {
      await _retryScrapeLink(newUrl);
    }
  }

  Widget _airbnbUrlRow(String url) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text('Airbnb URL:',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Expanded(
            child: InkWell(
              onTap: () => launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              ),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      url,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.open_in_new_rounded,
                    size: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  if (_scrapeLinkNeedsAttention && !_scrapeLinkRetrying) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: '$_scrapeLinkIssueReason. Tap to fix it.',
                      child: InkWell(
                        onTap: () => _showFixLinkDialog(url),
                        child: Icon(
                          Icons.error_outline_rounded,
                          size: 24,
                          color: context.palette.warning,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesTab() {
    final fingerprints =
        _property['file_fingerprints'] as Map<String, dynamic>? ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Edit button at the top
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: OutlinedButton.icon(
            onPressed: () {
              final nav = Navigator.of(context);
              final refresh = widget.onRefresh;
              // pushReplacement, not pop()+push() -- see the matching
              // comment on the SetupStatusBanner action in _buildOverviewTab.
              nav.pushReplacement(MaterialPageRoute(
                builder: (_) => EditPropertyScreen(
                  property: _property,
                  isDev: widget.isDev,
                ),
              )).then((_) => refresh());
            },
            icon: Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit Property / Add Files'),
          ),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Divider(height: 1),
        ),
        // File list
        Expanded(
          child: fingerprints.isEmpty
              ? const Center(
                  child: Text('No files ingested yet.',
                      style: TextStyle(color: Colors.grey)))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: fingerprints.entries.map((e) {
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.insert_drive_file_outlined,
                          size: 20),
                      title: Text(e.key,
                          style: const TextStyle(fontSize: 13)),
                      contentPadding: EdgeInsets.zero,
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildKnowledgeTab() {
    final masterJson = _property['master_json'] as Map<String, dynamic>?;
    final prettyJson = masterJson != null
        ? const JsonEncoder.withIndent('  ').convert(masterJson)
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.isDev) ...[
            // Master JSON viewer
            Text('Master JSON',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (prettyJson != null)
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8)),
                child: SingleChildScrollView(
                  child: SelectableText(
                    prettyJson,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.5,
                        color: Color(0xFFD4D4D4)),
                  ),
                ),
              )
            else
              Text('No master JSON yet.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
          ],
          _wtHighlight(
            step: 2,
            key: _wtAddKnowledgeKey,
            child: Text('Add New Knowledge',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 12),

          // Text input
          TextField(
            controller: _knowledgeController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Type new info here...',
              border: OutlineInputBorder(),
            ),
          ),
          if (_knowledgeError != null) ...[
            const SizedBox(height: 6),
            Text(_knowledgeError!,
                style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: VoiceRecorderWidget(
                  propertyId: _property['id'] as String,
                  onFileAdded: _onVoiceFileAdded,
                  onRecordingResult: _onVoiceFileResult,
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _addingKnowledge ? null : _addKnowledge,
                child: _addingKnowledge
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : const Text('Add Knowledge'),
              ),
            ],
          ),

          // Success confirmation
          if (_knowledgeSuccess) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                border: Border.all(color: Colors.green.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      color: Colors.green.shade600, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Knowledge added — master JSON updated successfully.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.green.shade800),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Voice progress
          if (_voiceStatuses.isNotEmpty) ...[
            const SizedBox(height: 12),
            FileStatusList(statuses: _voiceStatuses),
          ],

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),

          // Automated Learning section
          Builder(builder: (context) {
            if (!_learnedLoaded && !_loadingLearned) {
              _loadLearnedKnowledge();
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _wtHighlight(
                  step: 3,
                  key: _wtLearningKey,
                  child: Row(
                    children: [
                      Icon(Icons.bolt_rounded, size: 15, color: context.palette.accent),
                      const SizedBox(width: 6),
                      Text(
                        'Automated Learning',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _showKnowledgeVault,
                        icon: const Icon(Icons.inventory_2_outlined, size: 15),
                        label: Text(_vaultLearned.isEmpty
                            ? 'Vault'
                            : 'Vault (${_vaultLearned.length})'),
                        style: TextButton.styleFrom(
                          foregroundColor: context.palette.textSecondary,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          textStyle: GoogleFonts.inter(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Q&A entries captured automatically when issues are resolved.',
                  style: GoogleFonts.inter(fontSize: 11, color: context.palette.textMuted),
                ),
                const SizedBox(height: 12),
                if (_loadingLearned)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: CircularProgressIndicator(color: context.palette.primary),
                    ),
                  )
                else if (_pendingLearned.isEmpty)
                  Text(
                    _vaultLearned.isEmpty
                        ? 'No automated learning entries yet. Resolve an escalation to generate one.'
                        : 'All caught up — nothing waiting for review. Open the Vault to see what Alfred has learned.',
                    style: GoogleFonts.inter(fontSize: 12, color: context.palette.textMuted),
                  )
                else
                  ..._pendingLearned.map((e) {
                    final index = e.key;
                    final entry = e.value;
                    final reviewed = entry['reviewed'] == true;
                    final inGrace = _acceptGrace.contains(_learnedKey(entry, index));
                    final isEditing = _editingLearnedIndex == index;
                    final bg = reviewed ? Colors.green.shade50 : Colors.orange.shade50;
                    final borderColor = reviewed ? Colors.green.shade300 : Colors.orange.shade300;
                    final category = entry['category'] as String? ?? 'other';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: bg,
                        border: Border.all(color: borderColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: reviewed ? Colors.green.shade100 : Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  category,
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: reviewed ? Colors.green.shade700 : Colors.orange.shade700,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              if (reviewed)
                                Icon(Icons.check_circle_rounded, size: 14, color: Colors.green.shade600),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (isEditing) ...[
                            TextField(
                              controller: _editProblemCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Problem',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              style: GoogleFonts.inter(fontSize: 12),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _editSolutionCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Solution',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              style: GoogleFonts.inter(fontSize: 12),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                FilledButton.tonal(
                                  onPressed: () => _saveLearned(index),
                                  child: const Text('Save'),
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () => setState(() => _editingLearnedIndex = null),
                                  child: const Text('Cancel'),
                                ),
                              ],
                            ),
                          ] else ...[
                            Text(
                              'Q: ${entry['problem_summary'] ?? ''}',
                              style: GoogleFonts.inter(fontSize: 12, color: context.palette.textPrimary, height: 1.4),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'A: ${entry['solution_summary'] ?? ''}',
                              style: GoogleFonts.inter(fontSize: 12, color: context.palette.textSecondary, height: 1.4),
                            ),
                            const SizedBox(height: 10),
                            if (inGrace)
                              Row(
                                children: [
                                  Icon(Icons.check_circle_rounded,
                                      size: 15, color: Colors.green.shade600),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Saved to Vault',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: () => _undoAccept(index),
                                    icon: const Icon(Icons.undo_rounded, size: 14),
                                    label: const Text('Undo'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: context.palette.textSecondary,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      textStyle: GoogleFonts.inter(fontSize: 12),
                                    ),
                                  ),
                                ],
                              )
                            else
                              Row(
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _acceptLearned(index),
                                    icon: Icon(Icons.check_rounded, size: 14),
                                    label: const Text('Accept'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.green.shade700,
                                      side: BorderSide(color: Colors.green.shade400),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      textStyle: GoogleFonts.inter(fontSize: 12),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      _editProblemCtrl.text = entry['problem_summary'] as String? ?? '';
                                      _editSolutionCtrl.text = entry['solution_summary'] as String? ?? '';
                                      setState(() => _editingLearnedIndex = index);
                                    },
                                    icon: Icon(Icons.edit_outlined, size: 14),
                                    label: const Text('Edit'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: context.palette.textSecondary,
                                      side: BorderSide(color: context.palette.border),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      textStyle: GoogleFonts.inter(fontSize: 12),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  OutlinedButton.icon(
                                    onPressed: () => _discardLearned(index),
                                    icon: Icon(Icons.delete_outline_rounded, size: 14),
                                    label: const Text('Discard'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red.shade700,
                                      side: BorderSide(color: Colors.red.shade300),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      textStyle: GoogleFonts.inter(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ],
                      ),
                    );
                  }),
              ],
            );
          }),

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),

          // Knowledge base chat
          _wtHighlight(
            step: 4,
            key: _wtChatKey,
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded,
                    size: 15, color: context.palette.accent),
                const SizedBox(width: 6),
                Text('Ask the Knowledge Base',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ask Alfred anything about this property\'s knowledge base.',
            style: GoogleFonts.inter(fontSize: 11, color: context.palette.textMuted),
          ),
          const SizedBox(height: 12),

          // Chat history
          if (_kbHistory.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                reverse: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _kbHistory.map((entry) {
                    final q = entry['q'] ?? '';
                    final a = entry['a'] ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Host question
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                              decoration: BoxDecoration(
                                color: context.palette.primaryContainer,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(12),
                                  topRight: Radius.circular(12),
                                  bottomLeft: Radius.circular(12),
                                  bottomRight: Radius.circular(3),
                                ),
                              ),
                              child: Text(q,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: context.palette.onPrimaryContainer,
                                  )),
                            ),
                          ),
                          const SizedBox(height: 6),
                          // Alfred answer
                          if (a.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Row(children: [
                                SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: context.palette.accent)),
                                const SizedBox(width: 6),
                                Text('Alfred is thinking…',
                                    style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: context.palette.textMuted,
                                        fontStyle: FontStyle.italic)),
                              ]),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                              decoration: BoxDecoration(
                                color: context.palette.surfaceAlt,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(3),
                                  topRight: Radius.circular(12),
                                  bottomLeft: Radius.circular(12),
                                  bottomRight: Radius.circular(12),
                                ),
                              ),
                              child: Text(a,
                                  style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: context.palette.textPrimary)),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

          // Input row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _kbChatController,
                  decoration: InputDecoration(
                    hintText: 'e.g. How many guests can stay?',
                    hintStyle: GoogleFonts.inter(
                        fontSize: 12, color: context.palette.textMuted),
                    filled: true,
                    fillColor: context.palette.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: context.palette.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: context.palette.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: context.palette.primary, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    isDense: true,
                  ),
                  style: GoogleFonts.inter(
                      fontSize: 13, color: context.palette.textPrimary),
                  onSubmitted: (_) => _queryKnowledgeBase(),
                  textInputAction: TextInputAction.send,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _kbQuerying ? null : _queryKnowledgeBase,
                icon: _kbQuerying
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: context.palette.primary))
                    : Icon(Icons.send_rounded,
                        size: 18, color: context.palette.primary),
                style: IconButton.styleFrom(
                  backgroundColor: context.palette.primaryContainer,
                  disabledBackgroundColor: context.palette.surfaceAlt,
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),

          // Danger zone: delete property
          OutlinedButton.icon(
            onPressed: _confirmDeleteProperty,
            icon: Icon(Icons.delete_forever_outlined, size: 16),
            label: const Text('Delete Property'),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.palette.danger,
              side: BorderSide(color: context.palette.danger.withValues(alpha: 0.5)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            // Was "Deletes this property entry." — understated the actual
            // severity of the confirm dialog it triggers, below.
            'Permanently deletes this property and all its training data.',
            style: TextStyle(fontSize: 11, color: context.palette.textMuted),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteProperty() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
          const SizedBox(width: 8),
          const Text('Delete Property'),
        ]),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 14, color: Colors.black87),
            children: [
              const TextSpan(text: 'Are you sure you want to delete '),
              TextSpan(
                text: _property['name'] as String? ?? 'this property',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const TextSpan(
                text: '?\n\n⚠️ ALL PROPERTY DATA WILL BE LOST.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      // Soft-delete via the backend: it blanks the property data, drops the
      // storage files, and anonymizes guests under the service role, while
      // keeping conversations/messages for training. Hard-deleting the row
      // here would violate the FK from those retained chats. The host's access
      // token proves ownership server-side.
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      await ApiClient.postJson(
        '/api/property/${_property['id']}/soft-delete',
        const {},
        bearer: token,
      );
      if (mounted) {
        Navigator.of(context).pop();
        widget.onRefresh();
      }
    } catch (e) {
      if (mounted) {
        final msg = e is ApiException ? e.userMessage : '$e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Delete failed: $msg'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildResolveTab() {
    final masterJson = _property['master_json'] as Map<String, dynamic>?;
    final conflictReport = masterJson?['conflict_report'] as List<dynamic>?;

    if (conflictReport == null || conflictReport.isEmpty) {
      return const Center(
        child: Text('No conflicts to resolve.',
            style: TextStyle(color: Colors.grey)),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConflictQuestionnaireWidget(
        key: ValueKey(conflictReport.length),
        propertyId: _property['id'] as String,
        conflictReport: conflictReport,
        onResolved: _onResolved,
      ),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(top: BorderSide(color: context.palette.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                showDialog(
                  context: context,
                  builder: (_) =>
                      GenerateGuestLinkDialog(
                          property: _property, isDev: widget.isDev),
                );
              },
              icon: Icon(Icons.link, size: 16),
              label: const Text('+ Guest Link'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                // Was HostPanelScreen (plain Material colors, no glass
                // treatment, missing guest-link/archive context) — reuses the
                // same themed conversation-list dialog "Chat History" already
                // used correctly elsewhere, just scoped to active
                // conversations instead of archived ones.
                showDialog(
                  context: context,
                  builder: (_) => ArchivedChatsDialog(
                    propertyId: _property['id'] as String,
                    propertyName: _property['name'] as String? ?? 'Property',
                    showArchived: false,
                  ),
                );
              },
              icon: Icon(Icons.chat_bubble_outline, size: 16),
              label: const Text('Host Chat'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [context.palette.accent, context.palette.primary],
        ),
      ),
      child: Center(
        child: Icon(Icons.home_outlined,
            size: 48, color: Colors.white.withValues(alpha: 0.7)),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool isLink = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text('$label:',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                  fontSize: 13,
                  color: isLink ? context.palette.accent : null),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
