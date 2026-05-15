import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class FileThumbnail extends StatefulWidget {
  final String propertyId;
  final String fileName;
  final double size;
  const FileThumbnail({
    super.key,
    required this.propertyId,
    required this.fileName,
    this.size = 40,
  });

  @override
  State<FileThumbnail> createState() => _FileThumbnailState();
}

class _FileThumbnailState extends State<FileThumbnail> {
  String? _imageUrl;
  bool _isImage = false;

  @override
  void initState() {
    super.initState();
    _determineKind();
  }

  Future<void> _determineKind() async {
    final ext = widget.fileName.toLowerCase().split('.').last;
    final imgExts = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'gif'];
    if (imgExts.contains(ext)) {
      _isImage = true;
      try {
        final url = await Supabase.instance.client.storage
            .from('Property_assets')
            .createSignedUrl('${widget.propertyId}/${widget.fileName}', 3600);
        if (mounted) setState(() => _imageUrl = url);
      } catch (_) {
        _isImage = false;
        if (mounted) setState(() {});
      }
    }
  }

  ({IconData icon, Color color}) _iconFor(BuildContext context, String ext) {
    switch (ext) {
      case 'pdf':
        return (icon: Icons.picture_as_pdf_rounded, color: const Color(0xFFEF4444));
      case 'doc':
      case 'docx':
        return (icon: Icons.description_rounded, color: const Color(0xFF3B82F6));
      case 'csv':
      case 'xlsx':
      case 'xls':
        return (icon: Icons.table_chart_rounded, color: const Color(0xFF10B981));
      case 'm4a':
      case 'mp3':
      case 'wav':
      case 'ogg':
        return (icon: Icons.audiotrack_rounded, color: const Color(0xFFA78BFA));
      case 'txt':
      case 'md':
        return (icon: Icons.notes_rounded, color: context.palette.textSecondary);
      default:
        return (icon: Icons.insert_drive_file_rounded, color: context.palette.textSecondary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ext = widget.fileName.toLowerCase().split('.').last;
    return Tooltip(
      message: widget.fileName,
      child: Semantics(
        label: 'File: ${widget.fileName}',
        image: _isImage,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: widget.size,
            height: widget.size,
            color: context.palette.surfaceAlt,
            child: _isImage && _imageUrl != null
                ? Image.network(
                    _imageUrl!,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return Center(
                        child: SizedBox(
                          width: widget.size * 0.4,
                          height: widget.size * 0.4,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.palette.textMuted,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (_, __, ___) {
                      final ico = _iconFor(context, ext);
                      return Icon(ico.icon, size: 20, color: ico.color);
                    },
                  )
                : Builder(builder: (ctx) {
                    final ico = _iconFor(ctx, ext);
                    return Icon(ico.icon, size: 20, color: ico.color);
                  }),
          ),
        ),
      ),
    );
  }
}
