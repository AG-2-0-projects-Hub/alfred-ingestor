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
  // New-style keys announce themselves by prefix. `sb_secret_` is the
  // service-role successor and must never reach a browser. (Checked before the
  // JWT branch below: a secret key is not a JWT, so decoding alone misses it —
  // which is exactly how one briefly reached a public deploy on 2026-07-13.)
  if (key.startsWith('sb_secret_')) {
    throw StateError('SUPABASE_ANON_KEY is an sb_secret_ key. Refusing to start '
        '— the web bundle is public; use the sb_publishable_ key.');
  }
  if (key.startsWith('sb_publishable_')) return;

  try {
    final parts = key.split('.');
    if (parts.length != 3) return; // not a JWT and not a known prefix
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    payload = payload.padRight((payload.length + 3) ~/ 4 * 4, '=');
    final role = (jsonDecode(utf8.decode(base64.decode(payload)))
        as Map<String, dynamic>)['role'];
    if (role == 'anon') return;

    throw StateError('SUPABASE_ANON_KEY must be the anon/publishable key, '
        'got role="$role". Refusing to start.');
  } on FormatException {
    return; // unparseable: leave it to Supabase to reject
  }
}

/// True when the app was opened from the "confirm your email" link.
///
/// Supabase's confirmation link signs the visitor straight in. That means anyone
/// who gets hold of the email — a shared inbox, a forwarded message — lands in
/// the host's dashboard without ever knowing the password. So we detect it, drop
/// the session, and make them sign in properly.
///
/// There are TWO link shapes and we have to catch both:
///   • Implicit flow — tokens in the URL FRAGMENT: `#access_token=…&type=signup`.
///   • PKCE flow — a single-use code in the QUERY: `/?code=<uuid>`.
/// The first fix only handled the fragment; prod turned out to send the PKCE
/// shape, so the link still dropped you into the dashboard. This app has no
/// social OAuth, so a bare `?code=` can only be a confirmation link.
///
/// Captured BEFORE Supabase.initialize, which consumes both.
bool _openedFromEmailConfirmation = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final launchUri = Uri.base;
  final q = launchUri.queryParameters;
  _openedFromEmailConfirmation =
      launchUri.fragment.contains('type=signup') ||
          launchUri.fragment.contains('type=email_change') ||
          q.containsKey('confirmed') ||
          q.containsKey('code') ||       // PKCE confirmation code
          q.containsKey('token_hash');   // older verify-OTP links

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

  /// Set once we've torn down the session that the confirmation link created,
  /// so the sign-in screen can say "email confirmed" and we don't loop.
  bool _confirmedNeedsSignIn = false;

  @override
  void initState() {
    super.initState();

    // The PKCE code is exchanged DURING Supabase.initialize, so a session may
    // already exist right now — before any listener could fire. Catch that case
    // directly; the listener below catches the implicit flow, where the session
    // is restored a beat later.
    if (_openedFromEmailConfirmation &&
        Supabase.instance.client.auth.currentSession != null) {
      _tearDownConfirmationSession();
    }

    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      if (_openedFromEmailConfirmation && data.session != null) {
        await _tearDownConfirmationSession();
        return;
      }
      if (mounted) setState(() {});
    });
  }

  bool _tearingDown = false;

  /// Sign out the session the confirmation link created and flip to sign-in.
  /// Guarded so the two entry points (initState + the auth listener) don't both
  /// fire it.
  Future<void> _tearDownConfirmationSession() async {
    if (_tearingDown) return;
    _tearingDown = true;
    await Supabase.instance.client.auth.signOut();
    if (mounted) setState(() => _confirmedNeedsSignIn = true);
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

    // Arriving from the confirmation link must never drop you straight into the
    // dashboard — sign in with the password like anyone else.
    if (_openedFromEmailConfirmation) {
      return _app(AuthScreen(justConfirmed: _confirmedNeedsSignIn),
          wrapInactivity: false);
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
