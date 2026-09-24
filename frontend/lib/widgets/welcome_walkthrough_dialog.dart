import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// First-login onboarding modal — shows once, the first time a host reaches
/// an empty dashboard (see dashboard_screen.dart's `_maybeShowWelcomeModal`).
/// Gated server-side by `host_profiles.welcome_modal_seen`, not
/// SharedPreferences — see migrations/2026-09-24_welcome_modal_seen.sql for
/// why (must reset correctly on account delete + recreate).
class WelcomeWalkthroughDialog extends StatelessWidget {
  const WelcomeWalkthroughDialog._();

  /// Returns 'add_property' if the host tapped the primary button, null if
  /// dismissed via "Maybe later" (never via barrier tap — this is a
  /// deliberate one-time moment, not something to lose to a stray outside
  /// click, same reasoning ProfileDialog uses).
  static Future<String?> show(BuildContext context) {
    return showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const WelcomeWalkthroughDialog._(),
    );
  }

  static const _steps = [
    (
      icon: Icons.home_work_rounded,
      title: 'Add a property',
      body: 'Paste your Airbnb listing URL — Alfred scrapes the details automatically.',
    ),
    (
      icon: Icons.upload_file_rounded,
      title: 'Upload what Alfred should know',
      body: 'House manual, WiFi photo, appliance guides, house rules — PDFs, photos, '
          'or a voice note all work.',
    ),
    (
      icon: Icons.auto_awesome_rounded,
      title: 'Train Alfred',
      body: 'Ingest, then Merge — Alfred combines your files with the listing into '
          'one knowledge base.',
    ),
    (
      icon: Icons.link_rounded,
      title: 'Share a guest link',
      body: 'Generate a link from the property card and send it to a guest.',
    ),
    (
      icon: Icons.chat_bubble_outline_rounded,
      title: 'Test it yourself',
      body: 'Open the guest link and chat with Alfred to see exactly what your '
          'guests will see.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return AlertDialog(
      backgroundColor: palette.surface,
      insetPadding: isMobile
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [palette.primary, palette.accent]),
                ),
                child: const Icon(Icons.waving_hand_rounded, size: 32, color: Colors.white),
              ),
              const SizedBox(height: 16),
              Text(
                'Welcome to Alfred',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Here's how to get your first property up and answering guests.",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: palette.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              for (final step in _steps) ...[
                _StepRow(step: step, palette: palette),
                const SizedBox(height: 14),
              ],
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop('add_property'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('ADD YOUR FIRST PROPERTY'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Maybe later'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final ({IconData icon, String title, String body}) step;
  final AppPalette palette;
  const _StepRow({required this.step, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.primary.withOpacity(0.12),
          ),
          child: Icon(step.icon, size: 18, color: palette.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                step.body,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: palette.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
