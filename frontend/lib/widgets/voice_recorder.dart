// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VoiceRecorderWidget extends StatefulWidget {
  final String propertyId;

  /// Called immediately when recording stops and the filename is known,
  /// before the upload completes. Adds the file to the "Files to Ingest" list (REQ-13).
  final void Function(String filename) onFileAdded;

  /// Called after the upload attempt completes with success/failure.
  final void Function(String filename, bool success) onRecordingResult;

  const VoiceRecorderWidget({
    super.key,
    required this.propertyId,
    required this.onFileAdded,
    required this.onRecordingResult,
  });

  @override
  State<VoiceRecorderWidget> createState() => _VoiceRecorderWidgetState();
}

class _VoiceRecorderWidgetState extends State<VoiceRecorderWidget> {
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isUploading = false;

  Future<void> _start() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission denied.')),
      );
      return;
    }
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 128000,
      ),
      path: '',
    );
    setState(() => _isRecording = true);
  }

  String _sanitizeFilename(String filename) =>
      filename.replaceAll(RegExp(r'[^\w.\- ]'), '_');

  Future<void> _stop() async {
    setState(() => _isRecording = false);
    final path = await _recorder.stop();
    if (path == null) return;

    final filename = _sanitizeFilename(
        'voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a');

    // Notify IngestScreen immediately so the file appears in "Files to Ingest" (REQ-13)
    widget.onFileAdded(filename);

    setState(() => _isUploading = true);
    try {
      final bytes = await _readRecordingBytes(path);
      await Supabase.instance.client.storage
          .from('Property_assets')
          .uploadBinary(
            '${widget.propertyId}/user_uploads/$filename',
            bytes,
            fileOptions:
                const FileOptions(contentType: 'audio/m4a', upsert: true),
          );
      widget.onRecordingResult(filename, true);
    } catch (e) {
      widget.onRecordingResult(filename, false);
    } finally {
      setState(() => _isUploading = false);
    }
  }

  Future<Uint8List> _readRecordingBytes(String path) async {
    final response = await html.HttpRequest.request(
      path,
      responseType: 'arraybuffer',
    );
    final buffer = response.response as dynamic;
    return Uint8List.view(buffer as dynamic);
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (_isUploading)
          const Row(
            children: [
              SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Text('Uploading voice note...'),
            ],
          )
        else
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _isRecording ? Colors.red : null,
            ),
            onPressed: _isRecording ? _stop : _start,
            icon: Icon(_isRecording ? Icons.stop : Icons.mic),
            label:
                Text(_isRecording ? 'Stop Recording' : 'Record Voice Note'),
          ),
        if (_isRecording) ...[
          const SizedBox(width: 12),
          const _BlinkingDot(),
        ],
      ],
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: const Icon(Icons.fiber_manual_record,
          color: Colors.red, size: 14),
    );
  }
}
