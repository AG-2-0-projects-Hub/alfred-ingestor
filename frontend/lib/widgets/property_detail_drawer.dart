import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'voice_recorder.dart';
import 'file_status_list.dart';
import 'conflict_questionnaire.dart';
import 'generate_guest_link_dialog.dart';
import '../screens/host_panel_screen.dart';
import '../screens/edit_property_screen.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/setup_status.dart';
import 'setup_status_banner.dart';

class PropertyDetailDrawer extends StatefulWidget {
  final Map<String, dynamic> property;
  final VoidCallback onRefresh;

  const PropertyDetailDrawer({
    super.key,
    required this.property,
    required this.onRefresh,
  });

  @override
  State<PropertyDetailDrawer> createState() => _PropertyDetailDrawerState();
}

class _PropertyDetailDrawerState extends State<PropertyDetailDrawer>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
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

  @override
  void initState() {
    super.initState();
    _property = Map<String, dynamic>.from(widget.property);
    final hasConflict = _property['Conflict_status'] == 'pending';
    _tabController = TabController(
      length: hasConflict ? 4 : 3,
      vsync: this,
    );
    _loadHeroUrl();
    _subscribeProperty();
  }

  @override
  void dispose() {
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
          });
        });
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

  Future<void> _refreshProperty() async {
    try {
      final data = await Supabase.instance.client
          .from('properties')
          .select('id, name, status, airbnb_url, created_at, master_json, file_fingerprints, Conflict_status')
          .eq('id', _property['id'] as String)
          .single();
      if (mounted) setState(() => _property = data);
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

    final backendUrl = dotenv.env['BACKEND_URL'] ?? 'http://localhost:8000';
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;

    try {
      final response = await http.post(
        Uri.parse('$backendUrl/api/ingest/add-knowledge'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'property_id': _property['id'],
          'text': text,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
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
      } else {
        setState(() => _knowledgeError =
            'Failed (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      setState(() => _knowledgeError = 'Error: $e');
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
    final backendUrl = dotenv.env['BACKEND_URL'] ?? 'http://localhost:8000';
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;

    try {
      final response = await http.post(
        Uri.parse('$backendUrl/api/ingest/add-knowledge'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'property_id': _property['id'],
          'storage_path': '${_property['id']}/user_uploads/$filename',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
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
      } else {
        if (mounted) {
          setState(() {
            final idx = _voiceStatuses.indexWhere((e) => e['file'] == filename);
            if (idx >= 0) {
              _voiceStatuses[idx] = {
                'file': filename,
                'status': 'error',
                'message': 'Processing failed',
              };
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          final idx = _voiceStatuses.indexWhere((e) => e['file'] == filename);
          if (idx >= 0) {
            _voiceStatuses[idx] = {
              'file': filename,
              'status': 'error',
              'message': 'Error: $e',
            };
          }
        });
      }
    }
  }

  Future<void> _queryKnowledgeBase() async {
    final q = _kbChatController.text.trim();
    if (q.isEmpty || _kbQuerying) return;

    final backendUrl = dotenv.env['BACKEND_URL'] ?? 'http://localhost:8000';
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;

    setState(() {
      _kbQuerying = true;
      _kbHistory.add({'q': q, 'a': ''});
      _kbChatController.clear();
    });

    try {
      final response = await http.post(
        Uri.parse('$backendUrl/api/ingest/query-knowledge'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'property_id': _property['id'],
          'question': q,
        }),
      );
      if (mounted) {
        final answer = response.statusCode == 200
            ? (jsonDecode(response.body) as Map<String, dynamic>)['answer'] as String? ?? ''
            : 'Error (${response.statusCode}): ${response.body}';
        setState(() {
          _kbHistory[_kbHistory.length - 1] = {'q': q, 'a': answer};
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _kbHistory[_kbHistory.length - 1] = {'q': q, 'a': 'Error: $e'};
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
    final updated = List<Map<String, dynamic>>.from(_learnedKnowledge)
      ..removeAt(index);
    await _writeLearned(updated);
  }

  Future<bool> _confirmDelete(String question) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: Text(
          'This permanently removes it from $question learned knowledge. '
          'Alfred will no longer use it to answer guests.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
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
                                              'this property’s')) {
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
    final hasConflict = _property['Conflict_status'] == 'pending';
    final screenW = MediaQuery.of(context).size.width;
    final drawerW = screenW < 600 ? screenW : 440.0;

    return Material(
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
                  const Tab(text: 'Files'),
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
                    _buildFilesTab(),
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
                nav.pop();
                nav.push(MaterialPageRoute(
                  builder: (_) => EditPropertyScreen(property: _property),
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
          _infoRow('Status', status),
          if (airbnbUrl.isNotEmpty)
            _airbnbUrlRow(airbnbUrl),
          if (createdAt.isNotEmpty)
            _infoRow('Added', _formatDate(createdAt)),
          const SizedBox(height: 8),
          _buildWelcomeLanguageSetting(),
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
              nav.pop();
              nav.push(MaterialPageRoute(
                builder: (_) => EditPropertyScreen(property: _property),
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
          Text('Add New Knowledge',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
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
                Row(
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
          Row(
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
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade300),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Deletes this property entry.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
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
        backendUrl: dotenv.env['BACKEND_URL'] ?? 'http://localhost:8000',
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
                      GenerateGuestLinkDialog(property: _property),
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
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => HostPanelScreen(
                        propertyId: _property['id'] as String),
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
