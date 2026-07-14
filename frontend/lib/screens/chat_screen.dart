import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:record/record.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
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
  // Guest messages shown instantly on send, before the realtime stream
  // delivers the persisted row (which then prunes them).
  final List<Map<String, dynamic>> _optimistic = [];
  bool _isWaiting = false;
  bool _isRecording = false;
  // Set when the booking's property has been deleted (guest-token → 410). The
  // chat UI is replaced by a terminal "conversation closed" message.
  bool _conversationClosed = false;
  String _closedMessage =
      'This conversation is no longer active. If you still need help, '
      'please contact your host directly through the platform where you '
      'made your booking.';
  // Guest Supabase client — scoped to this booking's JWT; separate from the
  // global singleton so the host's auth session is never affected.
  SupabaseClient? _guestClient;
  // JWT state — fetched from /api/guest-token on init and re-fetched on expiry.
  String? _guestToken;
  int _guestTokenExpiry = 0; // unix seconds
  AudioRecorder? _recorder;
  AudioEncoder _recordEncoder = AudioEncoder.wav;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  StreamSubscription<List<Map<String, dynamic>>>? _convSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _modeSubscription;
  late final AnimationController _pulseCtrl;

  // Returns the current guest JWT, refreshing it if it has expired or is
  // within 5 minutes of expiry. Called by the SupabaseClient accessToken getter.
  Future<String> _getOrRefreshToken() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (_guestToken != null && _guestTokenExpiry - now > 300) {
      return _guestToken!;
    }
    try {
      final data = await ApiClient.postJson(
        '/api/guest-token',
        {'booking_id': widget.bookingId},
      );
      _guestToken = data['access_token'] as String;
      _guestTokenExpiry = now + (data['expires_in'] as int? ?? 86400);
      // Header identity is resolved server-side — RLS blocks the anon guest
      // from reading the properties table, so it comes back with the token.
      final pn = (data['property_name'] as String?)?.trim();
      final hn = (data['host_name'] as String?)?.trim();
      if (mounted &&
          ((pn != null && pn.isNotEmpty) || (hn != null && hn.isNotEmpty))) {
        setState(() {
          if (pn != null && pn.isNotEmpty) _propertyName = pn;
          if (hn != null && hn.isNotEmpty) _hostName = hn;
        });
      }
      // Keep the realtime socket's auth in sync on refresh so RLS keeps
      // letting the live messages stream through (first authed in bootstrap).
      _guestClient?.realtime.setAuth(_guestToken);
    } on ConversationClosedException {
      // Property deleted — never fall back to a stale token; let the caller
      // flip the UI into the terminal closed state.
      rethrow;
    } catch (_) {
      // If the refresh fails (no network, server down), return the stale
      // token if we have one so the UI stays functional. If we have no token
      // at all, fall through — Supabase calls will get 401s and the chat
      // shows empty state rather than crashing.
      if (_guestToken != null) return _guestToken!;
      rethrow;
    }
    return _guestToken!;
  }

  // Returns the dedicated guest SupabaseClient, creating it on first call.
  // Using a separate client keeps the host's global auth session untouched.
  SupabaseClient get _db {
    _guestClient ??= SupabaseClient(
      dotenv.env['SUPABASE_URL']!,
      dotenv.env['SUPABASE_ANON_KEY']!,
      accessToken: _getOrRefreshToken,
    );
    return _guestClient!;
  }

  @override
  void initState() {
    super.initState();
    _recorder = AudioRecorder();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _bootstrapGuestSession();
  }

  // Fetches the guest JWT, authenticates the realtime socket with it (so RLS
  // lets the live messages stream through — the bare anon key carries no
  // booking_id claim), then loads and watches the conversation.
  Future<void> _bootstrapGuestSession() async {
    try {
      await _getOrRefreshToken();
    } on ConversationClosedException {
      // The property was deleted — show the terminal closed state instead of
      // an empty chat the guest can type into and watch fail. We keep the
      // friendlier frontend copy rather than the terse server detail.
      if (mounted) setState(() => _conversationClosed = true);
      return;
    } catch (_) {
      // Token fetch failed (e.g. server cold-starting). Continue anyway —
      // REST reads just return 0 rows under RLS rather than crashing.
    }
    if (!mounted) return;
    if (_guestToken != null) {
      await _db.realtime.setAuth(_guestToken);
    }
    if (!mounted) return;
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
    _guestClient?.dispose();
    _guestClient = null;
    super.dispose();
  }

  Future<void> _loadConversation() async {
    // The header (property + host name) is already populated from the
    // guest-token response, so we only need the conversation row here.
    final result = await _db
        .from('conversations')
        .select('id, mode')
        .eq('booking_id', widget.bookingId)
        .maybeSingle();
    if (result != null && mounted) {
      setState(() {
        _conversationId = result['id'] as String;
        _mode = (result['mode'] as String?) ?? 'autopilot';
      });
      _subscribeToMessages(result['id'] as String);
    }
  }

  void _watchConversation() {
    _convSubscription?.cancel();
    _modeSubscription?.cancel();
    // Stream the conversation row by booking_id. Always update _mode from
    // incoming rows (do NOT early-return once a conversation exists — the
    // host taking over flips mode from 'autopilot' to 'intervene' and the
    // guest must see the banner appear without a refresh).
    _modeSubscription = _db
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
    _subscription = _db
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .listen((data) {
          if (mounted) {
            setState(() {
              _messages = data;
              _pruneOptimistic(data);
            });
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
    // Optimistically render the guest's own bubble immediately so it never
    // looks like the message was dropped while Alfred is thinking. The realtime
    // messages stream later delivers the persisted row and prunes this entry.
    final optimistic = <String, dynamic>{
      'sender_type': 'guest',
      'content': text,
      'message_type': 'text',
      '_optimistic': true,
    };
    setState(() {
      _isWaiting = true;
      _optimistic.add(optimistic);
    });

    try {
      await ApiClient.postJson(
        '/api/messages/web-incoming',
        {'booking_id': widget.bookingId, 'message': text},
      );
      if (_conversationId == null) {
        await _loadConversation();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _optimistic.remove(optimistic));
      _showApiError(e, retryWith: text);
    } catch (e) {
      if (mounted) setState(() => _optimistic.remove(optimistic));
      _showApiError(
        NetworkException(),
        retryWith: text,
      );
    } finally {
      if (mounted) setState(() => _isWaiting = false);
    }
  }

  // Drops optimistic guest bubbles once the persisted row arrives via the
  // stream, matching on (sender_type=guest, content) to avoid a brief double.
  void _pruneOptimistic(List<Map<String, dynamic>> data) {
    if (_optimistic.isEmpty) return;
    final delivered = data
        .where((m) => m['sender_type'] == 'guest')
        .map((m) => m['content'])
        .toSet();
    _optimistic.removeWhere((o) => delivered.contains(o['content']));
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
      await _loadConversation();
    }
    if (_conversationId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Send a text message first to start the conversation.')),
      );
      return;
    }
    // Several photos are ONE turn — the web equivalent of a Telegram album — so
    // Alfred addresses them together instead of replying once per image.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    final sent = <Map<String, String>>[];
    try {
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null) continue;
        final ext = file.extension?.toLowerCase() ?? 'jpg';
        final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';
        final filename =
            'img_${DateTime.now().microsecondsSinceEpoch}_${sent.length}.$ext';
        final storagePath = '$_conversationId/chat_media/$filename';

        await _db.storage.from('chat_media').uploadBinary(
              storagePath,
              bytes,
              fileOptions: FileOptions(contentType: contentType, upsert: false),
            );
        await _db.from('messages').insert({
          'conversation_id': _conversationId,
          'sender_type': 'guest',
          'content': '[image]',
          'message_type': 'image',
          'media_url': storagePath,
          'status': 'delivered',
        });
        sent.add({'url': storagePath, 'kind': 'image', 'mime': contentType});
      }
      if (sent.isEmpty) return;

      // Ask Alfred to analyze them + respond, in a single turn (skipped
      // server-side if the host has taken over). The reply arrives via the
      // realtime messages stream.
      try {
        await ApiClient.postJson('/api/messages/web-incoming', {
          'booking_id': widget.bookingId,
          'media_items': sent,
        });
      } catch (_) {
        // Non-fatal — the images are delivered; only the auto-reply is missed.
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send image: $e')),
        );
      }
    }
  }

  Future<void> _startRecording() async {
    if (_recorder == null) return;
    if (_conversationId == null) {
      // The conversation already exists — /api/guest-token creates it with the
      // welcome message — so a null id here just means the load hasn't landed.
      // Fetch it rather than telling the guest to go type something first.
      await _loadConversation();
    }
    if (_conversationId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Send a text message first to start the conversation.')),
      );
      return;
    }
    try {
      // Do NOT gate on hasPermission() here. On desktop Chrome and Firefox it
      // reports false while the permission is merely UN-ASKED (state "prompt",
      // not "denied"), so bailing out meant getUserMedia was never called — and
      // getUserMedia is the only thing that makes the browser show its
      // permission dialog. The mic was unreachable on desktop for that reason;
      // it only worked on mobile because permission was already granted there.
      //
      // Starting the recorder performs getUserMedia, which prompts. A genuine
      // denial (or a previously stored block) then surfaces as an exception
      // below, where we can tell the guest how to undo it.
      _recordEncoder = await _recorder!.isEncoderSupported(AudioEncoder.wav)
          ? AudioEncoder.wav  // Gemini reads WAV directly
          : AudioEncoder.opus;
      await _recorder!.start(RecordConfig(encoder: _recordEncoder), path: 'recording');
      if (mounted) setState(() => _isRecording = true);
    } catch (e) {
      if (!mounted) return;
      final err = e.toString().toLowerCase();
      final blocked = err.contains('notallowed') ||
          err.contains('permission') ||
          err.contains('denied');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            blocked
                ? 'Microphone blocked. Open the padlock in your browser\'s address '
                    'bar, set Microphone to "Allow", then reload and try again.'
                : 'Could not start recording: $e',
          ),
        ),
      );
    }
  }

  Future<void> _stopAndSendVoice() async {
    if (_recorder == null) return;
    final path = await _recorder!.stop();
    if (mounted) setState(() => _isRecording = false);
    if (path == null || _conversationId == null) return;
    final isWav = _recordEncoder == AudioEncoder.wav;
    final mime = isWav ? 'audio/wav' : 'audio/ogg';
    final ext = isWav ? 'wav' : 'ogg';
    try {
      final response = await http.get(Uri.parse(path));
      final bytes = response.bodyBytes;
      final filename = 'voice_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final storagePath = '$_conversationId/chat_media/$filename';
      await _db.storage
          .from('chat_media')
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
      await _db.from('messages').insert({
        'conversation_id': _conversationId,
        'sender_type': 'guest',
        'content': '[voice message]',
        'message_type': 'audio',
        'media_url': storagePath,
        'status': 'delivered',
      });
      // Ask Alfred to transcribe + respond (skipped server-side if the host has
      // taken over). The reply arrives via the realtime messages stream.
      try {
        await ApiClient.postJson('/api/messages/web-incoming', {
          'booking_id': widget.bookingId,
          'media_url': storagePath,
          'media_kind': 'audio',
          'media_mime': mime,
        });
      } catch (_) {
        // Non-fatal — the voice note is delivered; only the auto-reply is missed.
      }
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
                child: _conversationClosed
                    ? _buildClosedState()
                    : () {
                  final visible = [
                    ..._dedupeSystemMarkers(_messages),
                    ..._optimistic,
                  ];
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
              if (!_conversationClosed) _buildInputBar(),
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

  // Terminal state shown when the booking's property has been deleted. Replaces
  // the message list + input bar so the guest gets clear guidance instead of a
  // chat that silently fails on send.
  Widget _buildClosedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: GlassPanel(
          radius: 20,
          blurSigma: 18,
          tint: context.palette.glassTint,
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: 40, color: context.palette.textSecondary),
              const SizedBox(height: 16),
              Text(
                'This conversation has ended',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: context.palette.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _closedMessage,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.5,
                  color: context.palette.textSecondary,
                ),
              ),
            ],
          ),
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
