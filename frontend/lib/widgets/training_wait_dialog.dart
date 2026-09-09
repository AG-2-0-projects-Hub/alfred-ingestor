import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import 'glass_panel.dart';

const _factRotateInterval = Duration(seconds: 8);

// Real Alfred capabilities (verifiable from this codebase) plus widely-known,
// non-fabricated hosting guidance — no invented statistics. Shown while Train
// Now runs (can take 1-3+ minutes for a multi-file property) so the wait
// reads as "Alfred is working" rather than a frozen screen.
const List<String> trainingWaitFacts = [
  "Superhost status rewards fast, reliable guest replies — Alfred answers in seconds, any time of day, so a quick response never depends on you being awake.",
  "The questions guests ask most are the ones hosts forget to mention — WiFi password, check-in steps, parking. Alfred pulls these straight from what you upload.",
  "Alfred reads photos, not just text — it inspects your listing and uploaded photos to describe rooms and amenities more accurately.",
  "When your Airbnb listing and your own documents disagree, Alfred flags the conflict instead of guessing. You decide which version is right.",
  "Once trained, Alfred is ready on WhatsApp, Telegram, and web chat — no retraining per channel.",
  "If a guest asks something Alfred can't confidently answer, it escalates straight to you instead of making something up.",
  "Voice notes count as training too — a quick note about a quirky lock or a temperamental AC unit becomes part of what Alfred knows.",
  "The more documents and photos you upload now, the fewer late-night \"how does the AC work?\" messages later.",
];

/// Shown for the duration of a Train Now run (User mode). Purely visual —
/// callers show it via showDialog and pop it themselves once ingest+merge
/// finish; it has no close button and never dismisses itself.
class TrainingWaitDialog extends StatefulWidget {
  const TrainingWaitDialog({super.key});

  @override
  State<TrainingWaitDialog> createState() => _TrainingWaitDialogState();
}

class _TrainingWaitDialogState extends State<TrainingWaitDialog> {
  int _factIndex = 0;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_factRotateInterval, (_) {
      if (!mounted) return;
      setState(() => _factIndex = (_factIndex + 1) % trainingWaitFacts.length);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Dialog(
      // Opaque surface backing — see the identical comment on the Ingested
      // dialog this mirrors (GlassPanel's own tint isn't opaque on its own).
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassPanel(
          radius: 24,
          blurSigma: AppTheme.glassBlurSigmaHeavy,
          tint: palette.glassTintStrong,
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🤖', style: GoogleFonts.inter(fontSize: 34)),
              const SizedBox(height: 14),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: 16),
              Text(
                'Alfred is learning your property',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'This can take a couple of minutes for larger properties.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 12, color: palette.textMuted),
              ),
              const SizedBox(height: 22),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Container(
                  key: ValueKey(_factIndex),
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: palette.surfaceAlt,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DID YOU KNOW',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: palette.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        trainingWaitFacts[_factIndex],
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          height: 1.5,
                          color: palette.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
