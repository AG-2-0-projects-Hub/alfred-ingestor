import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mime/mime.dart';

const _supportedExtensions = [
  'pdf', 'doc', 'docx',
  'jpg', 'jpeg', 'png', 'webp', 'heic', 'gif',
  'xlsx', 'xls', 'csv',
  'mp3', 'wav', 'ogg', 'm4a', 'aac', 'webm',
];

class DropZoneWidget extends StatefulWidget {
  final String propertyId;
  final void Function(String filename, bool success) onFileResult;

  const DropZoneWidget({
    super.key,
    required this.propertyId,
    required this.onFileResult,
  });

  @override
  State<DropZoneWidget> createState() => _DropZoneWidgetState();
}

class _DropZoneWidgetState extends State<DropZoneWidget> {
  bool _isDragging = false;
  final List<_FileUploadState> _uploads = [];

  Future<void> _uploadBytes(String filename, Uint8List bytes) async {
    final entry = _FileUploadState(filename: filename);
    setState(() => _uploads.add(entry));

    try {
      final mime = lookupMimeType(filename) ?? 'application/octet-stream';
      final path = '${widget.propertyId}/user_uploads/$filename';
      await Supabase.instance.client.storage
          .from('Property_assets')
          .uploadBinary(path, bytes,
              fileOptions: FileOptions(contentType: mime, upsert: true));
      setState(() => entry.success = true);
      widget.onFileResult(filename, true);
    } catch (e) {
      setState(() {
        entry.success = false;
        entry.error = e.toString();
      });
      widget.onFileResult(filename, false);
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: _supportedExtensions,
    );
    if (result == null) return;
    for (final file in result.files) {
      if (file.bytes != null && file.name.isNotEmpty) {
        await _uploadBytes(file.name, file.bytes!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropTarget(
          onDragEntered: (_) => setState(() => _isDragging = true),
          onDragExited: (_) => setState(() => _isDragging = false),
          onDragDone: (details) async {
            setState(() => _isDragging = false);
            for (final file in details.files) {
              final bytes = await file.readAsBytes();
              await _uploadBytes(file.name, Uint8List.fromList(bytes));
            }
          },
          child: GestureDetector(
            onTap: _pickFiles,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 140,
              decoration: BoxDecoration(
                color: _isDragging
                    ? Colors.indigo.shade50
                    : Colors.grey.shade100,
                border: Border.all(
                  color: _isDragging ? Colors.indigo : Colors.grey.shade400,
                  width: _isDragging ? 2 : 1,
                  style: BorderStyle.solid,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    size: 40,
                    color: _isDragging ? Colors.indigo : Colors.grey,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isDragging
                        ? 'Drop files here'
                        : 'Drag & drop files or tap to browse',
                    style: TextStyle(
                        color: _isDragging ? Colors.indigo : Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'PDF | DOCX | Images | Sheets | Audio',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_uploads.isNotEmpty) ...[
          const SizedBox(height: 8),
          ..._uploads.map((u) => _FileChip(state: u)),
        ],
      ],
    );
  }
}

class _FileUploadState {
  final String filename;
  bool? success;
  String? error;
  _FileUploadState({required this.filename});
}

class _FileChip extends StatelessWidget {
  final _FileUploadState state;
  const _FileChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final Widget icon;
    if (state.success == null) {
      icon = const SizedBox(
          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
    } else if (state.success!) {
      icon = const Icon(Icons.check_circle, size: 16, color: Colors.green);
    } else {
      icon = const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              icon,
              const SizedBox(width: 8),
              Expanded(
                child: Text(state.filename,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          if (state.success == false && state.error != null)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2, bottom: 2),
              child: Text(
                state.error!,
                style: TextStyle(fontSize: 11, color: Colors.red.shade700),
              ),
            ),
        ],
      ),
    );
  }
}
