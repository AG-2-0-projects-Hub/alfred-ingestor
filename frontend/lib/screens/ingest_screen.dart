import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../widgets/drop_zone.dart';
import '../widgets/voice_recorder.dart';
import '../widgets/file_status_list.dart';

class IngestScreen extends StatefulWidget {
  const IngestScreen({super.key});

  @override
  State<IngestScreen> createState() => _IngestScreenState();
}

class _IngestScreenState extends State<IngestScreen> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  late final String _propertyId;
  bool _isIngesting = false;
  final List<Map<String, String>> _fileStatuses = [];
  String? _ingestedMarkdown;

  @override
  void initState() {
    super.initState();
    _propertyId = _generateUuidV4();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  /// Generates a UUID v4 without external packages.
  String _generateUuidV4() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> _startIngest() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _isIngesting) return;

    setState(() {
      _isIngesting = true;
      _fileStatuses.clear();
      _ingestedMarkdown = null;
    });

    // Upsert property row so files already uploaded under this UUID are linked.
    try {
      await Supabase.instance.client.from('properties').upsert({
        'id': _propertyId,
        'name': name,
        'airbnb_url': _urlController.text.trim(),
        'status': 'Ingesting',
      });
    } catch (e) {
      _showError('Failed to register property: $e');
      setState(() => _isIngesting = false);
      return;
    }

    // Call backend — stream SSE events.
    final backendUrl = dotenv.env['BACKEND_URL'] ?? 'http://localhost:8000';
    try {
      final request =
          http.Request('POST', Uri.parse('$backendUrl/api/ingest'))
            ..headers['Content-Type'] = 'application/json'
            ..body = jsonEncode({
              'property_id': _propertyId,
              'property_name': name,
              'airbnb_url': _urlController.text.trim(),
            });

      final response = await http.Client().send(request);
      await for (final chunk in response.stream.transform(utf8.decoder)) {
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

      // Fetch ingested markdown from Supabase once stream ends.
      final result = await Supabase.instance.client
          .from('properties')
          .select('ingested_markdown')
          .eq('id', _propertyId)
          .maybeSingle();
      if (result != null) {
        setState(
            () => _ingestedMarkdown = result['ingested_markdown'] as String?);
      }
    } catch (e) {
      _showError('Ingest failed: $e');
    } finally {
      setState(() => _isIngesting = false);
    }
  }

  void _handleSseEvent(Map<String, dynamic> event) {
    final file = event['file'] as String? ?? '';
    final status = event['status'] as String? ?? '';
    setState(() {
      final idx = _fileStatuses.indexWhere((s) => s['file'] == file);
      if (idx >= 0) {
        _fileStatuses[idx] = {'file': file, 'status': status};
      } else {
        _fileStatuses.add({'file': file, 'status': status});
      }
    });
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    final canIngest =
        _nameController.text.trim().isNotEmpty && !_isIngesting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alfred — Ingestor'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Property Name ──────────────────────────────────────────
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Property Name *',
                    hintText: 'e.g. Beach House Malibu',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Airbnb URL ─────────────────────────────────────────────
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'Airbnb URL',
                    hintText: 'https://www.airbnb.com/rooms/...',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 28),

                // ── Upload Files ───────────────────────────────────────────
                Text(
                  'Upload Files',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                DropZoneWidget(
                  propertyId: _propertyId,
                  onFileResult: (_, __) {},
                ),
                const SizedBox(height: 16),

                // ── Voice Recorder ─────────────────────────────────────────
                VoiceRecorderWidget(
                  propertyId: _propertyId,
                  onRecordingResult: (_, __) {},
                ),
                const SizedBox(height: 36),

                // ── INGEST NOW ─────────────────────────────────────────────
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
                                  strokeWidth: 2.5, color: Colors.white),
                            ),
                            SizedBox(width: 12),
                            Text('Ingesting...'),
                          ],
                        )
                      : const Text('INGEST NOW'),
                ),

                // ── Per-file SSE status ────────────────────────────────────
                if (_fileStatuses.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  FileStatusList(statuses: _fileStatuses),
                ],

                // ── Extracted Knowledge ────────────────────────────────────
                if (_ingestedMarkdown != null &&
                    _ingestedMarkdown!.isNotEmpty) ...[
                  const SizedBox(height: 40),
                  const Divider(),
                  const SizedBox(height: 20),
                  const Text(
                    'Extracted Knowledge',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
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
                      styleSheet: MarkdownStyleSheet(
                        h1: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                        h2: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                        h3: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                        p: const TextStyle(fontSize: 14, height: 1.6),
                        listBullet:
                            const TextStyle(fontSize: 14, height: 1.6),
                        blockquoteDecoration: BoxDecoration(
                          border: Border(
                              left: BorderSide(
                                  color: Colors.indigo.shade200, width: 3)),
                          color: Colors.indigo.shade50,
                        ),
                      ),
                    ),
                  ),
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
