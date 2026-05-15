import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../utils/setup_status.dart';

class SetupStatusBanner extends StatelessWidget {
  final SetupStep step;
  final VoidCallback? onAction;
  final bool compact;
  const SetupStatusBanner({
    super.key,
    required this.step,
    this.onAction,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = step.accent(context);
    return Container(
      margin: EdgeInsets.symmetric(horizontal: compact ? 0 : 16, vertical: compact ? 4 : 12),
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(step.icon, size: 18, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  step.headline,
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: context.palette.textPrimary,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 2),
                  Text(
                    step.subtext,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: context.palette.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (step.isProcessing) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent),
            ),
          ] else if (step.actionLabel.isNotEmpty && onAction != null) ...[
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              child: Text(step.actionLabel),
            ),
          ],
        ],
      ),
    );
  }
}
