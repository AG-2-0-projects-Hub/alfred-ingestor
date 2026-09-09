import 'package:shared_preferences/shared_preferences.dart';

/// Dismiss-state for the User-mode post-training walkthrough (Parts A/B/C).
/// Centralized so the key scheme can't drift between the dashboard, the
/// property drawer, and the guest-link/host-chat flow that all read/write it.
class WalkthroughPrefs {
  WalkthroughPrefs._();

  static const _postTrainingPrefix = 'post_training_walkthrough_seen_';
  static const _guestLinkKey = 'guest_link_walkthrough_seen';

  /// Parts A/B share this — per property, since each property's own training
  /// completion is what triggers it.
  static Future<bool> isPostTrainingSeen(String propertyId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_postTrainingPrefix$propertyId') ?? false;
  }

  static Future<void> markPostTrainingSeen(String propertyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_postTrainingPrefix$propertyId', true);
  }

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

  /// Part C — independent of A/B: general knowledge about how guest links
  /// work, not tied to any one property.
  static Future<bool> isGuestLinkWalkthroughSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_guestLinkKey) ?? false;
  }

  static Future<void> markGuestLinkWalkthroughSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_guestLinkKey, true);
  }
}
