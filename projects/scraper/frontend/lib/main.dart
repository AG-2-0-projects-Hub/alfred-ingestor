import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// ── CONFIG ────────────────────────────────────────────────────────────────────
// Replace with your Render.com URL after deployment.
const String kBackendUrl = 'https://scraper-ojux.onrender.com';
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  runApp(const AlfredScraperApp());
}

class AlfredScraperApp extends StatelessWidget {
  const AlfredScraperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alfred Scraper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A5F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'monospace',
      ),
      home: const ScraperHomePage(),
    );
  }
}

class ScraperHomePage extends StatefulWidget {
  const ScraperHomePage({super.key});

  @override
  State<ScraperHomePage> createState() => _ScraperHomePageState();
}

class _ScraperHomePageState extends State<ScraperHomePage> {
  final TextEditingController _urlController = TextEditingController();
  String _output = '';
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _runScrape() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isLoading = true;
      _output = '';
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$kBackendUrl/scrape'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'url': url}),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final data = decoded['data'] as String? ?? response.body;
        setState(() {
          _output = data;
        });
      } else {
        setState(() {
          _errorMessage = 'Error ${response.statusCode}: ${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Request failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text(
          'Alfred — Airbnb Scraper',
          style: TextStyle(
            color: Color(0xFFE6EDF3),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF30363D)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── URL Input Row ────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    style: const TextStyle(color: Color(0xFFE6EDF3)),
                    decoration: InputDecoration(
                      hintText: 'Paste Airbnb listing URL…',
                      hintStyle: const TextStyle(color: Color(0xFF8B949E)),
                      filled: true,
                      fillColor: const Color(0xFF161B22),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF30363D)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF30363D)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFF1E3A5F), width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    onSubmitted: (_) => _isLoading ? null : _runScrape(),
                  ),
                ),
                const SizedBox(width: 12),
                // ── Scrape Button ────────────────────────────────────────
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _runScrape,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F6FEB),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF21262D),
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Scrape',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // ── Loading indicator bar ────────────────────────────────────
            AnimatedOpacity(
              opacity: _isLoading ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: LinearProgressIndicator(
                backgroundColor: const Color(0xFF21262D),
                color: const Color(0xFF1F6FEB),
                minHeight: 2,
              ),
            ),

            const SizedBox(height: 20),

            // ── Error message ────────────────────────────────────────────
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF3D1A1A),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF8B1A1A)),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Color(0xFFF85149), fontSize: 13),
                ),
              ),

            // ── Output Panel ─────────────────────────────────────────────
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: _output.isEmpty && !_isLoading
                    ? Center(
                        child: Text(
                          _errorMessage != null
                              ? ''
                              : 'Output will appear here after scraping.',
                          style: const TextStyle(
                            color: Color(0xFF8B949E),
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : SingleChildScrollView(
                        child: SelectableText(
                          _output,
                          style: const TextStyle(
                            color: Color(0xFFE6EDF3),
                            fontSize: 13,
                            height: 1.6,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 12),
            Text(
              'Backend: $kBackendUrl',
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
              textAlign: TextAlign.right,
            ),
          ],
        ),
      ),
    );
  }
}
