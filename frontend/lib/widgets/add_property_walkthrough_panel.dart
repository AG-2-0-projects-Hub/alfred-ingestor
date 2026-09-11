import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import 'glass_panel.dart';

/// The 3 screens of the docked Add Property walkthrough panel. Deliberately
/// never referred to as "steps" elsewhere in the app — that word is reserved
/// for guide.html's own 1-6 step numbering, and reusing it here caused real
/// confusion between the two.
enum WalkthroughScreen { url, upload, train }

/// Shared with guide.html's Step 3 ("What trains Alfred best") — keep both in
/// sync by hand when either changes.
const kAlfredTrainingTips = [
  'Your house manual or welcome-book',
  'A photo of the WiFi router — name + password',
  'How your appliances work — thermostat, washer, coffee machine',
  'Check-in / check-out steps and house rules',
  'Parking or building access notes',
  'A voice note for anything hands-on — towels, linens, the washer, how guests get in',
];
const kAlfredTrainingTipsClosing =
    "Whatever's easiest — photo, PDF, document or just tell me in a voicenote.";

class AddPropertyWalkthroughPanel extends StatelessWidget {
  final WalkthroughScreen current;
  final ValueChanged<WalkthroughScreen> onScreenChange;
  final VoidCallback onDismiss;

  const AddPropertyWalkthroughPanel({
    super.key,
    required this.current,
    required this.onScreenChange,
    required this.onDismiss,
  });

  static const _order = [
    WalkthroughScreen.url,
    WalkthroughScreen.upload,
    WalkthroughScreen.train,
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final index = _order.indexOf(current);
    final isLast = index == _order.length - 1;

    final (title, body) = switch (current) {
      WalkthroughScreen.url => (
          'Paste your listing URL',
          'Nickname is optional, but the Airbnb URL is what I read the listing from — amenities, house rules, photos, all of it, automatically.',
        ),
      WalkthroughScreen.upload => (
          'Upload what I should know',
          null, // rendered as the shared tips list below
        ),
      WalkthroughScreen.train => (
          'Train me',
          'Tap Ingest Now to have me read everything you uploaded. Once that finishes, tap Merge Now — if anything disagrees with the listing, I\'ll ask you to confirm before I\'m done.',
        ),
    };

    return GlassPanel(
      radius: 20,
      blurSigma: AppTheme.glassBlurSigmaHeavy,
      tint: palette.glassTintHeavy,
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
                '${index + 1} of ${_order.length}',
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
                  onTap: onDismiss,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close_rounded, size: 16, color: palette.textMuted),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          if (body != null)
            SelectableText(
              body,
              style: GoogleFonts.inter(fontSize: 12.5, height: 1.5, color: palette.textSecondary),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final tip in kAlfredTrainingTips)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text('•  $tip',
                        style: GoogleFonts.inter(
                            fontSize: 12, height: 1.4, color: palette.textSecondary)),
                  ),
                Text(kAlfredTrainingTipsClosing,
                    style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: palette.textSecondary)),
              ],
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (index > 0)
                TextButton(
                  onPressed: () => onScreenChange(_order[index - 1]),
                  child: const Text('Back'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: isLast ? onDismiss : () => onScreenChange(_order[index + 1]),
                child: Text(isLast ? 'Done' : 'Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
