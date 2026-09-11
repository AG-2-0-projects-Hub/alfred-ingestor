import 'package:shared_preferences/shared_preferences.dart';

/// Dismiss-state for Part A of the post-training walkthrough (the dashboard's
/// Step 0 hint) — the only part still live. Parts B/C's own read/write
/// methods (drawer + guest-link/host-chat step panels) were removed along
/// with those panels; see walkthrough.md for what they used to do.
class WalkthroughPrefs {
  WalkthroughPrefs._();

  static const _postTrainingPrefix = 'post_training_walkthrough_seen_';

  /// All property IDs already marked seen — lets the dashboard compute which
  /// cards need Part A's hint in one pass instead of one async call per card.
  static Future<Set<String>> seenPostTrainingPropertyIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs
        .getKeys()
        .where((k) => k.startsWith(_postTrainingPrefix))
        .map((k) => k.substring(_postTrainingPrefix.length))
        .toSet();
  }
}
