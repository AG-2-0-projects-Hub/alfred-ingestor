import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import 'glass_panel.dart';

// Shared "training finished" result popups -- extracted from
// add_property_screen.dart (2026-09-17) so any flow that can finish a
// training/merge cycle (not just first-time property creation) can show the
// same result, from whichever screen is on top. useRootNavigator: true so
// these always render above an open drawer or EditPropertyScreen, regardless
// of who calls them.

Future<void> showTrainedResultDialog(
  BuildContext context,
  String propertyName, {
  String? caveat,
  // Called after the dialog closes -- add_property_screen.dart uses this to
  // also pop itself back to the dashboard; callers already sitting on the
  // dashboard (dashboard_screen.dart) can leave this null.
  VoidCallback? onDismiss,
}) async {
  await showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.65),
    builder: (ctx) => Dialog(
      // Opaque surface backing for the dialog. GlassPanel paints a translucent
      // highlight gradient that overrides its own solid `tint`, so a fully
      // transparent dialog let the dimmed barrier bleed through and crushed
      // text contrast. Backing it with the solid surface keeps the soft glass
      // sheen on top while staying readable.
      backgroundColor: context.palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: GlassPanel(
          radius: 24,
          blurSigma: AppTheme.glassBlurSigmaHeavy,
          // Light sheen over the opaque dialog backing above (see Dialog).
          tint: context.palette.glassTintStrong,
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [context.palette.primary, context.palette.accent],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: context.palette.primary.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(Icons.check_rounded,
                    color: Colors.white, size: 34),
              ),
              const SizedBox(height: 18),
              Text(
                propertyName.isNotEmpty ? propertyName : 'Property Ready',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w300,
                    color: context.palette.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Alfred is now trained and ready to take over conversations.',
                style: GoogleFonts.inter(
                    fontSize: 15,
                    height: 1.5,
                    color: context.palette.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'He’ll respond on autopilot to incoming guest messages. You can review or intervene anytime from the Dashboard.',
                style: GoogleFonts.inter(
                    fontSize: 13,
                    color: context.palette.textSecondary,
                    height: 1.5),
                textAlign: TextAlign.center,
              ),
              if (caveat != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.palette.warningContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    caveat,
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: context.palette.warning,
                        height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Center(
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    onDismiss?.call();
                  },
                  child: const Text('Back to Dashboard'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> showConflictResultDialog(
  BuildContext context,
  int conflictCount,
  String propertyName, {
  // Called after the dialog closes -- dashboard_screen.dart uses this to open
  // the property's drawer so the host lands straight on the resolution flow;
  // add_property_screen.dart already renders the questionnaire inline on the
  // same screen, so it leaves this null.
  VoidCallback? onResolve,
}) async {
  await showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.65),
    builder: (ctx) => Dialog(
      // Opaque surface backing for the dialog. GlassPanel paints a translucent
      // highlight gradient that overrides its own solid `tint`, so a fully
      // transparent dialog let the dimmed barrier bleed through and crushed
      // text contrast. Backing it with the solid surface keeps the soft glass
      // sheen on top while staying readable.
      backgroundColor: context.palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: GlassPanel(
          radius: 24,
          blurSigma: AppTheme.glassBlurSigmaHeavy,
          // Light sheen over the opaque dialog backing above (see Dialog).
          tint: context.palette.glassTintStrong,
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.palette.warningContainer,
                  boxShadow: [
                    BoxShadow(
                      color: context.palette.warning.withValues(alpha: 0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(Icons.tune_rounded,
                    color: context.palette.warning, size: 32),
              ),
              const SizedBox(height: 18),
              Text(
                propertyName.isNotEmpty ? propertyName : 'Property Ready',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w300,
                    color: context.palette.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              // Design approved via artifact (2026-09-19): title becomes the
              // property name, matching showTrainedResultDialog's format; the
              // conflict count moves into this pill instead of crowding the
              // title.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: context.palette.warningContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$conflictCount ${conflictCount == 1 ? 'conflict' : 'conflicts'} found',
                  style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: context.palette.warning),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Alfred merged your information but found $conflictCount ${conflictCount == 1 ? 'point' : 'points'} where your listing and uploaded documents disagree. Review each one and choose the version Alfred should use.',
                style: GoogleFonts.inter(
                    fontSize: 13,
                    color: context.palette.textSecondary,
                    height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Center(
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    onResolve?.call();
                  },
                  child: const Text('Resolve Conflicts'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
