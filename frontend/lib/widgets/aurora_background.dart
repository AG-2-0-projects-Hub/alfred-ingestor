import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A soft, bold gradient backdrop made of four blurred colour blobs over a
/// theme-aware base. Drop this in as the body of any Scaffold (with a transparent
/// scaffoldBackgroundColor) to get the "aurora" effect that sits behind
/// glassmorphic surfaces.
class AuroraBackground extends StatelessWidget {
  final Widget child;
  // Multiplier on the palette's baked-in blob alpha. 1.0 renders the palette
  // colors faithfully; <1.0 dims the aurora globally (useful on busy screens).
  final double intensity;

  const AuroraBackground({
    super.key,
    required this.child,
    this.intensity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final screenW = MediaQuery.of(context).size.width;
    // Mobile: lighter blur + dimmer aurora so mid-tier devices stay smooth.
    final isMobile = screenW < 600;
    final blurSigma = isMobile ? 30.0 : 60.0;
    final blobIntensity = intensity * (isMobile ? 0.75 : 1.0);
    final p = context.palette;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: p.background),
        // Ethereal amethyst — top-left dominant blob.
        _Blob(
          color: p.auroraTeal,
          alignment: const Alignment(-0.9, -0.95),
          size: 720,
          intensity: blobIntensity,
        ),
        // Vapor blue — top-right.
        _Blob(
          color: p.auroraSky,
          alignment: const Alignment(0.9, -0.85),
          size: 640,
          intensity: blobIntensity,
        ),
        // Bioluminescent mint — bottom-left, smaller accent only.
        _Blob(
          color: p.auroraLavender,
          alignment: const Alignment(-0.85, 0.95),
          size: 420,
          intensity: blobIntensity,
        ),
        // Deep amethyst — bottom-right anchor.
        _Blob(
          color: p.auroraPeach,
          alignment: const Alignment(0.95, 0.95),
          size: 600,
          intensity: blobIntensity,
        ),
        if (!reduceMotion)
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
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
  final double intensity;

  const _Blob({
    required this.color,
    required this.alignment,
    required this.size,
    required this.intensity,
  });

  @override
  Widget build(BuildContext context) {
    // Respect the baked-in alpha from the palette so each blob renders at
    // its theme-specified opacity. The intensity multiplier scales them
    // globally (e.g. to mute the aurora on busy screens).
    final baseAlpha = color.a;
    final alpha = (baseAlpha * intensity).clamp(0.0, 1.0);
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
                color.withValues(alpha: alpha),
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
