import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/ingest_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/chat_live_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const IngestorApp());
}

class IngestorApp extends StatelessWidget {
  const IngestorApp({super.key});

  @override
  Widget build(BuildContext context) {
    final uri = Uri.base;
    final path = uri.path;
    final params = uri.queryParameters;

    Widget home;
    if (path == '/chat' && params.containsKey('booking')) {
      home = ChatScreen(bookingId: params['booking']!);
    } else if (path == '/chat-live' && params.containsKey('booking')) {
      home = ChatLiveScreen(
        bookingId: params['booking']!,
        propertyId: params['property'] ?? '',
      );
    } else {
      home = const IngestScreen();
    }

    return MaterialApp(
      title: 'Alfred -- Ingestor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: home,
    );
  }
}
