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

/// Shown for the duration of a Train Now run (User mode). Callers show it via
/// showDialog and pop it themselves once ingest+merge finish. It also offers
/// its own "Continue in background" exit — true mid-flight cancellation of
/// the backend job isn't safe (ingest/merge aren't designed to be aborted
/// mid-run), so this dismisses the dialog without touching the in-flight
/// request; the caller still surfaces the eventual success/error result via
/// its normal SnackBar/dialog path once the request completes, whether or
/// not this dialog is still open to see it.
class TrainingWaitDialog extends StatefulWidget {
  final VoidCallback? onRunInBackground;
  // Lets other flows (e.g. the scrape-link retry) reuse this same wait
  // experience with their own copy instead of duplicating the widget.
  final String headline;
  final String subtext;

  const TrainingWaitDialog({
    super.key,
    this.onRunInBackground,
    this.headline = 'Alfred is learning your property',
    this.subtext = 'This can take a couple of minutes for larger properties.',
  });

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
                widget.headline,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.subtext,
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
              if (widget.onRunInBackground != null) ...[
                const SizedBox(height: 14),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onRunInBackground!();
                  },
                  child: Text(
                    'Continue in background',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Route-based push/pop for this dialog (2026-09-17) -- a plain
// Navigator.pop() closes whatever route is currently on top, which stopped
// being safe once dashboard_screen.dart can independently push its own
// result dialog (training_result_dialogs.dart) on the same root navigator
// while this one is still open: a screen closing "its" wait dialog via a
// blind pop() could actually close the dashboard's dialog instead, stranding
// this one on screen. removeRoute closes exactly the route it was given,
// regardless of what else was pushed on top of it in the meantime.
const _fadeDuration = Duration(milliseconds: 200);

// Keyed by route identity so pushTrainingWaitDialog's own return type (and
// every existing `Route<void>?` field storing it) never has to change --
// this is purely an internal detail of how the close fades out.
final Map<Route<void>, ValueNotifier<bool>> _closingNotifiers = {};

Route<void> pushTrainingWaitDialog(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = false,
  Color? barrierColor,
}) {
  // Starts invisible and flips true a frame after the route is pushed, so
  // AnimatedOpacity below animates it in over _fadeDuration instead of
  // popping straight to opacity 1 on the first frame (founder feedback,
  // 2026-09-19 -- fade-out already existed, fade-in didn't).
  final visible = ValueNotifier<bool>(false);
  final closing = ValueNotifier<bool>(false);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    builder: (ctx) => ValueListenableBuilder<bool>(
      valueListenable: visible,
      builder: (_, isVisible, child) => ValueListenableBuilder<bool>(
        valueListenable: closing,
        builder: (_, isClosing, child) => AnimatedOpacity(
          opacity: (isVisible && !isClosing) ? 1 : 0,
          duration: _fadeDuration,
          child: child,
        ),
        child: child,
      ),
      child: builder(ctx),
    ),
  );
  _closingNotifiers[route] = closing;
  Navigator.of(context, rootNavigator: true).push(route);
  WidgetsBinding.instance.addPostFrameCallback((_) => visible.value = true);
  return route;
}

// No-op if [route] is null or already gone (e.g. dismissed via "Continue in
// background", or already closed by an earlier call) -- safe to call
// unconditionally in a finally/catch block. Fades the dialog out first
// instead of the instant cut removeRoute would otherwise produce (2026-09-18
// founder feedback) -- still uses removeRoute, not a plain pop, so it closes
// exactly this route regardless of what else was pushed on top meanwhile.
//
// Returns a Future that only completes once the route is actually gone.
// This route stays on the stack (mid-fade) for the ~200ms between setting
// `closing.value = true` and the delayed removeRoute below -- a caller that
// fires a blind Navigator.pop() immediately after calling this (not awaiting
// it) pops whatever is CURRENTLY topmost, which is still this fading route,
// not whatever the caller actually meant to close. Confirmed live
// (2026-09-19): this is why the scrape-link retry's wait dialog cut off
// abruptly instead of fading, AND why the drawer never closed after a
// successful retry -- the drawer's own pop() was consumed by this route
// instead. Callers that pop something else afterward must await this first.
Future<void> popTrainingWaitDialog(BuildContext context, Route<void>? route) async {
  if (route == null || !route.isActive) return;
  final closing = _closingNotifiers.remove(route);
  if (closing == null) {
    Navigator.of(context, rootNavigator: true).removeRoute(route);
    return;
  }
  closing.value = true;
  await Future.delayed(_fadeDuration);
  if (route.isActive) {
    Navigator.of(context, rootNavigator: true).removeRoute(route);
  }
}
