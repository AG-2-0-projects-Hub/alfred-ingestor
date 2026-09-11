import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import 'glass_panel.dart';

/// Shared tip-bubble chrome for the post-training walkthrough (Settings
/// drawer, Guest Link dialog, Host Chat) — robot + step counter, optional
/// title, body, Back/Next footer. Identical visual design across all three
/// flows per walkthrough.md; [title] is nullable since the Guest Link steps
/// show only an eyebrow counter with no separate title line.
///
/// Deliberately rendered via a real Overlay entry by callers (not nested
/// inside a dialog route) — see property_detail_drawer.dart's `_wtOverlay`
/// for why.
class WalkthroughTipPanel extends StatelessWidget {
  final int stepIndex;
  final int stepCount;
  final String? title;
  final String body;
  final VoidCallback? onBack;
  final VoidCallback onNext;
  final VoidCallback onClose;
  final bool isLast;

  const WalkthroughTipPanel({
    super.key,
    required this.stepIndex,
    required this.stepCount,
    this.title,
    required this.body,
    this.onBack,
    required this.onNext,
    required this.onClose,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: Colors.transparent,
      child: GlassPanel(
        radius: 20,
        blurSigma: AppTheme.glassBlurSigmaHeavy,
        tint: palette.glassTintHeavy,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('🤖', style: GoogleFonts.inter(fontSize: 13)),
                const SizedBox(width: 5),
                Text(
                  '${stepIndex + 1} of $stepCount',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: palette.primary,
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: 'Close walkthrough',
                  child: InkWell(
                    onTap: onClose,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.close_rounded, size: 16, color: palette.textMuted),
                    ),
                  ),
                ),
              ],
            ),
            if (title != null) ...[
              const SizedBox(height: 8),
              Text(
                title!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              body,
              style: GoogleFonts.inter(fontSize: 12.5, height: 1.5, color: palette.textSecondary),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (onBack != null)
                  TextButton(onPressed: onBack, child: const Text('Back')),
                const Spacer(),
                FilledButton(
                  onPressed: onNext,
                  child: Text(isLast ? 'Done' : 'Next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
