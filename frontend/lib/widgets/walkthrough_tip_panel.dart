import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Which edge of the panel a [WalkthroughTipPanel] draws its connector notch
/// on, pointing back toward the real UI element the step describes.
enum WalkthroughPointer { none, up, down, left, right }

/// Shared tip-bubble chrome for the post-training walkthrough (dashboard Step
/// 0, Settings drawer, Guest Link dialog, Host Chat) — robot + step counter,
/// optional title, body, Back/Next footer. Identical visual design across all
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
  final WalkthroughPointer pointer;
  final double pointerOffset;

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
    this.pointer = WalkthroughPointer.none,
    this.pointerOffset = 28,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return WalkthroughBubble(
      radius: 20,
      pointer: pointer,
      pointerOffset: pointerOffset,
      contentPadding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
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
              if (onBack != null) TextButton(onPressed: onBack, child: const Text('Back')),
              const Spacer(),
              FilledButton(
                onPressed: onNext,
                child: Text(isLast ? 'Done' : 'Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Backlit-glass surface with an optional connector notch, used by every
/// walkthrough tip panel (this file's [WalkthroughTipPanel] and
/// property_card.dart's `_Step0Tip`).
///
/// Two things this deliberately does NOT do the way `glass_panel.dart`'s
/// `GlassPanel` does:
///
/// 1. It never sets `color` and `gradient` on the same `BoxDecoration`.
///    Flutter drops `color` outright whenever `gradient` is also set on a
///    BoxDecoration — they don't blend, the gradient just wins — so
///    `GlassPanel`'s single-container `color: tint, gradient:
///    glassInnerHighlight` has never actually painted its tint on ANY
///    GlassPanel in the app, walkthrough or not; only the faint highlight
///    gradient (~19% alpha fading to 0) has ever been visible. Confirmed
///    2026-09-14 against Flutter's own documented BoxDecoration paint order.
///    This widget puts the backing tint and the highlight gradient in two
///    separate layers so both actually render. (GlassPanel itself is left
///    alone here — this bug likely affects it everywhere it's used, not just
///    in walkthrough panels, which makes fixing it a separate, larger,
///    all-of-GlassPanel's-callers change outside this ticket's scope.)
/// 2. The connector notch is cut into the SAME outline as the panel body —
///    one path, one blur/tint/gradient/border pass — instead of a separate
///    triangle widget stacked on top and color-matched by hand. Two stacked
///    pieces always left a visible seam no amount of color-matching fixed;
///    a single path can't have one.
class WalkthroughBubble extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry contentPadding;
  final WalkthroughPointer pointer;
  final double pointerOffset;

  const WalkthroughBubble({
    super.key,
    required this.child,
    this.radius = 16,
    this.contentPadding = EdgeInsets.zero,
    this.pointer = WalkthroughPointer.none,
    this.pointerOffset = 28,
  });

  static const double _notchDepth = 13;
  static const double _notchWidth = 22;
  static const double _blurSigma = AppTheme.glassBlurSigmaHeavy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final notchMargin = switch (pointer) {
      WalkthroughPointer.up => const EdgeInsets.only(top: _notchDepth),
      WalkthroughPointer.down => const EdgeInsets.only(bottom: _notchDepth),
      WalkthroughPointer.left => const EdgeInsets.only(left: _notchDepth),
      WalkthroughPointer.right => const EdgeInsets.only(right: _notchDepth),
      WalkthroughPointer.none => EdgeInsets.zero,
    };
    final clipper = _BubbleClipper(
      radius: radius,
      pointer: pointer,
      pointerOffset: pointerOffset,
      notchDepth: _notchDepth,
      notchWidth: _notchWidth,
    );

    return Container(
      // Dark lift shadow (grounds the panel against the page) plus a soft
      // backlight glow, kept gentle per founder feedback 2026-09-14 — a
      // first pass at a strong outward glow "called attention to itself"
      // rather than reading as a simple, quiet light source behind glass.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 6)),
          BoxShadow(color: Colors.white.withValues(alpha: 0.20), blurRadius: 26, spreadRadius: 2),
        ],
      ),
      child: ClipPath(
        clipper: clipper,
        child: Stack(
          children: [
            // Layer 1: blur whatever's actually behind the panel.
            Positioned.fill(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma), child: const SizedBox.expand())),
            // Layer 2: the real backing tint — its own container, `color`
            // only, so it actually paints (see class doc).
            Positioned.fill(child: ColoredBox(color: palette.glassTintHeavy)),
            // Layer 3: the highlight sheen — its own container, `gradient`
            // only, so it also actually paints.
            const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: AppTheme.glassInnerHighlight))),
            // Layer 4: one continuous border stroke along the exact same
            // path as the clip — panel and notch share one outline.
            Positioned.fill(
              child: CustomPaint(painter: _BubbleStrokePainter(clipper: clipper, color: palette.glassBorderStrong)),
            ),
            Padding(padding: notchMargin.add(contentPadding), child: child),
          ],
        ),
      ),
    );
  }
}

Path _bubblePath({
  required Size size,
  required double radius,
  required WalkthroughPointer pointer,
  required double pointerOffset,
  required double notchDepth,
  required double notchWidth,
}) {
  double left = 0, top = 0, right = size.width, bottom = size.height;
  switch (pointer) {
    case WalkthroughPointer.up:
      top = notchDepth;
      break;
    case WalkthroughPointer.down:
      bottom = size.height - notchDepth;
      break;
    case WalkthroughPointer.left:
      left = notchDepth;
      break;
    case WalkthroughPointer.right:
      right = size.width - notchDepth;
      break;
    case WalkthroughPointer.none:
      break;
  }
  final r = Radius.circular(radius);
  final path = Path()..moveTo(left + radius, top);

  // Top edge (left → right), with the notch cut in if pointer == up.
  if (pointer == WalkthroughPointer.up) {
    path.lineTo(left + pointerOffset, top);
    path.lineTo(left + pointerOffset + notchWidth / 2, 0);
    path.lineTo(left + pointerOffset + notchWidth, top);
  }
  path.lineTo(right - radius, top);
  path.arcToPoint(Offset(right, top + radius), radius: r, clockwise: true);

  // Right edge (top → bottom), notch if pointer == right.
  if (pointer == WalkthroughPointer.right) {
    path.lineTo(right, top + pointerOffset);
    path.lineTo(size.width, top + pointerOffset + notchWidth / 2);
    path.lineTo(right, top + pointerOffset + notchWidth);
  }
  path.lineTo(right, bottom - radius);
  path.arcToPoint(Offset(right - radius, bottom), radius: r, clockwise: true);

  // Bottom edge (right → left), notch if pointer == down.
  if (pointer == WalkthroughPointer.down) {
    path.lineTo(left + pointerOffset + notchWidth, bottom);
    path.lineTo(left + pointerOffset + notchWidth / 2, size.height);
    path.lineTo(left + pointerOffset, bottom);
  }
  path.lineTo(left + radius, bottom);
  path.arcToPoint(Offset(left, bottom - radius), radius: r, clockwise: true);

  // Left edge (bottom → top), notch if pointer == left.
  if (pointer == WalkthroughPointer.left) {
    path.lineTo(left, top + pointerOffset + notchWidth);
    path.lineTo(0, top + pointerOffset + notchWidth / 2);
    path.lineTo(left, top + pointerOffset);
  }
  path.lineTo(left, top + radius);
  path.arcToPoint(Offset(left + radius, top), radius: r, clockwise: true);
  path.close();
  return path;
}

class _BubbleClipper extends CustomClipper<Path> {
  final double radius;
  final WalkthroughPointer pointer;
  final double pointerOffset;
  final double notchDepth;
  final double notchWidth;

  _BubbleClipper({
    required this.radius,
    required this.pointer,
    required this.pointerOffset,
    required this.notchDepth,
    required this.notchWidth,
  });

  @override
  Path getClip(Size size) => _bubblePath(
        size: size,
        radius: radius,
        pointer: pointer,
        pointerOffset: pointerOffset,
        notchDepth: notchDepth,
        notchWidth: notchWidth,
      );

  @override
  bool shouldReclip(covariant _BubbleClipper oldClipper) =>
      oldClipper.radius != radius ||
      oldClipper.pointer != pointer ||
      oldClipper.pointerOffset != pointerOffset ||
      oldClipper.notchDepth != notchDepth ||
      oldClipper.notchWidth != notchWidth;
}

/// Strokes the exact same path [_BubbleClipper] clips to, so the border
/// never drifts from the fill/blur edge by even a pixel.
class _BubbleStrokePainter extends CustomPainter {
  final _BubbleClipper clipper;
  final Color color;
  _BubbleStrokePainter({required this.clipper, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      clipper.getClip(size),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _BubbleStrokePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.clipper.shouldReclip(clipper);
}
