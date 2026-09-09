import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_live_dialog.dart';
import 'glass_panel.dart';
import '../theme/app_theme.dart';
import '../utils/walkthrough_prefs.dart';

class GenerateGuestLinkDialog extends StatefulWidget {
  final Map<String, dynamic> property;
  final VoidCallback? onCreated;
  final bool isDev;

  const GenerateGuestLinkDialog({
    super.key,
    required this.property,
    this.onCreated,
    this.isDev = false,
  });

  @override
  State<GenerateGuestLinkDialog> createState() =>
      _GenerateGuestLinkDialogState();
}

class _GenerateGuestLinkDialogState extends State<GenerateGuestLinkDialog> {
  final _nameController = TextEditingController();
  bool _loading = false;
  Map<String, dynamic>? _result; // {booking_id, guest_chat_url, host_chat_url}

  // Part C of the User-mode post-training walkthrough — first-ever guest link,
  // across any property (global flag, independent of Parts A/B). Steps 1-2
  // live here; steps 3-9 continue inside ChatLiveDialog once Open Host Chat
  // is tapped. Marked seen from there, not here — see ChatLiveDialog.dispose.
  bool _isWalkthrough = false;

  @override
  void initState() {
    super.initState();
    if (!widget.isDev) {
      WalkthroughPrefs.isGuestLinkWalkthroughSeen().then((seen) {
        if (mounted && !seen) {
          setState(() {
            _isWalkthrough = true;
            _nameController.text = 'Test walkthrough';
          });
        }
      });
    }
  }

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
    final propertyName = widget.property['name'] as String? ?? '';
    final isWalkthrough = _isWalkthrough;
    Navigator.of(context).pop();
    ChatLiveDialog.show(
      context,
      bookingId: bookingId,
      propertyId: propertyId,
      propertyName: propertyName,
      startWalkthrough: isWalkthrough,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 600;
    return AlertDialog(
      insetPadding: isMobile
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 24)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      contentPadding: EdgeInsets.fromLTRB(
          isMobile ? 14 : 24, 20, isMobile ? 14 : 24, 0),
      actionsPadding: EdgeInsets.fromLTRB(
          isMobile ? 14 : 16, 8, isMobile ? 14 : 16, isMobile ? 14 : 12),
      actionsOverflowDirection: VerticalDirection.up,
      actionsOverflowButtonSpacing: isMobile ? 8 : null,
      title: Text(_result != null
          ? '✓  Links ready${_nameController.text.trim().isNotEmpty ? " for ${_nameController.text.trim()}" : ""}'
          : 'New Guest Link'),
      content: _result == null ? _buildStep1(isMobile) : _buildStep2(isMobile),
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
              // Suppressed on the first-ever showing — Open Host Chat is the
              // only path forward, so the host can't skip the explanation.
              // Backdrop-dismiss still covers "not right now."
              if (!_isWalkthrough)
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
            ],
    );
  }

  Widget _buildStep1(bool isMobile) {
    return SizedBox(
      width: isMobile ? double.maxFinite : 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
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
          if (_isWalkthrough) ...[
            const SizedBox(height: 14),
            const _WalkthroughTip(
              eyebrow: 'GUEST LINK · 1 of 9',
              body: "I've filled in a test name — hit Generate Link and I'll "
                  "create real links you can use to message me yourself, as a guest.",
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStep2(bool isMobile) {
    final guestUrl = _result!['guest_chat_url'] as String;
    final hostUrl = _result!['host_chat_url'] as String;
    final telegramUrl = _result!['telegram_link'] as String?;
    final whatsappUrl = _result!['whatsapp_link'] as String?;
    final guestRows = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _urlRow('Guest link (web)', guestUrl),
        // WhatsApp before Telegram: it is the primary channel for the
        // Mexico/LATAM beta, and the first link a host sees is the one they
        // send. The link carries a PREFILLED message holding the booking id —
        // that text is how the guest gets connected, so it must not be edited
        // away (see routers/whatsapp.py).
        if (whatsappUrl != null && whatsappUrl.isNotEmpty) ...[
          const SizedBox(height: 16),
          _urlRow('Guest link (WhatsApp)', whatsappUrl),
        ],
        if (telegramUrl != null && telegramUrl.isNotEmpty) ...[
          const SizedBox(height: 16),
          _urlRow('Guest link (Telegram)', telegramUrl),
        ],
      ],
    );

    return SizedBox(
      width: isMobile ? double.maxFinite : 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _isWalkthrough
              ? Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.palette.primary, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: context.palette.primary.withValues(alpha: 0.25),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: guestRows,
                )
              : guestRows,
          const SizedBox(height: 16),
          _urlRow('Host link', hostUrl),
          if (_isWalkthrough) ...[
            const SizedBox(height: 14),
            const _WalkthroughTip(
              eyebrow: 'GUEST LINK · 2 of 9',
              body: 'Send whichever matches how your guest reaches out — web, '
                  'WhatsApp, or Telegram, they all reach me the same way. '
                  'One more thing to show you first →',
            ),
          ],
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

// Shared tip bubble for Part C's steps 1-2 — same visual language as Part A's
// Step 0 tip and Part B's docked panel (🤖 badge + eyebrow + body).
class _WalkthroughTip extends StatelessWidget {
  final String eyebrow;
  final String body;
  const _WalkthroughTip({required this.eyebrow, required this.body});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GlassPanel(
      radius: 14,
      blurSigma: AppTheme.glassBlurSigmaHeavy,
      tint: palette.glassTintStrong,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🤖', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
              Text(
                eyebrow,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: palette.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: GoogleFonts.inter(
                fontSize: 12.5, height: 1.5, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}
