import 'dart:async';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
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
