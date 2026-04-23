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
  final _nicknameController = TextEditingController();
  final _urlController = TextEditingController();
  late final String _propertyId;
  String? _resolvedPropertyId; // canonical ID from (system) SSE event (REQ-19)
  bool _isIngesting = false;
  final List<Map<String, String>> _filesToIngest = []; // pre-ingest list (REQ-15)
  final List<Map<String, String>> _fileStatuses = []; // post-ingest SSE (REQ-16)
  String? _ingestedMarkdown;
  String? _officialPropertyName; // parsed from scraped_markdown (REQ-03)
  String? _heroImageUrl; // signed URL for hero image (REQ-18)

  @override
  void initState() {
    super.initState();
    _propertyId = _generateUuidV4();
    _urlController.addListener(() => setState(() {})); // drives canIngest (REQ-02)
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _urlController.dispose();
    super.dispose();
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

  // Called immediately when a file is selected/recorded — before upload (REQ-13, REQ-15)
  void _onFileAdded(String filename) {
    setState(() {
      _filesToIngest.add({'file': filename, 'status': 'processing', 'message': ''});
    });
  }

  // Called after upload completes — update pre-ingest status badge (REQ-15)
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
      _resolvedPropertyId = null;
      _fileStatuses.clear();
      _ingestedMarkdown = null;
      _officialPropertyName = null;
      _heroImageUrl = null;
    });

    // Backend owns the Supabase upsert (REQ-19) — no frontend write here.
    final backendUrl = dotenv.env['BACKEND_URL'] ?? 'http://localhost:8000';
    try {
      final request =
          http.Request('POST', Uri.parse('$backendUrl/api/ingest'))
            ..headers['Content-Type'] = 'application/json'
            ..body = jsonEncode({
              'property_id': _propertyId,
              'property_name': _nicknameController.text.trim(),
              'airbnb_url': url,
            });

      final response = await http.Client().send(request);
      try {
        // 90 s silence = backend dead (heartbeats every 10 s reset the timer).
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

      // Fetch both markdowns using canonical property ID (REQ-03, REQ-18)
      final effectiveId = _resolvedPropertyId ?? _propertyId;
      final result = await Supabase.instance.client
          .from('properties')
          .select('ingested_markdown, scraped_markdown')
          .eq('id', effectiveId)
          .maybeSingle();

      if (result != null) {
        final ingested = result['ingested_markdown'] as String?;
        final scraped = result['scraped_markdown'] as String?;
        final name = _parseOfficialName(scraped);
        final heroUrl = await _getHeroImageUrl(effectiveId);
        setState(() {
          _ingestedMarkdown = ingested;
          _officialPropertyName = name;
          _heroImageUrl = heroUrl;
          _filesToIngest.clear(); // files have moved to "Files Ingested" (REQ-16)
        });
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
    final message = event['message'] as String? ?? '';

    if (status == 'heartbeat' || status == 'stream_closed') return;

    // System event — capture canonical property ID (REQ-19, REQ-20)
    if (file == '(system)' && status == 'property_id') {
      setState(() => _resolvedPropertyId = message);
      return;
    }

    setState(() {
      final idx = _fileStatuses.indexWhere((s) => s['file'] == file);
      if (idx >= 0) {
        _fileStatuses[idx] = {'file': file, 'status': status, 'message': message};
      } else {
        _fileStatuses.add({'file': file, 'status': status, 'message': message});
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

  // Extract official listing name from scraped_markdown (REQ-03)
  String? _parseOfficialName(String? markdown) {
    if (markdown == null) return null;
    final match =
        RegExp(r'\*\*Property Name:\*\*\s*(.+)').firstMatch(markdown);
    return match?.group(1)?.trim();
  }

  // Generate a 1-hour signed URL for the hero image (REQ-18)
  Future<String?> _getHeroImageUrl(String propertyId) async {
    try {
      return await Supabase.instance.client.storage
          .from('Property_assets')
          .createSignedUrl('$propertyId/hero_image/main.jpg', 3600);
    } catch (_) {
      return null;
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    // canIngest: URL required, nickname is optional (REQ-02)
    final canIngest = _urlController.text.trim().isNotEmpty && !_isIngesting;

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
                // ── Nickname (optional) — REQ-02 ───────────────────────────
                TextField(
                  controller: _nicknameController,
                  decoration: const InputDecoration(
                    labelText: 'Nickname (Optional)',
                    hintText: 'e.g. Beach House Malibu',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Airbnb URL (required) — REQ-02 ─────────────────────────
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'Airbnb URL *',
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
                  onFileAdded: _onFileAdded, // REQ-15
                  onFileResult: _onFileResult,
                ),
                const SizedBox(height: 16),

                // ── Voice Recorder ─────────────────────────────────────────
                VoiceRecorderWidget(
                  propertyId: _propertyId,
                  onFileAdded: _onFileAdded, // REQ-13
                  onRecordingResult: _onFileResult,
                ),

                // ── Files to Ingest — REQ-15 ────────────────────────────────
                if (_filesToIngest.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Files to Ingest',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  FileStatusList(statuses: _filesToIngest),
                ],

                const SizedBox(height: 28),

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

                // ── Files Ingested — REQ-16, REQ-17 ────────────────────────
                if (_fileStatuses.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Text(
                    'Files Ingested',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  FileStatusList(statuses: _fileStatuses),
                ],

                // ── Extracted Knowledge — REQ-03, REQ-18 ──────────────────
                if (_ingestedMarkdown != null &&
                    _ingestedMarkdown!.isNotEmpty) ...[
                  const SizedBox(height: 40),
                  const Divider(),
                  const SizedBox(height: 20),

                  // Hero image (REQ-18)
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

                  // Official property name as h1 (REQ-03)
                  if (_officialPropertyName != null) ...[
                    Text(
                      _officialPropertyName!,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                  ],

                  Text(
                    'Extracted Knowledge',
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500),
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
