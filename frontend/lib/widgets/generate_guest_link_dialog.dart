import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/chat_live_screen.dart';
import '../theme/app_theme.dart';

class GenerateGuestLinkDialog extends StatefulWidget {
  final Map<String, dynamic> property;
  final VoidCallback? onCreated;

  const GenerateGuestLinkDialog({
    super.key,
    required this.property,
    this.onCreated,
  });

  @override
  State<GenerateGuestLinkDialog> createState() =>
      _GenerateGuestLinkDialogState();
}

class _GenerateGuestLinkDialogState extends State<GenerateGuestLinkDialog> {
  final _nameController = TextEditingController();
  bool _loading = false;
  Map<String, dynamic>? _result; // {booking_id, guest_chat_url, host_chat_url}

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() => _loading = true);
    final backendUrl = dotenv.env['BACKEND_URL'] ?? 'http://localhost:8000';
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/api/guests'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'property_id': widget.property['id'],
          'guest_name': _nameController.text.trim().isEmpty
              ? 'Guest'
              : _nameController.text.trim(),
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (mounted) setState(() => _result = data);
        widget.onCreated?.call();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error ${response.statusCode}: ${response.body}'),
                backgroundColor: context.palette.danger),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: context.palette.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied!'), duration: Duration(seconds: 1)),
    );
  }

  void _openHostChat() {
    final bookingId = _result!['booking_id'] as String;
    final propertyId = widget.property['id'] as String;
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ChatLiveScreen(bookingId: bookingId, propertyId: propertyId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_result != null
          ? '✓  Links ready${_nameController.text.trim().isNotEmpty ? " for ${_nameController.text.trim()}" : ""}'
          : 'New Guest Link'),
      content: _result == null ? _buildStep1() : _buildStep2(),
      actions: _result == null
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _loading ? null : _generate,
                child: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : const Text('Generate Link'),
              ),
            ]
          : [
              TextButton(
                onPressed: _openHostChat,
                child: const Text('Open Host Chat'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
    );
  }

  Widget _buildStep1() {
    return SizedBox(
      width: 360,
      child: TextField(
        controller: _nameController,
        decoration: const InputDecoration(
          labelText: 'Guest name (optional)',
          hintText: 'e.g. Maria Garcia',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _generate(),
      ),
    );
  }

  Widget _buildStep2() {
    final guestUrl = _result!['guest_chat_url'] as String;
    final hostUrl = _result!['host_chat_url'] as String;

    return SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _urlRow('Guest link', guestUrl),
          const SizedBox(height: 16),
          _urlRow('Host link', hostUrl),
        ],
      ),
    );
  }

  Widget _urlRow(String label, String url) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w500,
                fontSize: 12,
                color: palette.textSecondary)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                url,
                style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: palette.primary),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 18),
              tooltip: 'Copy',
              onPressed: () => _copy(url),
            ),
          ],
        ),
      ],
    );
  }
}
