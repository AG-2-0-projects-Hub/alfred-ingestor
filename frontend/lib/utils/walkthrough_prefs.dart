import 'package:shared_preferences/shared_preferences.dart';

/// Dismiss-state for the post-training walkthrough. Part A (dashboard's Step
/// 0 hint) reads the same "seen" flag Part B (Settings drawer) writes, via
/// [seenPostTrainingPropertyIds] — see walkthrough.md for the full map.
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

  static Future<bool> isPostTrainingSeen(String propertyId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_postTrainingPrefix$propertyId') ?? false;
  }

  static Future<void> markPostTrainingSeen(String propertyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_postTrainingPrefix$propertyId', true);
  }

  static Future<void> resetPostTrainingWalkthrough(String propertyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_postTrainingPrefix$propertyId');
  }

  // Part C (Guest Link dialog + Host Chat, 9 combined steps) — a single
  // global flag, not per-property, since it only ever needs to run once for
  // a host regardless of how many properties they manage. Only ever written
  // from chat_live_dialog.dart, where the sequence actually ends.
  static const _guestLinkWalkthroughKey = 'guest_link_walkthrough_seen';

  static Future<bool> isGuestLinkWalkthroughSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_guestLinkWalkthroughKey) ?? false;
  }

  static Future<void> markGuestLinkWalkthroughSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_guestLinkWalkthroughKey, true);
  }

  static Future<void> resetGuestLinkWalkthrough() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_guestLinkWalkthroughKey);
  }
}
