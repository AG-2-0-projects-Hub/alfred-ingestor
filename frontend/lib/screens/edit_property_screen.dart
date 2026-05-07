import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../widgets/drop_zone.dart';
import '../widgets/voice_recorder.dart';
import '../widgets/file_status_list.dart';
import '../widgets/conflict_questionnaire.dart';

class EditPropertyScreen extends StatefulWidget {
  final Map<String, dynamic> property;

  const EditPropertyScreen({super.key, required this.property});

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
  final List<Map<String, String>> _filesToIngest = [];
  final List<Map<String, String>> _fileStatuses = [];
  String? _ingestedMarkdown;
  String? _propertyStatus;
  Map<String, dynamic>? _masterJson;

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
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _deleteExistingFile(filename);
  }

  void _onFileAdded(String filename) {
    setState(() => _filesToIngest
        .add({'file': filename, 'status': 'processing', 'message': ''}));
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
    if (_isIngesting) return;

    setState(() {
      _isIngesting = true;
      _fileStatuses.clear();
      _ingestedMarkdown = null;
      _propertyStatus = null;
      _masterJson = null;
    });

    final backendUrl = dotenv.env['BACKEND_URL'] ?? 'http://localhost:8000';
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;

    try {
      final request = http.Request('POST', Uri.parse('$backendUrl/api/ingest'))
        ..headers['Content-Type'] = 'application/json';
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      request.body = jsonEncode({
        'property_id': _propertyId,
        'property_name': _nicknameController.text.trim(),
        'airbnb_url': widget.property['airbnb_url'] as String? ?? '',
      });

      final response = await http.Client().send(request);
      try {
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
      } finally {
        _markPendingFilesAsTimeout();
      }

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
            _filesToIngest.clear();
          });
        }
      }
    } catch (e) {
      _showError('Ingest failed: $e');
    } finally {
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
      final idx = _fileStatuses.indexWhere((s) => s['file'] == file);
      final entry = {'file': file, 'status': status, 'message': message};
      if (idx >= 0) {
        _fileStatuses[idx] = entry;
      } else {
        _fileStatuses.add(entry);
      }
    });
  }

  void _markPendingFilesAsTimeout() {
    setState(() {
      for (var i = 0; i < _fileStatuses.length; i++) {
        final s = _fileStatuses[i]['status'];
        if (s == 'queued' || s == 'processing') {
          _fileStatuses[i] = {
            'file': _fileStatuses[i]['file']!,
            'status': 'timeout',
            'message': 'No response — try again',
          };
        }
      }
    });
  }

  Future<void> _runMerge() async {
    final backendUrl = dotenv.env['BACKEND_URL'] ?? 'http://localhost:8000';
    setState(() => _isMerging = true);
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/api/merge/$_propertyId'),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _propertyStatus = data['status'] as String?;
          _masterJson = data['master_json'] as Map<String, dynamic>?;
        });
      } else {
        _showError('Merge failed (${response.statusCode})');
      }
    } catch (e) {
      _showError('Merge failed: $e');
    } finally {
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
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
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
                // Property name (editable)
                TextField(
                  controller: _nicknameController,
                  decoration: const InputDecoration(
                    labelText: 'Property Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                // Airbnb URL (read-only info)
                if ((widget.property['airbnb_url'] as String?)?.isNotEmpty ?? false)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Airbnb: ${widget.property['airbnb_url']}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        // Active files
                        ..._existingFiles.entries.map((e) {
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.insert_drive_file_outlined,
                                size: 18),
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
                                        size: 18, color: Colors.red.shade400),
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
                                size: 18, color: Colors.red.shade300),
                            title: Text(
                              filename,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade400,
                                decoration: TextDecoration.lineThrough,
                                decorationColor: Colors.grey.shade400,
                              ),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                border: Border.all(color: Colors.red.shade200),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('Removed',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.red.shade600,
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
                      color: Colors.amber.shade50,
                      border: Border.all(color: Colors.amber.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Colors.amber.shade700, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'The knowledge database still contains data extracted from removed files. '
                            'Add new files below and re-ingest to keep the knowledge base up to date.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.amber.shade900),
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

                // Re-ingest button
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

                // Post-ingest results
                if (_fileStatuses.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Text('Files Ingested',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  FileStatusList(statuses: _fileStatuses),
                ],
                if (_ingestedMarkdown != null && _ingestedMarkdown!.isNotEmpty) ...[
                  const SizedBox(height: 40),
                  const Divider(),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      border: Border.all(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: MarkdownBody(
                      data: _ingestedMarkdown!,
                      selectable: true,
                    ),
                  ),
                ],
                if (_propertyStatus != null) ...[
                  const SizedBox(height: 40),
                  const Divider(),
                  const SizedBox(height: 20),
                  if (_propertyStatus == 'Ingested' &&
                      (_ingestedMarkdown?.isNotEmpty ?? false)) ...[
                    FilledButton(
                      onPressed: _isMerging ? null : _runMerge,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        backgroundColor: Colors.indigo.shade600,
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
                  if (_postMergeStatuses.contains(_propertyStatus)) ...[
                    const SizedBox(height: 24),
                    if (_masterJson != null) ...[
                      Text('Master JSON',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
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
                      backendUrl: dotenv.env['BACKEND_URL'] ?? 'http://localhost:8000',
                      onResolved: _onResolved,
                    ),
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
