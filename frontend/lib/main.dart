import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/add_property_screen.dart';
import 'screens/host_panel_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/chat_live_screen.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'widgets/inactivity_wrapper.dart';

/// Everything in `.env` is compiled into the web bundle and served publicly at
/// /assets/.env — so the ONLY Supabase key that may ever appear there is the
/// anon key, which is designed to be public and constrained by RLS.
///
/// On 2026-07-13 the prod Vercel project had the **service_role** key pasted
/// into SUPABASE_ANON_KEY. That key bypasses RLS and can read, delete or
/// rewrite any table and reset any user's password — and the live site was
/// handing it to every visitor. This refuses to boot rather than ever ship that
/// again: a misconfigured deploy must fail loudly, not silently expose the DB.
void _assertNotAServiceRoleKey(String key) {
  try {
    final parts = key.split('.');
    if (parts.length != 3) return; // not a JWT (e.g. a new-style sb_publishable key)
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    payload = payload.padRight((payload.length + 3) ~/ 4 * 4, '=');
    final role = (jsonDecode(utf8.decode(base64.decode(payload)))
        as Map<String, dynamic>)['role'];
    if (role == 'anon') return;

    debugPrint('FATAL: SUPABASE_ANON_KEY carries role="$role". Refusing to '
        'start — a non-anon key in the web bundle is public and omnipotent.');
    throw StateError('SUPABASE_ANON_KEY must be the anon key, got role="$role"');
  } on FormatException {
    return; // unparseable: leave it to Supabase to reject
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  final anonKey = dotenv.env['SUPABASE_ANON_KEY']!;
  _assertNotAServiceRoleKey(anonKey);

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: anonKey,
  );

  await themeController.load();

  runApp(const IngestorApp());
}

class IngestorApp extends StatefulWidget {
  const IngestorApp({super.key});

  @override
  State<IngestorApp> createState() => _IngestorAppState();
}

class _IngestorAppState extends State<IngestorApp> {
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange
        .listen((_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uri = Uri.base;
    final path = uri.path;
    final params = uri.queryParameters;

    // Public chat routes — no auth required, no inactivity timer.
    if (path == '/chat' && params.containsKey('booking')) {
      return _app(ChatScreen(bookingId: params['booking']!), wrapInactivity: false);
    }
    if (path == '/chat-live' && params.containsKey('booking')) {
      return _app(ChatLiveScreen(
        bookingId: params['booking']!,
        propertyId: params['property'] ?? '',
      ));
    }

    if (path == '/host-panel' && params.containsKey('property')) {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return _app(const AuthScreen(), wrapInactivity: false);
      return _app(HostPanelScreen(propertyId: params['property']!));
    }

    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      return _app(const DashboardScreen());
    }
    return _app(const AuthScreen(), wrapInactivity: false);
  }

  Widget _app(Widget home, {bool wrapInactivity = true}) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        final wrapped = wrapInactivity ? InactivityWrapper(child: home) : home;
        return MaterialApp(
          title: 'Alfred',
          theme: AppTheme.daylightTheme,
          darkTheme: AppTheme.midnightTheme,
          themeMode: themeController.mode,
          home: _AuthWatcher(child: wrapped),
          routes: {
            '/auth': (_) => const AuthScreen(),
            '/dashboard': (_) => const DashboardScreen(),
            '/add-property': (_) => const AddPropertyScreen(),
          },
        );
      },
    );
  }
}

class _AuthWatcher extends StatefulWidget {
  final Widget child;
  const _AuthWatcher({required this.child});

  @override
  State<_AuthWatcher> createState() => _AuthWatcherState();
}

class _AuthWatcherState extends State<_AuthWatcher> {
  late final Stream<AuthState> _authStream;

  @override
  void initState() {
    super.initState();
    _authStream = Supabase.instance.client.auth.onAuthStateChange;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _authStream,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final event = snapshot.data!.event;
          if (event == AuthChangeEvent.signedOut) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AuthScreen()),
                (_) => false,
              );
            });
          }
        }
        return widget.child;
      },
    );
  }
}
