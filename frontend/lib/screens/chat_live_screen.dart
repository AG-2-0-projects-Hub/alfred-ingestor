import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/aurora_background.dart';

class ChatLiveScreen extends StatefulWidget {
  final String bookingId;
  final String propertyId;

  const ChatLiveScreen({
    super.key,
    required this.bookingId,
    required this.propertyId,
  });

  @override
  State<ChatLiveScreen> createState() => _ChatLiveScreenState();
}

class _ChatLiveScreenState extends State<ChatLiveScreen> {
  String? _conversationId;
  String? _guestChatUrl;
  bool _copiedLink = false;
  List<Map<String, dynamic>> _messages = [];
  String _mode = 'autopilot';
  bool _isSending = false;
  final _hostController = TextEditingController();
  final _scrollController = ScrollController();
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;

  @override
  void initState() {
    super.initState();
    _loadConversation();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _hostController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadConversation() async {
    final results = await Future.wait([
      Supabase.instance.client
          .from('conversations')
          .select('id, mode')
          .eq('booking_id', widget.bookingId)
          .maybeSingle(),
      Supabase.instance.client
          .from('guests')
          .select('guest_chat_url')
          .eq('booking_id', widget.bookingId)
          .maybeSingle(),
    ]);

    final conv = results[0] as Map<String, dynamic>?;
    final guest = results[1] as Map<String, dynamic>?;

    if (mounted) {
      setState(() {
        if (conv != null) {
          _conversationId = conv['id'] as String;
          _mode = conv['mode'] as String? ?? 'autopilot';
        }
        _guestChatUrl = guest?['guest_chat_url'] as String?;
      });
      if (_conversationId != null) _subscribeToMessages(_conversationId!);
    }
  }

  Future<void> _copyGuestLink() async {
    if (_guestChatUrl == null) return;
    await Clipboard.setData(ClipboardData(text: _guestChatUrl!));
    if (mounted) {
      setState(() => _copiedLink = true);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _copiedLink = false);
      });
    }
  }

  void _subscribeToMessages(String conversationId) {
    _subscription?.cancel();
    _subscription = Supabase.instance.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .listen((data) {
          if (mounted) {
            setState(() => _messages = data);
            _scrollToBottom();
            // Auto-switch to intervene when an escalated AI message arrives
            if (_mode == 'autopilot' &&
                data.isNotEmpty &&
                data.last['is_escalated_interaction'] == true) {
              _setMode('intervene');
            }
          }
        });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _setMode(String mode) async {
    if (_conversationId == null) return;
    await Supabase.instance.client
        .from('conversations')
        .update({'mode': mode}).eq('id', _conversationId!);
    if (mounted) setState(() => _mode = mode);
  }

  Future<void> _sendHostMessage() async {
    final text = _hostController.text.trim();
    if (text.isEmpty || _conversationId == null || _isSending) return;
    _hostController.clear();
    setState(() => _isSending = true);

    try {
      await ApiClient.postJson(
        '/api/messages/host-send',
        {'conversation_id': _conversationId, 'message': text},
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.userMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: AppBar(
              backgroundColor: AppTheme.glassTint,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Live Chat',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: AppTheme.primary),
                  ),
                  Text(
                    widget.bookingId,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: AuroraBackground(
        intensity: 0.4,
        child: Padding(
          padding: const EdgeInsets.only(top: kToolbarHeight),
          child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Left: conversation ───────────────────────────────────────────
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  color: AppTheme.surfaceAlt,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Conversation',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: AppTheme.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chat_bubble_outline_rounded,
                                  size: 40,
                                  color: AppTheme.border),
                              const SizedBox(height: 12),
                              Text(
                                'No messages yet.',
                                style: GoogleFonts.inter(
                                    color: AppTheme.textMuted, fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) => _buildBubble(_messages[i]),
                        ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          // ── Right: host control panel ────────────────────────────────────
          SizedBox(
            width: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildGuestLinkSection(),
                _buildModeToggle(),
                const Divider(height: 1),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        _mode == 'autopilot'
                            ? 'Alfred is handling this conversation.\n\nSwitch to Intervene to reply manually.'
                            : 'You are in control.\nType below to reply to the guest.',
                        style: GoogleFonts.inter(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          height: 1.6,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                if (_mode == 'intervene') _buildHostInput(),
              ],
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }

  Widget _buildGuestLinkSection() {
    if (_guestChatUrl == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Guest Chat Link',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text(
                  _guestChatUrl!,
                  style: GoogleFonts.inter(
                      fontSize: 11, color: AppTheme.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _copiedLink ? null : _copyGuestLink,
                  icon: Icon(
                    _copiedLink
                        ? Icons.check_circle_outline_rounded
                        : Icons.copy_rounded,
                    size: 16,
                  ),
                  label: Text(_copiedLink ? 'Copied!' : 'Copy Guest Link'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _copiedLink
                        ? AppTheme.success
                        : AppTheme.primary,
                    side: BorderSide(
                        color: _copiedLink
                            ? AppTheme.success
                            : AppTheme.border),
                  ),
                ),
              ),
              if (_copiedLink) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        size: 12, color: AppTheme.success),
                    const SizedBox(width: 4),
                    Text(
                      'Link copied to clipboard.',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppTheme.success),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 24),
      ],
    );
  }

  Widget _buildModeToggle() {
    final isAutopilot = _mode == 'autopilot';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mode',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _modeButton(
                    label: 'Autopilot',
                    active: isAutopilot,
                    activeColor: AppTheme.primary,
                    onTap: isAutopilot ? null : () => _setMode('autopilot'),
                  ),
                ),
                Expanded(
                  child: _modeButton(
                    label: 'Intervene',
                    active: !isAutopilot,
                    activeColor: AppTheme.warning,
                    onTap: !isAutopilot ? null : () => _setMode('intervene'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeButton({
    required String label,
    required bool active,
    required Color activeColor,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppTheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: active ? activeColor : AppTheme.textMuted,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(Map<String, dynamic> msg) {
    final senderType = msg['sender_type'] as String;
    final isGuest = senderType == 'guest';
    final isHost = senderType == 'host';
    final isEscalated = msg['is_escalated_interaction'] == true;

    Color bgColor;
    Color textColor = AppTheme.textPrimary;
    BorderRadius radius;

    if (isGuest) {
      bgColor = AppTheme.primaryContainer;
      radius = const BorderRadius.only(
        topLeft: Radius.circular(14),
        topRight: Radius.circular(14),
        bottomLeft: Radius.circular(14),
        bottomRight: Radius.circular(3),
      );
    } else if (isHost) {
      bgColor = AppTheme.surface;
      radius = const BorderRadius.only(
        topLeft: Radius.circular(3),
        topRight: Radius.circular(14),
        bottomLeft: Radius.circular(14),
        bottomRight: Radius.circular(14),
      );
    } else if (isEscalated) {
      bgColor = AppTheme.warningContainer;
      radius = BorderRadius.circular(14);
    } else {
      bgColor = AppTheme.surfaceAlt;
      radius = const BorderRadius.only(
        topLeft: Radius.circular(3),
        topRight: Radius.circular(14),
        bottomLeft: Radius.circular(14),
        bottomRight: Radius.circular(14),
      );
    }

    final senderLabel = isGuest
        ? 'Guest'
        : isHost
            ? 'You'
            : isEscalated
                ? 'Alfred — needs attention'
                : 'Alfred';

    final senderColor = isGuest
        ? AppTheme.primary
        : isHost
            ? AppTheme.textSecondary
            : isEscalated
                ? AppTheme.warning
                : AppTheme.textMuted;

    return Align(
      alignment: isGuest ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: radius,
          border: isHost
              ? Border.all(color: AppTheme.border)
              : isEscalated
                  ? Border.all(color: AppTheme.warning, width: 1.5)
                  : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              senderLabel,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: senderColor,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              msg['content'] as String,
              style: GoogleFonts.inter(fontSize: 13, color: textColor, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHostInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _hostController,
              decoration: InputDecoration(
                hintText: 'Reply to guest…',
                hintStyle: GoogleFonts.inter(
                    fontSize: 13, color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              style: GoogleFonts.inter(fontSize: 13),
              onSubmitted: (_) => _sendHostMessage(),
              textInputAction: TextInputAction.send,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _isSending ? null : _sendHostMessage,
            icon: const Icon(Icons.send_rounded, size: 18),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppTheme.border,
              disabledForegroundColor: AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
