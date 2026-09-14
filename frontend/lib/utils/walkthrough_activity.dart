import 'package:flutter/foundation.dart';

/// Whether any post-training walkthrough (Settings drawer or Guest
/// Link/Host Chat) is currently mid-flow, anywhere in the app. The
/// dashboard's Step 0 hint hides itself while this is true — see
/// dashboard_screen.dart's `_showStep0Hint`.
class WalkthroughActivity {
  WalkthroughActivity._();

  static final ValueNotifier<bool> isActive = ValueNotifier(false);
}
