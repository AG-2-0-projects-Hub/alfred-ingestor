// QA scenario C6 (chat-sys-markers-01) — Layer 1 widget test
// See: _tests/scenarios.md C6
//
// Asserts that ChatSystemMessages.formatForGuest/formatForHost render the
// marker tokens correctly per viewer, and that legacy plain-text content
// passes through verbatim.

import 'package:flutter_test/flutter_test.dart';
import 'package:the_ingestor/utils/chat_system_messages.dart';

void main() {
  group('ChatSystemMessages.formatForGuest', () {
    test('intervene marker renders host name', () {
      final result = ChatSystemMessages.formatForGuest(
        ChatSystemMessages.intervene,
        hostName: 'Maria',
      );
      expect(result, equals('You are now speaking with your host Maria.'));
    });

    test('renders in Spanish when the guest is chatting in Spanish', () {
      expect(
        ChatSystemMessages.formatForGuest(
          ChatSystemMessages.intervene,
          hostName: 'Maria',
          language: 'es',
        ),
        equals('Ahora estás hablando con tu anfitrión Maria.'),
      );
      expect(
        ChatSystemMessages.formatForGuest(
          ChatSystemMessages.resume,
          hostName: 'Maria',
          language: 'es-MX',
        ),
        equals('Alfred ha retomado la conversación.'),
      );
    });

    test('unknown or missing language falls back to English', () {
      expect(
        ChatSystemMessages.formatForGuest(
          ChatSystemMessages.intervene,
          hostName: 'Maria',
          language: 'de',
        ),
        equals('You are now speaking with your host Maria.'),
      );
    });

    test('resume marker renders neutral message', () {
      expect(
        ChatSystemMessages.formatForGuest(
          ChatSystemMessages.resume,
          hostName: 'Maria',
        ),
        equals('Alfred has resumed the conversation.'),
      );
    });

    test('resumeAfterResolve marker renders neutral message', () {
      expect(
        ChatSystemMessages.formatForGuest(
          ChatSystemMessages.resumeAfterResolve,
          hostName: 'Maria',
        ),
        equals('Alfred has resumed the conversation.'),
      );
    });

    test('legacy plain-text content renders verbatim', () {
      const legacy = 'Some old plain-text system message';
      expect(
        ChatSystemMessages.formatForGuest(legacy, hostName: 'Maria'),
        equals(legacy),
      );
    });

    test('legacy resolved string strips host-only prefix for guest', () {
      expect(
        ChatSystemMessages.formatForGuest(
          'Issue resolved — Alfred has resumed the conversation.',
          hostName: 'Maria',
        ),
        equals('Alfred has resumed the conversation.'),
      );
    });
  });

  group('ChatSystemMessages.formatForHost', () {
    test('intervene marker renders guest name', () {
      final result = ChatSystemMessages.formatForHost(
        ChatSystemMessages.intervene,
        guestName: 'Alex',
      );
      expect(result, equals('You are now speaking with Alex.'));
    });

    test('resume marker renders neutral message', () {
      expect(
        ChatSystemMessages.formatForHost(
          ChatSystemMessages.resume,
          guestName: 'Alex',
        ),
        equals('Alfred has resumed the conversation.'),
      );
    });

    test('resumeAfterResolve marker keeps the "Issue resolved" prefix for host', () {
      expect(
        ChatSystemMessages.formatForHost(
          ChatSystemMessages.resumeAfterResolve,
          guestName: 'Alex',
        ),
        equals('Issue resolved — Alfred has resumed the conversation.'),
      );
    });

    test('legacy plain-text content renders verbatim', () {
      const legacy = 'Some old plain-text system message';
      expect(
        ChatSystemMessages.formatForHost(legacy, guestName: 'Alex'),
        equals(legacy),
      );
    });
  });

  group('ChatSystemMessages.inferModeFromSystemMessage', () {
    test('intervene marker maps to intervene', () {
      expect(
        ChatSystemMessages.inferModeFromSystemMessage(
          ChatSystemMessages.intervene,
        ),
        equals('intervene'),
      );
    });

    test('resume marker maps to autopilot', () {
      expect(
        ChatSystemMessages.inferModeFromSystemMessage(
          ChatSystemMessages.resume,
        ),
        equals('autopilot'),
      );
    });

    test('resumeAfterResolve maps to autopilot', () {
      expect(
        ChatSystemMessages.inferModeFromSystemMessage(
          ChatSystemMessages.resumeAfterResolve,
        ),
        equals('autopilot'),
      );
    });

    test('legacy intervene prefix maps to intervene', () {
      expect(
        ChatSystemMessages.inferModeFromSystemMessage(
          'You are now speaking with Maria.',
        ),
        equals('intervene'),
      );
    });

    test('unknown content returns null', () {
      expect(
        ChatSystemMessages.inferModeFromSystemMessage('random text'),
        isNull,
      );
    });
  });
}
