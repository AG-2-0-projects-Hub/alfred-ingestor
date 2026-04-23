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

  /// Called immediately when a supported file is selected (before upload completes).
  /// Used by IngestScreen to add the file to the "Files to Ingest" list (REQ-13, REQ-15).
  final void Function(String filename) onFileAdded;

  /// Called after the upload attempt completes with success/failure.
  final void Function(String filename, bool success) onFileResult;

  const DropZoneWidget({
    super.key,
    required this.propertyId,
    required this.onFileAdded,
    required this.onFileResult,
  });

  @override
  State<DropZoneWidget> createState() => _DropZoneWidgetState();
}

class _DropZoneWidgetState extends State<DropZoneWidget> {
  bool _isDragging = false;
  String? _unsupportedError;

  String _sanitizeFilename(String filename) =>
      filename.replaceAll(RegExp(r'[^\w.\- ]'), '_');

  Future<void> _uploadBytes(String filename, Uint8List bytes) async {
    final safeFilename = _sanitizeFilename(filename);
    widget.onFileAdded(safeFilename); // notify IngestScreen immediately (REQ-15)

    try {
      final mime = lookupMimeType(safeFilename) ?? 'application/octet-stream';
      final path = '${widget.propertyId}/user_uploads/$safeFilename';
      await Supabase.instance.client.storage
          .from('Property_assets')
          .uploadBinary(path, bytes,
              fileOptions: FileOptions(contentType: mime, upsert: true));
      widget.onFileResult(safeFilename, true);
    } catch (e) {
      widget.onFileResult(safeFilename, false);
    }
  }

  Future<void> _pickFiles() async {
    setState(() => _unsupportedError = null);
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
          onDragEntered: (_) => setState(() {
            _isDragging = true;
            _unsupportedError = null;
          }),
          onDragExited: (_) => setState(() => _isDragging = false),
          onDragDone: (details) async {
            setState(() => _isDragging = false);
            for (final file in details.files) {
              final ext = file.name.split('.').last.toLowerCase();
              if (!_supportedExtensions.contains(ext)) {
                // REQ-09: reject unsupported types inline, do NOT upload
                setState(() =>
                    _unsupportedError = '${file.name} — unsupported file type');
                continue;
              }
              final bytes = await file.readAsBytes();
              await _uploadBytes(file.name, Uint8List.fromList(bytes));
            }
          },
          child: GestureDetector(
            onTap: _pickFiles,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 120,
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
                    size: 36,
                    color: _isDragging ? Colors.indigo : Colors.grey,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isDragging
                        ? 'Drop files here'
                        : 'Drag & drop or tap to browse',
                    style: TextStyle(
                        color: _isDragging
                            ? Colors.indigo
                            : Colors.grey.shade600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'PDF · DOCX · Images · Sheets · Audio',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_unsupportedError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _unsupportedError!,
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          ),
      ],
    );
  }
}
