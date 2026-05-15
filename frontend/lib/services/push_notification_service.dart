import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Browser-native Web Notification API wrapper.
///
/// Tab must be open — no service worker / FCM. Click handlers focus the tab
/// and dispatch the user-supplied callback (typically opens ChatLiveDialog).
class PushNotificationService {
  static String _cachedState = 'default';
  static final Map<String, VoidCallback> _callbackRegistry = {};
  static int _idCounter = 0;

  static bool get isSupported {
    try {
      return globalContext.has('Notification');
    } catch (_) {
      return false;
    }
  }

  static String get permissionState {
    if (!isSupported) return 'denied';
    try {
      return web.Notification.permission;
    } catch (_) {
      return _cachedState;
    }
  }

  static Future<void> requestPermission() async {
    if (!isSupported) return;
    final current = permissionState;
    if (current == 'granted' || current == 'denied') {
      _cachedState = current;
      return;
    }
    try {
      final result = await web.Notification.requestPermission().toDart;
      _cachedState = result.toDart;
    } catch (_) {
      // ignore — leaves _cachedState unchanged
    }
  }

  static void showEscalationAlert({
    required String propertyName,
    required String bookingId,
    required String? reason,
    required bool isEmergency,
    required VoidCallback onTap,
  }) {
    if (!isSupported || permissionState != 'granted') return;

    final title = isEmergency
        ? '🚨 Alfred Alert — $propertyName'
        : 'Alfred Alert — $propertyName';
    final body = isEmergency
        ? 'Emergency: ${reason ?? bookingId}'
        : 'Guest needs attention: ${reason ?? bookingId}';

    try {
      final options = web.NotificationOptions(
        body: body,
        icon: '/icons/Icon-192.png',
      );
      final notification = web.Notification(title, options);

      final id = '${++_idCounter}-${DateTime.now().millisecondsSinceEpoch}';
      _callbackRegistry[id] = onTap;

      notification.onclick = ((web.Event _) {
        try {
          web.window.focus();
        } catch (_) {}
        final cb = _callbackRegistry.remove(id);
        try {
          notification.close();
        } catch (_) {}
        cb?.call();
      }).toJS;

      Timer(const Duration(seconds: 30), () {
        _callbackRegistry.remove(id);
      });
    } catch (_) {
      // ignore — never let a notification failure bubble into the dashboard
    }
  }
}
