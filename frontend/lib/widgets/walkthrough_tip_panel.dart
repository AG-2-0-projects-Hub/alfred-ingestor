import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import 'glass_panel.dart';

/// Which edge of the tip panel the pointer tail is cut into — the side
/// nearest the element the panel is docked next to.
enum WalkthroughPointerSide { left, right, top }

/// Rounded-rect body with a triangular tail cut into one edge, drawn as one
/// continuous Path so there is no seam between a separate tail shape and the
/// panel (the earlier two-piece version always showed one). The body is
/// inset from the pointer-side edge by [_tailReach]; the tail's tip reaches
/// out to the panel's actual edge, same distance from the target as an
/// arrow-less panel would sit. [pointerCenter] is measured along the
/// pointer edge from its start (top-to-bottom for left/right, left-to-right
/// for top).
class WalkthroughPointerClipper extends CustomClipper<Path> {
  final double radius;
  final WalkthroughPointerSide side;
  final double pointerCenter;

  static const double _tailReach = 12;
  static const double _tailBase = 18;

  const WalkthroughPointerClipper({
    required this.radius,
    required this.side,
    required this.pointerCenter,
  });

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final top = side == WalkthroughPointerSide.top ? _tailReach : 0.0;
    final left = side == WalkthroughPointerSide.left ? _tailReach : 0.0;
    final right = side == WalkthroughPointerSide.right ? w - _tailReach : w;

    final path = Path()..moveTo(left + radius, top);

    if (side == WalkthroughPointerSide.top) {
      final cx = pointerCenter.clamp(0.0, w);
      final tipStart = (cx - _tailBase / 2).clamp(left + radius, right - radius);
      final tipEnd = (cx + _tailBase / 2).clamp(left + radius, right - radius);
      path
        ..lineTo(tipStart, top)
        ..lineTo(cx, 0)
        ..lineTo(tipEnd, top);
    }
    path.lineTo(right - radius, top);
    path.arcToPoint(Offset(right, top + radius), radius: Radius.circular(radius));

    if (side == WalkthroughPointerSide.right) {
      final cy = pointerCenter.clamp(top, h);
      final tipStart = (cy - _tailBase / 2).clamp(top + radius, h - radius);
      final tipEnd = (cy + _tailBase / 2).clamp(top + radius, h - radius);
      path
        ..lineTo(right, tipStart)
        ..lineTo(w, cy)
        ..lineTo(right, tipEnd);
    }
    path.lineTo(right, h - radius);
    path.arcToPoint(Offset(right - radius, h), radius: Radius.circular(radius));
    path.lineTo(left + radius, h);
    path.arcToPoint(Offset(left, h - radius), radius: Radius.circular(radius));

    if (side == WalkthroughPointerSide.left) {
      final cy = pointerCenter.clamp(top, h);
      final tipStart = (cy - _tailBase / 2).clamp(top + radius, h - radius);
      final tipEnd = (cy + _tailBase / 2).clamp(top + radius, h - radius);
      path
        ..lineTo(left, tipEnd)
        ..lineTo(0, cy)
        ..lineTo(left, tipStart);
    }
    path.lineTo(left, top + radius);
    path.arcToPoint(Offset(left + radius, top), radius: Radius.circular(radius));
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant WalkthroughPointerClipper oldClipper) =>
      oldClipper.side != side ||
      oldClipper.pointerCenter != pointerCenter ||
      oldClipper.radius != radius;
}

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
  final InlineSpan body;
  final VoidCallback? onBack;
  final VoidCallback onNext;
  final VoidCallback onClose;
  final bool isLast;
  /// Which edge gets a pointer tail, and where along it (distance from the
  /// panel's top, in logical px). Null (the default) renders a plain
  /// rounded-rect panel with no tail — used where the panel isn't docked
  /// next to one single element.
  final WalkthroughPointerSide? pointerSide;
  final double pointerCenter;

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
    this.pointerSide,
    this.pointerCenter = 28,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Soft white glow behind the panel — a tighter "lit from within" halo
    // plus a broader spotlight — so it reads as the foreground element
    // against the dialog's dark scrim instead of blending into it. Kept
    // subtle per founder feedback (an earlier, more pronounced version was
    // compared side by side in an artifact and rejected in favor of this).
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.white.withValues(alpha: 0.30), blurRadius: 18),
          BoxShadow(color: Colors.white.withValues(alpha: 0.14), blurRadius: 40, spreadRadius: 8),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: GlassPanel(
          radius: 20,
          blurSigma: AppTheme.glassBlurSigmaHeavy,
          tint: palette.glassTintHeavy,
          // The plain BoxDecoration border can't follow the tail's outline
          // (it only ever draws around the panel's own rounded rect), so it
          // would show a broken stub at the tail — hidden here rather than
          // shipping that seam; the halo shadow still carries definition.
          border: pointerSide != null ? Colors.transparent : null,
          clipper: pointerSide != null
              ? WalkthroughPointerClipper(
                  radius: 20, side: pointerSide!, pointerCenter: pointerCenter)
              : null,
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
              Text.rich(
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
      ),
    );
  }
}
