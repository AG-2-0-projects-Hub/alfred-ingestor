import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:realtime_client/realtime_client.dart' show FilterType;

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
  List<Map<String, dynamic>> _messages = [];
  String _mode = 'autopilot';
  bool _isSending = false;
  final _hostController = TextEditingController();
  final _scrollController = ScrollController();
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadConversation();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _hostController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadConversation() async {
    final result = await Supabase.instance.client
        .from('conversations')
        .select('id, mode')
        .eq('booking_id', widget.bookingId)
        .maybeSingle();
    if (result != null && mounted) {
      setState(() {
        _conversationId = result['id'] as String;
        _mode = result['mode'] as String? ?? 'autopilot';
      });
      _subscribeToMessages(result['id'] as String);
    }
  }

  void _subscribeToMessages(String conversationId) {
    _channel?.unsubscribe();
    _channel = Supabase.instance.client.channel('live:$conversationId');
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: FilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            _reloadMessages(conversationId);
            // Auto-switch to intervene when an escalated AI message arrives
            if (payload.newRecord['is_escalated_interaction'] == true &&
                _mode == 'autopilot') {
              _setMode('intervene');
            }
          },
        )
        .subscribe();
    _reloadMessages(conversationId);
  }

  Future<void> _reloadMessages(String conversationId) async {
    final data = await Supabase.instance.client
        .from('messages')
        .select('sender_type, content, created_at, is_escalated_interaction')
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true);
    if (mounted) {
      setState(() => _messages = List<Map<String, dynamic>>.from(data));
      _scrollToBottom();
    }
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
      final backendUrl = dotenv.env['BACKEND_URL'] ?? 'http://localhost:8000';
      await http.post(
        Uri.parse('$backendUrl/api/messages/host-send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'conversation_id': _conversationId,
          'message': text,
        }),
      );
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
      appBar: AppBar(
        title: Text('Live Chat — ${widget.bookingId}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Left: conversation view ──────────────────────────────────────
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  color: Colors.grey.shade100,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: const Text(
                    'Conversation',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _messages.isEmpty
                      ? const Center(child: Text('No messages yet.'))
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
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
            width: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildModeToggle(),
                const Divider(height: 1),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _mode == 'autopilot'
                            ? 'Alfred is handling this conversation.\n\nSwitch to Intervene to reply manually.'
                            : 'You are in control.\nType below to reply to the guest.',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
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
    );
  }

  Widget _buildModeToggle() {
    final isAutopilot = _mode == 'autopilot';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mode',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _modeButton(
                  label: 'Autopilot',
                  active: isAutopilot,
                  activeColor: Colors.indigo,
                  onTap: isAutopilot ? null : () => _setMode('autopilot'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _modeButton(
                  label: 'Intervene',
                  active: !isAutopilot,
                  activeColor: Colors.orange.shade800,
                  onTap: !isAutopilot ? null : () => _setMode('intervene'),
                ),
              ),
            ],
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
          color: active ? activeColor.withOpacity(0.1) : Colors.transparent,
          border: Border.all(
            color: active ? activeColor : Colors.grey.shade300,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: active ? activeColor : Colors.grey.shade500,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(Map<String, dynamic> msg) {
    final senderType = msg['sender_type'] as String;
    final isGuest = senderType == 'guest';
    final isEscalated = msg['is_escalated_interaction'] == true;

    Color bgColor;
    Color textColor = Colors.black87;
    if (isGuest) {
      bgColor = Colors.indigo.shade50;
    } else if (senderType == 'host') {
      bgColor = Colors.teal.shade50;
    } else if (isEscalated) {
      bgColor = Colors.orange.shade50;
    } else {
      bgColor = Colors.grey.shade100;
    }

    return Align(
      alignment: isGuest ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: isEscalated
              ? Border.all(color: Colors.orange.shade300, width: 1.5)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              senderType == 'guest'
                  ? 'Guest'
                  : senderType == 'host'
                      ? 'You'
                      : isEscalated
                          ? 'Alfred ⚠️'
                          : 'Alfred',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              msg['content'] as String,
              style: TextStyle(fontSize: 14, color: textColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHostInput() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _hostController,
              decoration: InputDecoration(
                hintText: 'Reply to guest...',
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
              onSubmitted: (_) => _sendHostMessage(),
              textInputAction: TextInputAction.send,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _isSending ? null : _sendHostMessage,
            icon: const Icon(Icons.send, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
            ),
          ),
        ],
      ),
    );
  }
}
