import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mime/mime.dart';
import '../theme/app_theme.dart';

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
    final dragColor = AppTheme.primary;
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
            child: AnimatedScale(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              scale: _isDragging ? 1.015 : 1.0,
              child: CustomPaint(
                painter: _DashedBorderPainter(
                  color: _isDragging ? dragColor : AppTheme.borderStrong,
                  strokeWidth: _isDragging ? 2.0 : 1.5,
                  radius: 14,
                  dashLength: 8,
                  gap: 5,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 132,
                  decoration: BoxDecoration(
                    color: _isDragging
                        ? AppTheme.primaryContainer.withValues(alpha: 0.55)
                        : AppTheme.glassTint,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: _isDragging
                        ? [
                            BoxShadow(
                              color: dragColor.withValues(alpha: 0.18),
                              blurRadius: 24,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedScale(
                        duration: const Duration(milliseconds: 200),
                        scale: _isDragging ? 1.12 : 1.0,
                        child: Icon(
                          Icons.cloud_upload_outlined,
                          size: 36,
                          color: _isDragging ? dragColor : AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isDragging
                            ? 'Drop files here'
                            : 'Drag & drop or tap to browse',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: _isDragging
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: _isDragging
                              ? dragColor
                              : AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'PDF · DOCX · Images · Sheets · Audio',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_unsupportedError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _unsupportedError!,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppTheme.danger,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

/// Paints a dashed rounded rectangle. Flutter has no native dashed border.
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double radius;
  final double dashLength;
  final double gap;

  _DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
    required this.dashLength,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rect);
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final next = (distance + dashLength).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.radius != radius ||
      old.dashLength != dashLength ||
      old.gap != gap;
}
