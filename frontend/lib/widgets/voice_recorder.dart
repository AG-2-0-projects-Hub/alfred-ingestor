import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

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
  // Native browser MediaRecorder, not the `record` package — mirrors
  // chat_screen.dart's guest-side recorder (see its own comment there):
  // record_web routes audio through an AudioWorklet + a hand-rolled JS
  // resampler that drops samples (badly on mobile), which is why that file
  // moved off it. MediaRecorder captures losslessly on every browser; we
  // decode+re-encode to WAV the same way here (duplicated rather than shared
  // with chat_screen.dart, to avoid touching that already-verified
  // guest-facing flow for this fix).
  web.MediaRecorder? _mediaRecorder;
  web.MediaStream? _micStream;
  final List<web.Blob> _recordChunks = [];
  bool _isRecording = false;
  bool _isUploading = false;

  String _sanitizeFilename(String filename) =>
      filename.replaceAll(RegExp(r'[^\w.\- ]'), '_');

  void _stopMic() {
    final s = _micStream;
    if (s != null) {
      for (final t in s.getTracks().toDart) {
        t.stop();
      }
    }
    _micStream = null;
  }

  Future<void> _start() async {
    try {
      // getUserMedia is the only call that makes the browser show its mic
      // prompt — a real denial surfaces as an exception below.
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
          .toDart;
      if (!mounted) {
        // Widget was disposed while the permission prompt was pending --
        // stop the tracks immediately rather than starting a recording on
        // disposed state, which dispose() (already run) would never stop.
        for (final t in stream.getTracks().toDart) {
          t.stop();
        }
        return;
      }
      _micStream = stream;
      _recordChunks.clear();

      final rec = web.MediaRecorder(stream);
      rec.ondataavailable = ((web.BlobEvent e) {
        if (e.data.size > 0) _recordChunks.add(e.data);
      }).toJS;
      rec.onstop = ((web.Event _) {
        _finalizeAndUpload();
      }).toJS;
      _mediaRecorder = rec;
      rec.start(); // one blob delivered at stop()

      setState(() => _isRecording = true);
    } catch (e) {
      if (!mounted) return;
      _stopMic();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission denied.')),
      );
    }
  }

  Future<void> _stop() async {
    if (_mediaRecorder == null || !_isRecording) return;
    if (!mounted) return;
    setState(() => _isRecording = false);
    try {
      _mediaRecorder!.stop(); // async → onstop → _finalizeAndUpload
    } catch (e) {
      _stopMic();
      _mediaRecorder = null;
    }
  }

  /// onstop handler: decode the recorded blob with the browser's own decoder
  /// and re-encode as mono 16-bit WAV (the one format Gemini reads), then
  /// upload immediately — same auto-upload-on-stop behavior this widget
  /// always had, just with a correct/lossless audio pipeline underneath.
  Future<void> _finalizeAndUpload() async {
    _stopMic();
    final filename = _sanitizeFilename(
        'voice_note_${DateTime.now().millisecondsSinceEpoch}.wav');

    final Uint8List wav;
    try {
      final parts = <JSAny>[for (final b in _recordChunks) b].toJS;
      final blob = web.Blob(parts);
      final arrayBuffer = await blob.arrayBuffer().toDart;

      final ctx = web.AudioContext();
      final audioBuffer = await ctx.decodeAudioData(arrayBuffer).toDart;
      await ctx.close().toDart;

      wav = _encodeWavMono16(audioBuffer);
    } catch (e) {
      _mediaRecorder = null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Could not prepare that recording. Please try again.')),
      );
      return;
    }
    _mediaRecorder = null;
    // Checked before calling into the parent (unlike a stray earlier version
    // of this code) -- if disposed here, the parent is almost certainly also
    // being torn down, and calling its callback would hit an unguarded
    // setState on a disposed State.
    if (!mounted) return;

    // Notify the parent screen immediately so the file appears in the
    // unified file list, then upload.
    widget.onFileAdded(filename);
    setState(() => _isUploading = true);
    try {
      await Supabase.instance.client.storage
          .from('Property_assets')
          .uploadBinary(
            '${widget.propertyId}/user_uploads/$filename',
            wav,
            fileOptions:
                const FileOptions(contentType: 'audio/wav', upsert: true),
          );
      widget.onRecordingResult(filename, true);
    } catch (e) {
      widget.onRecordingResult(filename, false);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  /// Encode an AudioBuffer as mono, 16-bit PCM WAV at its native sample
  /// rate — identical approach to chat_screen.dart's own encoder.
  Uint8List _encodeWavMono16(web.AudioBuffer buffer) {
    final sampleRate = buffer.sampleRate.toInt();
    final frames = buffer.length;
    final channels = buffer.numberOfChannels;

    final ch0 = buffer.getChannelData(0).toDart;
    Float32List mono;
    if (channels <= 1) {
      mono = ch0;
    } else {
      final ch1 = buffer.getChannelData(1).toDart;
      mono = Float32List(frames);
      for (var i = 0; i < frames; i++) {
        mono[i] = (ch0[i] + ch1[i]) * 0.5;
      }
    }

    final dataLen = frames * 2; // 16-bit mono
    final out = ByteData(44 + dataLen);
    void writeStr(int off, String s) {
      for (var i = 0; i < s.length; i++) {
        out.setUint8(off + i, s.codeUnitAt(i));
      }
    }

    writeStr(0, 'RIFF');
    out.setUint32(4, 36 + dataLen, Endian.little);
    writeStr(8, 'WAVE');
    writeStr(12, 'fmt ');
    out.setUint32(16, 16, Endian.little); // PCM chunk size
    out.setUint16(20, 1, Endian.little); // audio format = PCM
    out.setUint16(22, 1, Endian.little); // channels = mono
    out.setUint32(24, sampleRate, Endian.little);
    out.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    out.setUint16(32, 2, Endian.little); // block align
    out.setUint16(34, 16, Endian.little); // bits per sample
    writeStr(36, 'data');
    out.setUint32(40, dataLen, Endian.little);

    var off = 44;
    for (var i = 0; i < frames; i++) {
      var s = mono[i];
      if (s > 1) {
        s = 1;
      } else if (s < -1) {
        s = -1;
      }
      out.setInt16(
          off, (s < 0 ? s * 0x8000 : s * 0x7FFF).round(), Endian.little);
      off += 2;
    }
    return out.buffer.asUint8List();
  }

  @override
  void dispose() {
    _stopMic();
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
