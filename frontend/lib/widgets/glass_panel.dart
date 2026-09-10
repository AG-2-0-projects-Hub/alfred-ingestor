import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A reusable glassmorphic surface: clipped, backdrop-blurred, tinted with a
/// subtle inner highlight gradient. Use [hoverable] to enable a subtle hover
/// lift + tint bump on web.
class GlassPanel extends StatefulWidget {
  final Widget child;
  final double radius;
  final double blurSigma;
  final Color? tint;
  final Color? border;
  final EdgeInsetsGeometry padding;
  final bool hoverable;
  final List<BoxShadow>? shadow;
  final VoidCallback? onTap;

  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 16,
    this.blurSigma = AppTheme.glassBlurSigma,
    this.tint,
    this.border,
    this.padding = EdgeInsets.zero,
    this.hoverable = false,
    this.shadow,
    this.onTap,
  });

  @override
  State<GlassPanel> createState() => _GlassPanelState();
}

class _GlassPanelState extends State<GlassPanel> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tint = widget.tint ?? palette.glassTint;
    final hoverTint = widget.tint == null
        ? palette.glassTintStrong
        : Color.alphaBlend(Colors.white.withValues(alpha: 0.1), widget.tint!);
    final borderColor = _hovered
        ? palette.glassBorderStrong
        : (widget.border ?? palette.glassBorder);

    final panel = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: AppTheme.standardEasing,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: _hovered && widget.hoverable ? hoverTint : tint,
        gradient: AppTheme.glassInnerHighlight,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: widget.child,
    );

    final blurred = ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
            sigmaX: widget.blurSigma, sigmaY: widget.blurSigma),
        child: panel,
      ),
    );

    // The drop shadow has to live OUTSIDE the ClipRRect above: a BoxShadow
    // painted by a clipped descendant gets cut off at the clip's own bounds
    // instead of spreading outward, which was silently killing every panel's
    // shadow — the one thing meant to visually separate these "glass" cards
    // from whatever sits behind them (a dialog, a dashboard, another card).
    final clipped = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: AppTheme.standardEasing,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        boxShadow: widget.shadow ??
            (_hovered && widget.hoverable
                ? palette.cardShadowHover
                : palette.cardShadow),
      ),
      child: blurred,
    );

    if (!widget.hoverable && widget.onTap == null) return clipped;

    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: widget.hoverable ? (_) => setState(() => _hovered = true) : null,
      onExit: widget.hoverable ? (_) => setState(() => _hovered = false) : null,
      child: widget.onTap == null
          ? clipped
          : GestureDetector(onTap: widget.onTap, child: clipped),
    );
  }
}
