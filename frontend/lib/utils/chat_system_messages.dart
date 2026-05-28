/// Single source of truth for system message text in the chat thread.
///
/// These strings are inserted into the messages table on the host side and
/// pattern-matched on the guest side to keep `_mode` in sync without relying
/// solely on the conversations stream (which can drop on Supabase free tier).
/// If you change the wording, update both ends here — the matchers below
/// scan for the leading phrase to stay tolerant to minor edits.
class ChatSystemMessages {
  static const String resume = 'Alfred has resumed your conversation.';
  static const String resumeAfterResolve =
      'Issue resolved — Alfred has resumed the conversation.';
  static String intervene(String hostName) =>
      'You are now speaking with $hostName.';

  // Substring matchers used by the guest-side piggyback.
  static const String _resumeMatch = 'Alfred has resumed';
  static const String _interveneMatch = 'You are now speaking with';

  /// Returns the implied conversation mode if [content] looks like a known
  /// system message, otherwise null.
  static String? inferModeFromSystemMessage(String content) {
    if (content.contains(_resumeMatch)) return 'autopilot';
    if (content.contains(_interveneMatch)) return 'intervene';
    return null;
  }
}
