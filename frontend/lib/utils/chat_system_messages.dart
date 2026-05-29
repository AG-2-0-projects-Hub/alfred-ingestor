/// Single source of truth for chat system messages.
///
/// What's stored in the DB is now a marker token (e.g. `__SYS_INTERVENE__`),
/// not the user-facing string. Each viewer (guest or host) renders the marker
/// with their own context — that's how the same DB row produces:
///   - guest: "You are now speaking with Eduardo Rafael."
///   - host:  "You are now speaking with Maria."
///
/// Legacy plain-text messages (from before this refactor) still render
/// verbatim through the fall-through in the formatters and are still
/// recognised by [inferModeFromSystemMessage].
class ChatSystemMessages {
  // ── Marker tokens (persisted to messages.content) ─────────────────────────
  static const String intervene = '__SYS_INTERVENE__';
  static const String resume = '__SYS_RESUME__';
  static const String resumeAfterResolve = '__SYS_RESOLVED__';

  // ── Legacy strings (still present in older DB rows) ───────────────────────
  static const String _legacyIntervenePrefix = 'You are now speaking with';
  static const String _legacyResume = 'Alfred has resumed your conversation.';
  static const String _legacyResolvedFull =
      'Issue resolved — Alfred has resumed the conversation.';

  /// What the guest sees for a given system message content.
  static String formatForGuest(String content, {required String hostName}) {
    switch (content) {
      case intervene:
        return 'You are now speaking with $hostName.';
      case resume:
      case resumeAfterResolve:
        return 'Alfred has resumed the conversation.';
    }
    // Legacy: strip the host-only "Issue resolved —" prefix so old messages
    // render the guest-appropriate text without a migration.
    if (content == _legacyResolvedFull) {
      return 'Alfred has resumed the conversation.';
    }
    return content;
  }

  /// What the host sees for a given system message content.
  static String formatForHost(String content, {required String guestName}) {
    switch (content) {
      case intervene:
        return 'You are now speaking with $guestName.';
      case resume:
        return 'Alfred has resumed the conversation.';
      case resumeAfterResolve:
        return 'Issue resolved — Alfred has resumed the conversation.';
    }
    return content;
  }

  /// Used by the guest-side piggyback to keep `_mode` in sync via the
  /// messages stream when the conversations stream silently drops.
  /// Returns the implied mode or null if [content] isn't a recognised marker.
  static String? inferModeFromSystemMessage(String content) {
    if (content == intervene) return 'intervene';
    if (content == resume || content == resumeAfterResolve) return 'autopilot';
    // Backward-compat for legacy plain-text rows.
    if (content.startsWith(_legacyIntervenePrefix)) return 'intervene';
    if (content == _legacyResume || content == _legacyResolvedFull) {
      return 'autopilot';
    }
    return null;
  }
}
