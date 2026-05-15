import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A soft, bold gradient backdrop made of four blurred colour blobs over a
/// theme-aware base. Drop this in as the body of any Scaffold (with a transparent
/// scaffoldBackgroundColor) to get the "aurora" effect that sits behind
/// glassmorphic surfaces.
class AuroraBackground extends StatelessWidget {
  final Widget child;
  final double intensity;

  const AuroraBackground({
    super.key,
    required this.child,
    this.intensity = 0.50,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final p = context.palette;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: p.background),
        _Blob(
          color: p.auroraTeal,
          alignment: const Alignment(-0.9, -0.95),
          size: 720,
          opacity: intensity,
        ),
        _Blob(
          color: p.auroraSky,
          alignment: const Alignment(0.9, -0.85),
          size: 640,
          opacity: intensity * 0.85,
        ),
        _Blob(
          color: p.auroraLavender,
          alignment: const Alignment(-0.85, 0.95),
          size: 680,
          opacity: intensity * 0.7,
        ),
        _Blob(
          color: p.auroraPeach,
          alignment: const Alignment(0.95, 0.95),
          size: 560,
          opacity: intensity * 0.6,
        ),
        if (!reduceMotion)
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
            child: const SizedBox.expand(),
          ),
        child,
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final Alignment alignment;
  final double size;
  final double opacity;

  const _Blob({
    required this.color,
    required this.alignment,
    required this.size,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: opacity),
                color.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
