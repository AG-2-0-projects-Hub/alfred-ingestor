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

// Statuses where training already finished — matches the walkthrough's own
// _wtReadyStatuses in property_detail_drawer.dart.
const _trainedStatuses = {'Trained', 'Active', 'Resolved', 'Merged'};

SetupStep? nextStepFor(
  String status, {
  bool hasIngestedFiles = false,
  bool hasMasterJson = false,
  bool hasQueuedFiles = false,
  // Non-dev hosts must only ever see "Train"/"Retrain"/"Resolve" — never the
  // raw internal pipeline words (Ingest/Merge). Dev keeps the literal stage
  // names since those map directly to the separate manual buttons it shows.
  bool isDev = false,
}) {
  // A file dropped into an already-trained property's "Add New Files" only
  // uploads to storage — nothing else in this switch below covers a
  // post-training status, so without this branch the file sat at "Queued"
  // forever with no way to trigger the retrain that would pick it up.
  if (hasQueuedFiles && _trainedStatuses.contains(status)) {
    return SetupStep(
      headline: 'New files added',
      subtext: "Update Alfred so it learns what you just uploaded.",
      actionLabel: isDev ? 'Update Training' : 'Retrain',
      icon: Icons.sync_rounded,
      accent: (ctx) => Theme.of(ctx).colorScheme.primary,
    );
  }
  switch (status) {
    case 'Scraped':
      return SetupStep(
        headline: 'Add property files to train Alfred',
        subtext: 'Upload PDFs, photos, voice notes — anything Alfred should know.',
        actionLabel: isDev ? 'Continue Setup' : 'Train Now',
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
      // Non-dev: this is a transient mid-chain state now (edit_property_screen
      // auto-merges right after a successful ingest) — show it as still
      // processing rather than as a separate actionable "Merge Now" step.
      if (!isDev) {
        return SetupStep(
          headline: 'Training Alfred…',
          subtext: 'Building the master profile. This usually takes a moment.',
          actionLabel: '',
          icon: Icons.hourglass_top_rounded,
          accent: (ctx) => Theme.of(ctx).colorScheme.secondary,
          isProcessing: true,
        );
      }
      return SetupStep(
        headline: 'Build the master profile',
        subtext: 'Merge the file data into one profile so Alfred can use it.',
        actionLabel: 'Merge Now',
        icon: Icons.merge_rounded,
        accent: (ctx) => Theme.of(ctx).colorScheme.primary,
      );
    case 'Ingest_Error':
      return SetupStep(
        headline: "Some files didn't finish processing",
        subtext: 'Alfred hit a snag partway through — files that already '
            'succeeded are saved. Retry to pick up the rest.',
        actionLabel: 'Retry',
        icon: Icons.refresh_rounded,
        accent: (ctx) => ctx.palette.warning,
      );
    case 'Conflict_Pending':
      return SetupStep(
        headline: 'Some details need your review',
        subtext: 'A few items disagree between your files. Pick the right answers.',
        actionLabel: 'Resolve',
        icon: Icons.warning_amber_rounded,
        accent: (ctx) => ctx.palette.warning,
      );
    case 'Merged':
      if (hasMasterJson) return null;
      // Non-dev shouldn't reach this state at all (Ingested auto-chains
      // straight through merge), but keep a safe, on-vocabulary fallback.
      return SetupStep(
        headline: 'Train Alfred to enable AI replies',
        subtext: 'Final step — Alfred learns your property and starts answering guests.',
        actionLabel: isDev ? 'Train Alfred' : 'Train Now',
        icon: Icons.auto_awesome_rounded,
        accent: (ctx) => Theme.of(ctx).colorScheme.primary,
      );
    default:
      return null;
  }
}
