import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/relative_time.dart';

/// Glassmorphic modal containing the same two-panel chat layout as
/// [ChatLiveScreen]. Opens via [ChatLiveDialog.show] on top of
/// PropertyExpandedView so the user stays on the dashboard.
class ChatLiveDialog extends StatefulWidget {
  final String bookingId;
  final String propertyId;
  final String propertyName;

  const ChatLiveDialog({
    super.key,
    required this.bookingId,
    required this.propertyId,
    required this.propertyName,
  });

  static Future<void> show(
    BuildContext context, {
    required String bookingId,
    required String propertyId,
    required String propertyName,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close chat',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, __, ___) => ChatLiveDialog(
        bookingId: bookingId,
        propertyId: propertyId,
        propertyName: propertyName,
      ),
      transitionBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.94, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<ChatLiveDialog> createState() => _ChatLiveDialogState();
}

class _ChatLiveDialogState extends State<ChatLiveDialog> {
  String? _conversationId;
  String? _guestChatUrl;
  String _hostName = 'Your host';
  bool _copiedLink = false;
  List<Map<String, dynamic>> _messages = [];
  String _mode = 'autopilot';
  String? _escalationReason;
  bool _isSending = false;
  bool _isResolving = false;
  final _hostController = TextEditingController();
  final _scrollController = ScrollController();
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  StreamSubscription<List<Map<String, dynamic>>>? _convSubscription;

  @override
  void initState() {
    super.initState();
    _loadConversation();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _convSubscription?.cancel();
    _hostController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadConversation() async {
    final results = await Future.wait([
      Supabase.instance.client
          .from('guests')
          .select('guest_chat_url')
          .eq('booking_id', widget.bookingId)
          .maybeSingle(),
      Supabase.instance.client
          .from('properties')
          .select("master_json->host_profile->>name")
          .eq('id', widget.propertyId)
          .maybeSingle(),
    ]);

    final guest = results[0] as Map<String, dynamic>?;
    final prop = results[1] as Map<String, dynamic>?;

    if (mounted) {
      setState(() {
        _guestChatUrl = guest?['guest_chat_url'] as String?;
        _hostName = (prop?['name'] as String?) ?? 'Your host';
      });
      _watchConversation();
    }
  }

  void _watchConversation() {
    _convSubscription?.cancel();
    _convSubscription = Supabase.instance.client
        .from('conversations')
        .stream(primaryKey: ['id'])
        .eq('booking_id', widget.bookingId)
        .listen((rows) {
          if (!mounted || rows.isEmpty) return;
          final row = rows.first;
          final rowId = row['id'] as String;
          setState(() {
            _mode = row['mode'] as String? ?? 'autopilot';
            _escalationReason = row['escalation_reason'] as String?;
          });
          if (_conversationId == null) {
            setState(() => _conversationId = rowId);
            _subscribeToMessages(rowId);
          }
        });
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

  Future<void> _insertSystemMessage(String content) async {
    if (_conversationId == null) return;
    await Supabase.instance.client.from('messages').insert(<String, dynamic>{
      'conversation_id': _conversationId,
      'sender_type': 'system',
      'content': content,
      'status': 'delivered',
    });
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
    if (mode == 'intervene') {
      await _insertSystemMessage('You are now speaking with $_hostName.');
    } else {
      await _insertSystemMessage('Alfred has resumed your conversation.');
    }
  }

  Future<void> _resolveIssue() async {
    if (_isResolving) return;
    setState(() => _isResolving = true);
    try {
      await ApiClient.postJson(
        '/api/conversations/resolve',
        {'booking_id': widget.bookingId},
      );
      if (mounted) {
        setState(() {
          _mode = 'autopilot';
          _escalationReason = null;
        });
        await _insertSystemMessage('Alfred has resumed your conversation.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Issue resolved. Alfred is back on autopilot.'),
              backgroundColor: context.palette.success,
            ),
          );
        }
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.userMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resolve: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isResolving = false);
    }
  }

  Future<void> _sendHostMessage() async {
    final text = _hostController.text.trim();
    if (text.isEmpty || _conversationId == null || _isSending) return;
    _hostController.clear();

    final optimisticId = 'local-${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _isSending = true;
      _messages = [
        ..._messages,
        <String, dynamic>{
          'id': optimisticId,
          'sender_type': 'host',
          'content': text,
          'status': 'sending',
          'created_at': DateTime.now().toIso8601String(),
        },
      ];
    });
    _scrollToBottom();

    try {
      await ApiClient.postJson(
        '/api/messages/host-send',
        {'conversation_id': _conversationId, 'message': text},
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _messages = _messages.where((m) => m['id'] != optimisticId).toList());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.userMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _messages = _messages.where((m) => m['id'] != optimisticId).toList());
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
    final palette = context.palette;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1320,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: palette.glassTintStrong,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: palette.glassBorderStrong),
              ),
              child: Column(
                children: [
                  _buildDialogAppBar(),
                  const Divider(height: 1),
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDialogAppBar() {
    final palette = context.palette;
    final isEmergency = _escalationReason?.startsWith('emergency_') == true;
    final modeColor = _mode == 'intervene'
        ? palette.warning
        : (isEmergency
            ? palette.danger
            : (_escalationReason != null ? palette.warning : palette.primary));
    final modeLabel = _mode == 'intervene'
        ? 'Intervene'
        : (_escalationReason != null ? 'Needs Attention' : 'Autopilot');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.propertyName.isEmpty ? 'Live Chat' : widget.propertyName,
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: palette.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  widget.bookingId,
                  style: GoogleFonts.inter(fontSize: 11, color: palette.textMuted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: modeColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: modeColor.withValues(alpha: 0.45)),
            ),
            child: Text(
              modeLabel,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: modeColor,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            color: palette.textMuted,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                color: context.palette.surfaceAlt,
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Conversation',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: context.palette.textSecondary),
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
                                size: 40, color: context.palette.border),
                            const SizedBox(height: 12),
                            Text(
                              'No messages yet.',
                              style: GoogleFonts.inter(
                                  color: context.palette.textMuted, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : Builder(builder: (_) {
                        final window = _computeEscalationWindow();
                        final isEmergency =
                            _escalationReason?.startsWith('emergency_') == true;
                        return ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) => _buildBubble(
                            _messages[i],
                            inEscalationWindow: window[i],
                            isEmergency: isEmergency,
                          ),
                        );
                      }),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        SizedBox(
          width: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildGuestLinkSection(),
              _buildModeToggle(),
              if (_mode == 'intervene') _buildResolveButton(),
              if (_mode == 'autopilot' && _escalationReason != null)
                _buildUnresolvedBanner(),
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
                        color: context.palette.textSecondary,
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
                    color: context.palette.textPrimary),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: context.palette.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.palette.border),
                ),
                child: Text(
                  _guestChatUrl!,
                  style: GoogleFonts.inter(
                      fontSize: 11, color: context.palette.textSecondary),
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
                        ? context.palette.success
                        : context.palette.primary,
                    side: BorderSide(
                        color: _copiedLink
                            ? context.palette.success
                            : context.palette.border),
                  ),
                ),
              ),
              if (_copiedLink) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 12, color: context.palette.success),
                    const SizedBox(width: 4),
                    Text(
                      'Link copied to clipboard.',
                      style: GoogleFonts.inter(
                          fontSize: 11, color: context.palette.success),
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
                color: context.palette.textPrimary),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: context.palette.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.palette.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _modeButton(
                    label: 'Autopilot',
                    active: isAutopilot,
                    activeColor: context.palette.primary,
                    onTap: isAutopilot ? null : () => _setMode('autopilot'),
                  ),
                ),
                Expanded(
                  child: _modeButton(
                    label: 'Intervene',
                    active: !isAutopilot,
                    activeColor: context.palette.warning,
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
          color: active ? context.palette.surface : Colors.transparent,
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
            color: active ? activeColor : context.palette.textMuted,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  List<bool> _computeEscalationWindow() {
    final out = List<bool>.filled(_messages.length, false);
    bool inWindow = false;
    for (int i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (!inWindow &&
          m['sender_type'] == 'guest' &&
          i + 1 < _messages.length &&
          _messages[i + 1]['is_escalated_interaction'] == true) {
        inWindow = true;
      }
      if (m['is_escalated_interaction'] == true) inWindow = true;
      out[i] = inWindow;
      if (m['resolution_status'] == 'resolved') inWindow = false;
    }
    return out;
  }

  Widget _buildResolveButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isResolving ? null : _resolveIssue,
          icon: _isResolving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_circle_outline_rounded, size: 18),
          label: Text(_isResolving ? 'Resolving…' : 'Mark Issue as Resolved'),
          style: ElevatedButton.styleFrom(
            backgroundColor: context.palette.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnresolvedBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.palette.warningContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: context.palette.warning.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: context.palette.warning, size: 15),
              const SizedBox(width: 6),
              Text(
                'Open issue',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.palette.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _escalationReason ??
                'Unresolved escalation. Alfred is active but this was not formally resolved.',
            style:
                GoogleFonts.inter(fontSize: 11, color: context.palette.warning),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _isResolving ? null : _resolveIssue,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.palette.warning,
                side: BorderSide(color: context.palette.warning),
                padding: const EdgeInsets.symmetric(vertical: 6),
                textStyle: GoogleFonts.inter(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
              child: _isResolving
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: context.palette.warning))
                  : const Text('Mark as Resolved'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(
    Map<String, dynamic> msg, {
    required bool inEscalationWindow,
    required bool isEmergency,
  }) {
    final senderType = msg['sender_type'] as String;

    if (senderType == 'system') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Text(
            msg['content'] as String,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: context.palette.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    final isGuest = senderType == 'guest';
    final messageType = msg['message_type'] as String? ?? 'text';
    if (messageType == 'image') {
      final publicUrl = Supabase.instance.client.storage
          .from('chat_media')
          .getPublicUrl(msg['media_url'] as String);
      return Align(
        alignment: isGuest ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          constraints: const BoxConstraints(maxWidth: 280),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              publicUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 200,
                height: 80,
                color: context.palette.surfaceAlt,
                child: Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: context.palette.textMuted),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (messageType == 'audio') {
      return _AudioBubble(
        storagePath: msg['media_url'] as String,
        isGuest: isGuest,
      );
    }
    final isHost = senderType == 'host';
    final isEscalated = msg['is_escalated_interaction'] == true;
    final usedLearned = msg['used_learned_knowledge'] == true;

    Color bgColor;
    Color textColor = context.palette.textPrimary;
    BorderRadius radius;
    Border? border;

    if (isGuest) {
      if (inEscalationWindow && isEmergency) {
        bgColor = context.palette.dangerContainer;
        border = Border.all(color: context.palette.danger, width: 1.5);
      } else if (inEscalationWindow) {
        bgColor = context.palette.warningContainer;
        border = Border.all(color: context.palette.warning, width: 1.5);
      } else {
        bgColor = context.palette.primaryContainer;
        border = null;
      }
      radius = const BorderRadius.only(
        topLeft: Radius.circular(14),
        topRight: Radius.circular(14),
        bottomLeft: Radius.circular(14),
        bottomRight: Radius.circular(3),
      );
    } else if (isHost) {
      bgColor = context.palette.surface;
      border = Border.all(color: context.palette.border);
      radius = const BorderRadius.only(
        topLeft: Radius.circular(3),
        topRight: Radius.circular(14),
        bottomLeft: Radius.circular(14),
        bottomRight: Radius.circular(14),
      );
    } else if (isEscalated && isEmergency) {
      bgColor = context.palette.dangerContainer;
      border = Border.all(color: context.palette.danger, width: 1.5);
      radius = BorderRadius.circular(14);
    } else if (isEscalated) {
      bgColor = context.palette.warningContainer;
      border = Border.all(color: context.palette.warning, width: 1.5);
      radius = BorderRadius.circular(14);
    } else {
      bgColor = context.palette.surfaceAlt;
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
            : isEscalated && isEmergency
                ? 'Alfred — EMERGENCY 🚨'
                : isEscalated
                    ? 'Alfred — needs attention'
                    : 'Alfred';

    final senderColor = isGuest
        ? (inEscalationWindow && isEmergency
            ? context.palette.danger
            : inEscalationWindow
                ? context.palette.warning
                : context.palette.primary)
        : isHost
            ? context.palette.textSecondary
            : isEscalated && isEmergency
                ? context.palette.danger
                : isEscalated
                    ? context.palette.warning
                    : context.palette.textMuted;

    final isSending = msg['status'] == 'sending';
    final ts = parseTime(msg['created_at']);
    return Align(
      alignment: isGuest ? Alignment.centerRight : Alignment.centerLeft,
      child: Opacity(
        opacity: isSending ? 0.6 : 1.0,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: radius,
            border: border,
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
              if (!isGuest && !isHost && usedLearned) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.palette.accentContainer,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: context.palette.accent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt_rounded,
                          size: 11, color: context.palette.accent),
                      const SizedBox(width: 4),
                      Text(
                        'Resolved via automated learning',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: context.palette.accent,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                isSending ? 'Sending…' : (ts != null ? relativeTime(ts) : ''),
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: context.palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHostInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.palette.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _hostController,
              decoration: InputDecoration(
                hintText: 'Reply to guest…',
                hintStyle: GoogleFonts.inter(
                    fontSize: 13, color: context.palette.textMuted),
                filled: true,
                fillColor: context.palette.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: context.palette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: context.palette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide:
                      BorderSide(color: context.palette.primary, width: 1.5),
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
              backgroundColor: context.palette.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: context.palette.border,
              disabledForegroundColor: context.palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _AudioBubble extends StatefulWidget {
  final String storagePath;
  final bool isGuest;
  const _AudioBubble({required this.storagePath, required this.isGuest});

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  late final AudioPlayer _player;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playing = state == PlayerState.playing);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
    } else {
      final url = Supabase.instance.client.storage
          .from('chat_media')
          .getPublicUrl(widget.storagePath);
      await _player.play(UrlSource(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.isGuest ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: widget.isGuest
              ? context.palette.primaryContainer
              : context.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: _togglePlay,
              icon: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 22,
              ),
              color: context.palette.primary,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            const SizedBox(width: 6),
            Text(
              'Voice message',
              style: GoogleFonts.inter(
                  fontSize: 13, color: context.palette.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
