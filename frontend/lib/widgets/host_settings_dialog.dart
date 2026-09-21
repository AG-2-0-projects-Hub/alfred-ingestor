import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../utils/walkthrough_prefs.dart';
import 'glass_panel.dart';

/// Account-level settings, reachable from the dashboard's top-right icon
/// row. Currently holds just the walkthrough replay toggle — moved here
/// 2026-09-19 from inside each property's own drawer, since flipping it
/// always acted account-wide (both the Settings walkthrough and the guest
/// link walkthrough) even when it visually lived per-property.
class HostSettingsDialog extends StatefulWidget {
  const HostSettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const HostSettingsDialog(),
    );
  }

  @override
  State<HostSettingsDialog> createState() => _HostSettingsDialogState();
}

class _HostSettingsDialogState extends State<HostSettingsDialog> {
  bool? _replayPending;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settingsSeen = await WalkthroughPrefs.isPostTrainingSeen();
    final guestLinkSeen = await WalkthroughPrefs.isGuestLinkWalkthroughSeen();
    if (mounted) {
      setState(() => _replayPending = !(settingsSeen && guestLinkSeen));
    }
  }

  Future<void> _toggleReplay(bool value) async {
    if (!value) {
      await WalkthroughPrefs.markPostTrainingSeen();
      await WalkthroughPrefs.markGuestLinkWalkthroughSeen();
    } else {
      await WalkthroughPrefs.resetPostTrainingWalkthrough();
      await WalkthroughPrefs.resetGuestLinkWalkthrough();
    }
    if (mounted) setState(() => _replayPending = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Dialog(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: GlassPanel(
          radius: 20,
          blurSigma: AppTheme.glassBlurSigmaHeavy,
          tint: palette.glassTintStrong,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.settings_rounded, size: 18, color: palette.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    'Settings',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: palette.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Tooltip(
                        message: 'Replays the onboarding tips shown after a property '
                            'finishes training — both the property drawer walkthrough '
                            'and the guest link walkthrough.',
                        waitDuration: const Duration(milliseconds: 300),
                        child: Text(
                          '+ Show walkthrough again',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _replayPending == null
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Switch(
                            value: _replayPending!,
                            activeThumbColor: palette.primary,
                            onChanged: _toggleReplay,
                          ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
