import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:record/record.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/aurora_background.dart';
import '../widgets/glass_panel.dart';
import '../utils/chat_system_messages.dart';

class ChatScreen extends StatefulWidget {
  final String bookingId;
  const ChatScreen({super.key, required this.bookingId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  String? _conversationId;
  String? _propertyName;
  String _hostName = 'the host';
  String _mode = 'autopilot';
  List<Map<String, dynamic>> _messages = [];
  bool _isWaiting = false;
  bool _isRecording = false;
  AudioRecorder? _recorder;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  StreamSubscription<List<Map<String, dynamic>>>? _convSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _modeSubscription;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _recorder = AudioRecorder();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _loadConversation();
    _watchConversation();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _convSubscription?.cancel();
    _modeSubscription?.cancel();
    _pulseCtrl.dispose();
    _recorder?.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadConversation() async {
    final result = await Supabase.instance.client
        .from('conversations')
        .select('id, property_id, mode')
        .eq('booking_id', widget.bookingId)
        .maybeSingle();
    if (result != null && mounted) {
      // Load the official listing name + host name from Master JSON. The merge
      // step builds property_identity with a "dynamic" structure, so the
      // official-name key varies by row (listing_name / property_name / name /
      // property_complex_name). Pull each candidate via PostgREST aliasing and
      // fall back through them, then to the host-chosen nickname (`name`).
      // host_name feeds the guest-side "You are now speaking with [host]" marker.
      final propResult = await Supabase.instance.client
          .from('properties')
          .select(
            'name,'
            'host_name:master_json->host_profile->>name,'
            'pi_listing_name:master_json->property_identity->>listing_name,'
            'pi_property_name:master_json->property_identity->>property_name,'
            'pi_name:master_json->property_identity->>name,'
            'pi_complex_name:master_json->property_identity->>property_complex_name',
          )
          .eq('id', result['property_id'] as String)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _conversationId = result['id'] as String;
          _propertyName = _firstNonEmpty([
            propResult?['pi_listing_name'] as String?,
            propResult?['pi_property_name'] as String?,
            propResult?['pi_name'] as String?,
            propResult?['pi_complex_name'] as String?,
            propResult?['name'] as String?,
          ]);
          final hn = _sanitizeHostName(propResult?['host_name'] as String?);
          if (hn != null) _hostName = hn;
          _mode = (result['mode'] as String?) ?? 'autopilot';
        });
        _subscribeToMessages(result['id'] as String);
      }
    }
  }

  // Returns the first non-empty, trimmed value, or null if none qualify.
  String? _firstNonEmpty(List<String?> candidates) {
    for (final c in candidates) {
      final v = c?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  // Guards against extraction noise leaking into the chat. The merge step can
  // occasionally stuff a whole instruction sentence into host_profile.name
  // (e.g. "Host is Ilse, mention Rogelio at the entrance"). A real host display
  // name is short and rarely sentence-like, so reject overly long values or
  // ones that read like a phrase, falling back to the generic "the host".
  String? _sanitizeHostName(String? raw) {
    final name = raw?.trim();
    if (name == null || name.isEmpty) return null;
    if (name.length > 40) return null;
    // Multiple words plus a comma/sentence punctuation → almost certainly a
    // note, not a name. Allow short multi-word names like "Eduardo Rafael".
    final wordCount = name.split(RegExp(r'\s+')).length;
    if (wordCount > 3) return null;
    if (RegExp(r'[,;:.!?]').hasMatch(name) && wordCount > 1) return null;
    return name;
  }

  void _watchConversation() {
    _convSubscription?.cancel();
    _modeSubscription?.cancel();
    // Stream the conversation row by booking_id. Always update _mode from
    // incoming rows (do NOT early-return once a conversation exists — the
    // host taking over flips mode from 'autopilot' to 'intervene' and the
    // guest must see the banner appear without a refresh).
    _modeSubscription = Supabase.instance.client
        .from('conversations')
        .stream(primaryKey: ['id'])
        .eq('booking_id', widget.bookingId)
        .listen((rows) {
          if (!mounted || rows.isEmpty) return;
          final row = rows.first;
          final newMode = (row['mode'] as String?) ?? 'autopilot';
          if (_mode != newMode) {
            setState(() => _mode = newMode);
          }
          if (_conversationId == null) {
            _loadConversation();
          }
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
            _syncModeFromMessageStream(data);
          }
        });
  }

  // Piggyback on the (reliable) messages stream to keep _mode in sync even
  // when the conversations stream silently drops. Walks backwards from the
  // most recent message; the first "mode-defining" event wins:
  //   - system marker → use its implied mode
  //   - escalated AI message that hasn't been resolved → 'intervene'
  //     (covers the emergency case before the host has interacted at all)
  void _syncModeFromMessageStream(List<Map<String, dynamic>> data) {
    for (int i = data.length - 1; i >= 0; i--) {
      final m = data[i];
      if (m['sender_type'] == 'system') {
        final inferred = ChatSystemMessages.inferModeFromSystemMessage(
          (m['content'] as String?) ?? '',
        );
        if (inferred != null) {
          if (_mode != inferred) setState(() => _mode = inferred);
          return;
        }
        continue;
      }
      if (m['is_escalated_interaction'] == true &&
          m['resolution_status'] != 'resolved') {
        if (_mode != 'intervene') setState(() => _mode = 'intervene');
        return;
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: AppTheme.standardEasing,
        );
      }
    });
  }

  Future<void> _sendMessage({String? overrideText}) async {
    final text = overrideText ?? _controller.text.trim();
    if (text.isEmpty || _isWaiting) return;
    if (overrideText == null) _controller.clear();
    setState(() => _isWaiting = true);

    try {
      await ApiClient.postJson(
        '/api/messages/web-incoming',
        {'booking_id': widget.bookingId, 'message': text},
      );
      if (_conversationId == null) {
        await _loadConversation();
      }
    } on ApiException catch (e) {
      _showApiError(e, retryWith: text);
    } catch (e) {
      _showApiError(
        NetworkException(),
        retryWith: text,
      );
    } finally {
      if (mounted) setState(() => _isWaiting = false);
    }
  }

  void _showApiError(ApiException e, {required String retryWith}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(e.userMessage),
      duration: const Duration(seconds: 8),
      backgroundColor: context.palette.textPrimary,
      action: e.retry
          ? SnackBarAction(
              label: 'Retry',
              textColor: context.palette.accent,
              onPressed: () => _sendMessage(overrideText: retryWith),
            )
          : null,
    ));
  }

  Future<void> _pickAndSendImage() async {
    if (_conversationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Send a text message first to start the conversation.')),
      );
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    final ext = file.extension?.toLowerCase() ?? 'jpg';
    final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';
    final filename = 'img_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final storagePath = '$_conversationId/chat_media/$filename';
    try {
      await Supabase.instance.client.storage
          .from('chat_media')
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: false),
          );
      await Supabase.instance.client.from('messages').insert({
        'conversation_id': _conversationId,
        'sender_type': 'guest',
        'content': '[image]',
        'message_type': 'image',
        'media_url': storagePath,
        'status': 'delivered',
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send image: $e')),
        );
      }
    }
  }

  Future<void> _startRecording() async {
    if (_recorder == null || !await _recorder!.hasPermission()) return;
    await _recorder!.start(const RecordConfig(encoder: AudioEncoder.wav), path: 'recording.wav');
    if (mounted) setState(() => _isRecording = true);
  }

  Future<void> _stopAndSendVoice() async {
    if (_recorder == null) return;
    final path = await _recorder!.stop();
    if (mounted) setState(() => _isRecording = false);
    if (path == null || _conversationId == null) return;
    try {
      final response = await http.get(Uri.parse(path));
      final bytes = response.bodyBytes;
      final filename = 'voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      final storagePath = '$_conversationId/chat_media/$filename';
      await Supabase.instance.client.storage
          .from('chat_media')
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(contentType: 'audio/wav', upsert: false),
          );
      await Supabase.instance.client.from('messages').insert({
        'conversation_id': _conversationId,
        'sender_type': 'guest',
        'content': '[voice message]',
        'message_type': 'audio',
        'media_url': storagePath,
        'status': 'delivered',
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send voice message: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(),
      body: AuroraBackground(
        intensity: 0.45,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: kToolbarHeight + 24),
              if (_mode == 'intervene') _buildInterventionBanner(),
              Expanded(
                child: () {
                  final visible = _dedupeSystemMarkers(_messages);
                  return visible.isEmpty && !_isWaiting
                      ? _buildEmptyState()
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          itemCount: visible.length + (_isWaiting ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == visible.length) {
                              return _buildTypingIndicator();
                            }
                            return _buildBubble(visible[index]);
                          },
                        );
                }(),
              ),
              _buildInputBar(),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: AppBar(
            backgroundColor: context.palette.glassTint,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [context.palette.primary, context.palette.accent],
                    ),
                  ),
                  child: const Icon(Icons.support_agent,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                // When the official listing name is known, lead with it as the
                // header and keep the Alfred identity as a small concierge tag.
                // Falls back to plain "Alfred" branding when no name is loaded.
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: _propertyName != null
                        ? [
                            Text(
                              _propertyName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 16,
                                  height: 1.1,
                                  color: context.palette.textPrimary),
                            ),
                            Text(
                              'Alfred · Concierge',
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: context.palette.primary),
                            ),
                          ]
                        : [
                            Text('Alfred',
                                style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w300,
                                    fontSize: 18,
                                    color: context.palette.primary)),
                          ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInterventionBanner() {
    final amber = context.palette.warning;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: amber.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: amber.withValues(alpha: 0.22),
                  blurRadius: 18,
                  spreadRadius: -2,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) {
                    final t = _pulseCtrl.value;
                    return Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: amber,
                        boxShadow: [
                          BoxShadow(
                            color: amber.withValues(alpha: 0.55 + 0.35 * t),
                            blurRadius: 6 + 6 * t,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'The host is now attending your inquiry',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: context.palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          'Send a message to start the conversation.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
              color: context.palette.textSecondary, fontSize: 14, height: 1.5),
        ),
      ),
    );
  }

  Widget _buildImageBubble(String storagePath, bool isGuest) {
    final publicUrl = Supabase.instance.client.storage
        .from('chat_media')
        .getPublicUrl(storagePath);
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
            loadingBuilder: (_, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: 200,
                height: 150,
                color: context.palette.surfaceAlt,
                child: Center(
                  child: CircularProgressIndicator(color: context.palette.primary),
                ),
              );
            },
            errorBuilder: (_, __, ___) => Container(
              width: 200,
              height: 80,
              color: context.palette.surfaceAlt,
              child: Center(
                child: Icon(Icons.broken_image_outlined, color: context.palette.textMuted),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Collapses runs of consecutive identical system markers into one. A
  // double-submit/retry race (or legacy data) can insert two back-to-back
  // "__SYS_INTERVENE__" rows, which would otherwise render as two identical
  // "You are now speaking with …" lines. Non-system messages always break a run.
  List<Map<String, dynamic>> _dedupeSystemMarkers(
      List<Map<String, dynamic>> messages) {
    final out = <Map<String, dynamic>>[];
    for (final m in messages) {
      if (m['sender_type'] == 'system' && out.isNotEmpty) {
        final prev = out.last;
        if (prev['sender_type'] == 'system' &&
            prev['content'] == m['content']) {
          continue;
        }
      }
      out.add(m);
    }
    return out;
  }

  Widget _buildBubble(Map<String, dynamic> msg) {
    if (msg['sender_type'] == 'system') {
      final text = ChatSystemMessages.formatForGuest(
        msg['content'] as String,
        hostName: _hostName,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: SelectableText(
            text,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: context.palette.textMuted,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final isGuest = msg['sender_type'] == 'guest';
    final messageType = msg['message_type'] as String? ?? 'text';
    if (messageType == 'image') {
      return _buildImageBubble(msg['media_url'] as String, isGuest);
    }
    if (messageType == 'audio') {
      return _AudioBubble(
        storagePath: msg['media_url'] as String,
        isGuest: isGuest,
      );
    }
    final bg = isGuest ? context.palette.primary : context.palette.surface;
    final fg = isGuest ? Colors.white : context.palette.textPrimary;
    return Align(
      alignment: isGuest ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isGuest ? 16 : 4),
            bottomRight: Radius.circular(isGuest ? 4 : 16),
          ),
          border: isGuest ? null : Border.all(color: context.palette.border),
          boxShadow: context.palette.cardShadow,
        ),
        child: SelectableText(
          msg['content'] as String,
          style: GoogleFonts.inter(color: fg, fontSize: 14, height: 1.45),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.palette.surface,
          border: Border.all(color: context.palette.border),
          borderRadius: BorderRadius.circular(16),
          boxShadow: context.palette.cardShadow,
        ),
        child: const _TypingDots(),
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: GlassPanel(
          radius: 28,
          blurSigma: 20,
          tint: context.palette.glassTintStrong,
          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    hintStyle:
                        GoogleFonts.inter(color: context.palette.textMuted, fontSize: 14),
                  ),
                  style: GoogleFonts.inter(fontSize: 14),
                  onSubmitted: (_) => _sendMessage(),
                  textInputAction: TextInputAction.send,
                ),
              ),
              IconButton(
                onPressed: _isWaiting ? null : _pickAndSendImage,
                icon: const Icon(Icons.image_outlined, size: 20),
                color: context.palette.textSecondary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
              IconButton(
                onPressed: _isWaiting
                    ? null
                    : (_isRecording ? _stopAndSendVoice : _startRecording),
                icon: Icon(
                  _isRecording
                      ? Icons.stop_circle_rounded
                      : Icons.mic_none_rounded,
                  size: 20,
                ),
                color: _isRecording ? context.palette.danger : context.palette.textSecondary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: _isWaiting ? null : _sendMessage,
                icon: const Icon(Icons.send, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: context.palette.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: context.palette.border,
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),
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
          color: widget.isGuest ? context.palette.primary : context.palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: widget.isGuest ? null : Border.all(color: context.palette.border),
          boxShadow: context.palette.cardShadow,
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
              color: widget.isGuest ? Colors.white : context.palette.primary,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
            const SizedBox(width: 6),
            Text(
              'Voice message',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: widget.isGuest ? Colors.white : context.palette.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three-dot typing indicator with a 240ms stagger per dot.
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 18,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final phase = ((_ctrl.value - i * 0.18) % 1.0).clamp(0.0, 1.0);
              final opacity = 0.3 + 0.7 * (1 - (phase * 2 - 1).abs());
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.palette.textSecondary
                        .withValues(alpha: opacity),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
