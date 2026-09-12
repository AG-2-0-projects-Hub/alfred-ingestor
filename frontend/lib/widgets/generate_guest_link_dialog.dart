import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_live_dialog.dart';
import 'walkthrough_tip_panel.dart';
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

  // Part C steps 1-2 of the post-training walkthrough (steps 3-9 continue in
  // ChatLiveDialog once "Open Host Chat" is used — see walkthrough.md).
  // Fires once ever, across all properties, on the first-ever guest link
  // generated. Docked via a real Overlay entry for the same reason as Part B
  // (property_detail_drawer.dart's _wtOverlay) — never nest the tip panel
  // inside this dialog's own showDialog route.
  bool _wtActive = false;
  final _wtDockLink = LayerLink();
  OverlayEntry? _wtOverlay;
  final _wtStepNotifier = ValueNotifier<int?>(null);

  @override
  void initState() {
    super.initState();
    _maybeStartWalkthrough();
  }

  Future<void> _maybeStartWalkthrough() async {
    if (widget.isDev) return;
    final seen = await WalkthroughPrefs.isGuestLinkWalkthroughSeen();
    if (seen || !mounted) return;
    setState(() {
      _wtActive = true;
      _nameController.text = 'Test walkthrough';
    });
    _wtStepNotifier.value = 0;
  }

  void _wtClose() {
    setState(() => _wtActive = false);
    _wtStepNotifier.value = null;
  }

  void _wtNext() {
    if (_result == null) {
      _generate();
    } else {
      _openHostChat();
    }
  }

  void _ensureWtOverlayInserted() {
    if (_wtOverlay != null) return;
    final entry = OverlayEntry(builder: (overlayContext) {
      return ValueListenableBuilder<int?>(
        valueListenable: _wtStepNotifier,
        builder: (_, step, __) {
          final screenW = MediaQuery.of(overlayContext).size.width;
          if (step == null || screenW < 1000) return const SizedBox.shrink();
          return Positioned(
            width: 300,
            child: CompositedTransformFollower(
              link: _wtDockLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topRight,
              followerAnchor: Alignment.topLeft,
              offset: const Offset(20, 0),
              child: WalkthroughTipPanel(
                stepIndex: step,
                stepCount: 9,
                body: step == 0
                    ? "I've filled in a test name — hit Generate Link and "
                        "I'll create real links you can use to message me "
                        "myself, as a guest."
                    : "Send whichever matches how your guest reaches out — "
                        "web, WhatsApp, or Telegram, they all reach me the "
                        "same way. One more thing to show you first →",
                onNext: _wtNext,
                onClose: _wtClose,
                isLast: false,
              ),
            ),
          );
        },
      );
    });
    _wtOverlay = entry;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Overlay.of(context, rootOverlay: true).insert(entry);
    });
  }

  @override
  void dispose() {
    _wtOverlay?.remove();
    _wtOverlay = null;
    _wtStepNotifier.dispose();
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
        if (_wtActive) _wtStepNotifier.value = 1;
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
    final continueWalkthrough = _wtActive;
    Navigator.of(context).pop();
    ChatLiveDialog.show(
      context,
      bookingId: bookingId,
      propertyId: propertyId,
      propertyName: propertyName,
      continueWalkthrough: continueWalkthrough,
    );
  }

  List<Widget> get _actions => _result == null
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
        ];

  String get _titleText => _result != null
      ? '✓  Links ready${_nameController.text.trim().isNotEmpty ? " for ${_nameController.text.trim()}" : ""}'
      : 'New Guest Link';

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 600;

    // The LayerLink target must wrap a tightly-sized widget, not the whole
    // AlertDialog — Dialog's own build() internally expands to fill the
    // entire route (to center its card), so a target wrapping the whole
    // AlertDialog reports the FULL SCREEN as its box, anchoring the docked
    // panel off past the viewport edge. Wrapping just `content` (a real,
    // dialog-sized widget) gives a sane box to anchor beside instead.
    final content = CompositedTransformTarget(
      link: _wtDockLink,
      child: _result == null ? _buildStep1(isMobile) : _buildStep2(isMobile),
    );

    final dialog = AlertDialog(
      insetPadding: isMobile
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 24)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      contentPadding: EdgeInsets.fromLTRB(
          isMobile ? 14 : 24, 20, isMobile ? 14 : 24, 0),
      actionsPadding: EdgeInsets.fromLTRB(
          isMobile ? 14 : 16, 8, isMobile ? 14 : 16, isMobile ? 14 : 12),
      actionsOverflowDirection: VerticalDirection.up,
      actionsOverflowButtonSpacing: isMobile ? 8 : null,
      title: Text(_titleText),
      content: content,
      actions: _actions,
    );

    _ensureWtOverlayInserted();
    return dialog;
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
          guestRows,
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
