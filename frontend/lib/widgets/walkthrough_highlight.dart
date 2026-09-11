import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The purple highlight that outlines whichever real UI element a
/// walkthrough step is pointing at. Steady 2px border plus a soft glow that
/// pulses continuously while active — matches the approved design artifact's
/// `.hl` CSS class (`box-shadow: 0 0 0 4px → 7px`, 12% → 22% alpha, 1.6s
/// ease-in-out, infinite). The border itself doesn't pulse, only the glow.
class WalkthroughHighlight extends StatefulWidget {
  final bool active;
  final Widget child;
  final double borderRadius;

  const WalkthroughHighlight({
    super.key,
    required this.active,
    required this.child,
    this.borderRadius = 14,
  });

  @override
  State<WalkthroughHighlight> createState() => _WalkthroughHighlightState();
}

class _WalkthroughHighlightState extends State<WalkthroughHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(
          color: widget.active ? palette.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: !widget.active
          ? widget.child
          : AnimatedBuilder(
              animation: _pulse,
              builder: (_, child) {
                final t = Curves.easeInOut.transform(_pulse.value);
                final spread = 4 + (t * 3); // 4px → 7px, matches the artifact
                final alpha = 0.12 + (t * 0.10); // 12% → 22%
                return DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    boxShadow: [
                      BoxShadow(
                        color: palette.primary.withValues(alpha: alpha),
                        spreadRadius: spread,
                      ),
                    ],
                  ),
                  child: child,
                );
              },
              child: widget.child,
            ),
    );
  }
}
