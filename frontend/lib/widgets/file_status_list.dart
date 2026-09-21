import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class FileStatusList extends StatelessWidget {
  final List<Map<String, String>> statuses;

  /// Optional per-row remove action, keyed by index into [statuses]. Null
  /// (the default) renders no remove button, matching every existing
  /// consumer of this widget — only the pre-Train-Now queue in
  /// add_property_screen.dart opts in. Previously there was no way to drop a
  /// file from the queue at all, not even an accidentally-dropped one.
  final void Function(int index)? onRemove;

  const FileStatusList({super.key, required this.statuses, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < statuses.length; i++)
          _FileStatusRow(
            filename: statuses[i]['file'] ?? '',
            status: statuses[i]['status'] ?? '',
            message: statuses[i]['message'] ?? '',
            onRemove: onRemove == null ? null : () => onRemove!(i),
          ),
      ],
    );
  }
}

class _FileStatusRow extends StatelessWidget {
  final String filename;
  final String status;
  final String message;
  final VoidCallback? onRemove;

  const _FileStatusRow({
    required this.filename,
    required this.status,
    this.message = '',
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusIcon(status: status),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  filename,
                  style: GoogleFonts.inter(
                      fontSize: 13, color: palette.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _StatusLabel(status: status),
              if (onRemove != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  tooltip: 'Remove',
                  color: palette.textMuted,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  onPressed: onRemove,
                ),
              ],
            ],
          ),
          if ((status == 'error' || status == 'timeout' || status == 'processing') &&
              message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 4),
              child: Text(
                message,
                style: GoogleFonts.inter(
                    fontSize: 11,
                    // 'processing' with a message is a benign "Retrying
                    // (attempt N)…" note (backend auto-retry, still working —
                    // see ingest_files.attempts), not a failure — only
                    // error/timeout get the alarming danger color.
                    color: status == 'processing'
                        ? palette.textMuted
                        : palette.danger),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final String status;
  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    switch (status) {
      case 'queued':
        return Icon(Icons.hourglass_empty_rounded,
            size: 18, color: palette.textMuted);
      case 'processing':
        return SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: palette.accent),
        );
      case 'done':
        return Icon(Icons.check_circle_rounded,
            size: 18, color: palette.success);
      case 'already_in_db':
        return Icon(Icons.storage_rounded,
            size: 18, color: palette.textSecondary);
      case 'file_updated':
        return Icon(Icons.update_rounded,
            size: 18, color: palette.accent);
      case 'skipped':
        return Icon(Icons.skip_next_rounded,
            size: 18, color: palette.warning);
      case 'error':
        return Icon(Icons.error_rounded,
            size: 18, color: palette.danger);
      case 'timeout':
        return Icon(Icons.timer_off_rounded,
            size: 18, color: palette.warning);
      default:
        return const SizedBox(width: 18);
    }
  }
}

class _StatusLabel extends StatelessWidget {
  final String status;
  const _StatusLabel({required this.status});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (label, color) = switch (status) {
      'queued' => ('Queued', palette.textMuted),
      'processing' => ('Processing…', palette.accent),
      'done' => ('Done', palette.success),
      'already_in_db' => ('Already in database', palette.textSecondary),
      'file_updated' => ('File updated in database', palette.accent),
      'skipped' => ('Skipped', palette.warning),
      'error' => ('Error', palette.danger),
      'timeout' => ('Timeout — try again', palette.warning),
      _ => (status, palette.textMuted),
    };
    return Text(label,
        style: GoogleFonts.inter(
            fontSize: 12, color: color, fontWeight: FontWeight.w500));
  }
}
