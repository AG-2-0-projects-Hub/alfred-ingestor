import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'voice_recorder.dart';
import 'file_status_list.dart';
import 'conflict_questionnaire.dart';
import 'generate_guest_link_dialog.dart';
import '../screens/host_panel_screen.dart';
import '../screens/edit_property_screen.dart';

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
  String? _knowledgeError;

  // Voice path state (reuses voice recorder + file status)
  final List<Map<String, String>> _voiceStatuses = [];

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
  }

  @override
  void dispose() {
    _tabController.dispose();
    _knowledgeController.dispose();
    super.dispose();
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
            if (updatedJson != null) {
              _property['master_json'] = updatedJson;
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Knowledge added successfully')),
          );
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

  void _onResolved(String status, Map<String, dynamic> masterJson) {
    setState(() {
      _property['status'] = status;
      _property['master_json'] = masterJson;
      _property['Conflict_status'] = null;
    });
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final hasConflict = _property['Conflict_status'] == 'pending';

    return Material(
      elevation: 16,
      child: SizedBox(
        width: 420,
        height: double.infinity,
        child: Column(
          children: [
            // Header
            _buildHeader(),
            // Tabs
            TabBar(
              controller: _tabController,
              labelColor: Colors.indigo.shade700,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.indigo.shade700,
              tabs: [
                const Tab(text: 'Overview'),
                const Tab(text: 'Files'),
                const Tab(text: 'Knowledge'),
                if (hasConflict) const Tab(icon: Icon(Icons.warning_amber_rounded, size: 16), text: 'Resolve'),
              ],
            ),
            // Tab content
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
            // Pinned bottom actions
            _buildBottomActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final name = _property['name'] as String? ?? 'Property';
    return Container(
      color: Colors.indigo.shade700,
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero image
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: _heroLoaded && _heroUrl != null
                  ? Image.network(_heroUrl!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _heroPlaceholder())
                  : _heroLoaded
                      ? _heroPlaceholder()
                      : const ColoredBox(color: Color(0xFFE8EAF6)),
            ),
          ),
          const SizedBox(height: 16),
          _infoRow('Status', status),
          if (airbnbUrl.isNotEmpty)
            _infoRow('Airbnb URL', airbnbUrl, isLink: true),
          if (createdAt.isNotEmpty)
            _infoRow('Added', _formatDate(createdAt)),
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
            icon: const Icon(Icons.edit_outlined, size: 16),
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
                      leading: const Icon(Icons.insert_drive_file_outlined,
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

          // Voice progress
          if (_voiceStatuses.isNotEmpty) ...[
            const SizedBox(height: 12),
            FileStatusList(statuses: _voiceStatuses),
          ],

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),

          // Danger zone: delete property
          OutlinedButton.icon(
            onPressed: _confirmDeleteProperty,
            icon: const Icon(Icons.delete_forever_outlined, size: 16),
            label: const Text('Delete Property'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade300),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Deletes this property entry. Chat history is preserved.',
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
                text: '?\n\n⚠️ ALL PROPERTY DATA WILL BE LOST — '
                    'including the master JSON, ingested files, and scraper data.\n\n'
                    'Chat history with guests will be preserved.',
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
      await Supabase.instance.client
          .from('properties')
          .delete()
          .eq('id', _property['id'] as String);
      if (mounted) {
        Navigator.of(context).pop();
        widget.onRefresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Delete failed: $e'),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
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
              icon: const Icon(Icons.link, size: 16),
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
              icon: const Icon(Icons.chat_bubble_outline, size: 16),
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
          colors: [Colors.indigo.shade100, Colors.indigo.shade300],
        ),
      ),
      child: const Center(
        child: Icon(Icons.home_outlined, size: 48, color: Colors.white),
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
                  color: isLink ? Colors.indigo.shade700 : null),
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
