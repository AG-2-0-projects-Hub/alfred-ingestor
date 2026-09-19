import 'package:shared_preferences/shared_preferences.dart';

/// Dismiss-state for the post-training walkthrough. A single account-wide
/// flag (changed 2026-09-19 — was per-property) since it's an onboarding
/// explainer for the Settings drawer's own controls, not knowledge tied to
/// any one property; a host training a 2nd/3rd property shouldn't see it
/// repeat. Part A (dashboard's Step 0 hint) reads the same flag Part B
/// (Settings drawer) writes — see walkthrough.md for the full map.
class WalkthroughPrefs {
  WalkthroughPrefs._();

  static const _postTrainingKey = 'post_training_walkthrough_seen';

  static Future<bool> isPostTrainingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_postTrainingKey) ?? false;
  }

  static Future<void> markPostTrainingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_postTrainingKey, true);
  }

  static Future<void> resetPostTrainingWalkthrough() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_postTrainingKey);
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
