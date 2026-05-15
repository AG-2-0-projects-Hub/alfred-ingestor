import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SetupStep {
  final String headline;
  final String subtext;
  final String actionLabel;
  final IconData icon;
  final Color Function(BuildContext) accent;
  final bool isProcessing;
  const SetupStep({
    required this.headline,
    required this.subtext,
    required this.actionLabel,
    required this.icon,
    required this.accent,
    this.isProcessing = false,
  });
}

SetupStep? nextStepFor(String status, {bool hasIngestedFiles = false}) {
  switch (status) {
    case 'Scraped':
      return SetupStep(
        headline: 'Add property files to train Alfred',
        subtext: 'Upload PDFs, photos, voice notes — anything Alfred should know.',
        actionLabel: 'Continue Setup',
        icon: Icons.upload_file_rounded,
        accent: (ctx) => Theme.of(ctx).colorScheme.primary,
      );
    case 'Ingesting':
    case 'Training':
      return SetupStep(
        headline: 'Processing files…',
        subtext: 'Alfred is reading your files. This usually takes 30–60 seconds.',
        actionLabel: '',
        icon: Icons.hourglass_top_rounded,
        accent: (ctx) => Theme.of(ctx).colorScheme.secondary,
        isProcessing: true,
      );
    case 'Ingested':
      return SetupStep(
        headline: 'Build the master profile',
        subtext: 'Merge the file data into one profile so Alfred can use it.',
        actionLabel: 'Merge Now',
        icon: Icons.merge_rounded,
        accent: (ctx) => Theme.of(ctx).colorScheme.primary,
      );
    case 'Conflict_Pending':
      return SetupStep(
        headline: 'Resolve conflicts to continue',
        subtext: 'A few details disagree between your files. Pick the right answers.',
        actionLabel: 'Resolve',
        icon: Icons.warning_amber_rounded,
        accent: (ctx) => ctx.palette.warning,
      );
    case 'Merged':
      return SetupStep(
        headline: 'Train Alfred to enable AI replies',
        subtext: 'Final step — Alfred learns your property and starts answering guests.',
        actionLabel: 'Train Alfred',
        icon: Icons.auto_awesome_rounded,
        accent: (ctx) => Theme.of(ctx).colorScheme.primary,
      );
    default:
      return null;
  }
}
