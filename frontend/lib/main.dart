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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

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
    // Re-render when auth state changes — this catches the async session
    // restoration on page reload (Supabase reads localStorage and fires
    // initialSession event after the first build would otherwise have run).
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

    // Public chat routes — no auth required.
    if (path == '/chat' && params.containsKey('booking')) {
      return _app(ChatScreen(bookingId: params['booking']!));
    }
    if (path == '/chat-live' && params.containsKey('booking')) {
      return _app(ChatLiveScreen(
        bookingId: params['booking']!,
        propertyId: params['property'] ?? '',
      ));
    }

    // Host panel deep-link.
    if (path == '/host-panel' && params.containsKey('property')) {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return _app(const AuthScreen());
      return _app(HostPanelScreen(propertyId: params['property']!));
    }

    // Default: auth guard → dashboard.
    final session = Supabase.instance.client.auth.currentSession;
    return _app(session != null ? const DashboardScreen() : const AuthScreen());
  }

  MaterialApp _app(Widget home) {
    return MaterialApp(
      title: 'Alfred',
      theme: AppTheme.light,
      home: _AuthWatcher(child: home),
      routes: {
        '/auth': (_) => const AuthScreen(),
        '/dashboard': (_) => const DashboardScreen(),
        '/add-property': (_) => const AddPropertyScreen(),
      },
    );
  }
}

/// Listens to auth state changes and redirects to AuthScreen on logout.
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
