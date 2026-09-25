import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/auth_screen.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';

/// Host profile menu. Shows and edits the host's display name, nickname, short
/// bio, and avatar (uploaded to the public `host_avatars` bucket). Contact email
/// and the number of registered properties are read-only context.
///
/// Backed by the owner-only `host_profiles` table (RLS: id = auth.uid()). The
/// row is upserted on save — the id defaults to auth.uid() so a first-time host
/// simply creates their row here.
class ProfileDialog extends StatefulWidget {
  /// Registered (non-deleted) property count, passed in from the dashboard so we
  /// don't re-query — it already has this list loaded.
  final int propertyCount;

  const ProfileDialog({super.key, required this.propertyCount});

  static Future<void> show(BuildContext context, {required int propertyCount}) {
    return showDialog<void>(
      context: context,
      // Was dismissible by tapping outside with no unsaved-changes guard — a
      // host who edited name/nickname/bio and tapped outside lost every edit
      // silently, with none of the affordance a labeled Cancel button gives.
      barrierDismissible: false,
      builder: (_) => ProfileDialog(propertyCount: propertyCount),
    );
  }

  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog> {
  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _bioController = TextEditingController();
  String? _avatarUrl;
  bool _loading = true;
  bool _loadError = false;
  bool _saving = false;
  bool _uploading = false;
  bool _deleting = false;

  // Telegram "Connect" (host-escalation alerts + reply-from-Telegram).
  String? _telegramChatId; // non-null once linked
  String? _activeConversationBookingId; // non-null while a Telegram reply is locked to a guest
  String? _telegramLink; // set after generating a connect link this session
  bool _connectingTelegram = false;
  bool _disconnectingTelegram = false;
  Timer? _telegramPollTimer;
  final _tgHelpDockLink = LayerLink();
  OverlayEntry? _tgHelpOverlay;
  final _telegramSectionKey = GlobalKey();

  SupabaseClient get _db => Supabase.instance.client;
  String? get _uid => _db.auth.currentUser?.id;
  String get _email => _db.auth.currentUser?.email ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _bioController.dispose();
    _telegramPollTimer?.cancel();
    _tgHelpOverlay?.remove();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loadError = false);
    try {
      final row = await _db
          .from('host_profiles')
          .select('display_name, nickname, bio, avatar_url, telegram_chat_id, '
              'active_conversation_booking_id')
          .eq('id', _uid ?? '')
          .maybeSingle();
      // row == null here is a clean "no profile row yet" — expected for a
      // first-time host, not an error. Start blank.
      if (row != null) {
        _nameController.text = row['display_name'] as String? ?? '';
        _nicknameController.text = row['nickname'] as String? ?? '';
        _bioController.text = row['bio'] as String? ?? '';
        _avatarUrl = row['avatar_url'] as String?;
        _telegramChatId = row['telegram_chat_id'] as String?;
        _activeConversationBookingId =
            row['active_conversation_booking_id'] as String?;
      }
    } catch (_) {
      // A real failure (network, RLS) is NOT the same as "no row yet" — that
      // distinction matters because this used to render the same blank form
      // either way, and Save would then upsert blanks over any real existing
      // profile data. Surface a retry state instead.
      if (mounted) setState(() => _loadError = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickAvatar() async {
    final uid = _uid;
    if (uid == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    final ext = file.extension?.toLowerCase() ?? 'jpg';
    setState(() => _uploading = true);
    try {
      // Brokered through the backend (service role): the Flutter web client
      // can't satisfy the host_avatars storage RLS write policy directly, so the
      // backend validates the host token and writes under the host's uid folder.
      final backendUrl = ApiClient.backendUrl;
      final token = _db.auth.currentSession?.accessToken;
      final req = http.MultipartRequest(
        'POST', Uri.parse('$backendUrl/api/host/avatar'),
      );
      if (token != null) req.headers['Authorization'] = 'Bearer $token';
      req.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: 'avatar.$ext'),
      );
      final resp = await http.Response.fromStream(await req.send());
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (mounted) setState(() => _avatarUrl = data['url'] as String?);
      } else {
        throw Exception('${resp.statusCode}: ${resp.body}');
      }
    } on ConfigurationException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.userMessage)),
        );
      }
    } catch (e) {
      // Matches _confirmDeleteAccount's friendly-message pattern below,
      // instead of interpolating the raw exception into the SnackBar.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload photo. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      await _db.from('host_profiles').upsert({
        'id': uid,
        'display_name': _nameController.text.trim(),
        'nickname': _nicknameController.text.trim(),
        'bio': _bioController.text.trim(),
        'avatar_url': _avatarUrl,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save profile. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied!'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _connectTelegram() async {
    setState(() => _connectingTelegram = true);
    try {
      final token = _db.auth.currentSession?.accessToken;
      final data = await ApiClient.postJson(
        '/api/host/telegram/link-code', const {}, bearer: token,
      );
      if (mounted) {
        setState(() => _telegramLink = data['telegram_link'] as String?);
        // The QR/link section pushes the dialog's content past its visible
        // height -- without this, the host has no obvious affordance telling
        // them to scroll, and the new content (link text, copy button, even
        // Delete account below it) silently sits below the fold.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _telegramSectionKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(ctx,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                alignment: 1.0);
          }
        });
      }
      // The host taps the link/QR on their phone and it links server-side —
      // this dialog has no other way to know that happened, so poll the
      // owner-scoped RLS row every few seconds and flip to "Connected" the
      // moment it lands. Capped at 10 minutes, matching the code's own expiry.
      _telegramPollTimer?.cancel();
      var elapsed = Duration.zero;
      const interval = Duration(seconds: 3);
      const cap = Duration(minutes: 10);
      _telegramPollTimer = Timer.periodic(interval, (timer) async {
        elapsed += interval;
        if (elapsed >= cap) {
          timer.cancel();
          return;
        }
        final row = await _db
            .from('host_profiles')
            .select('telegram_chat_id')
            .eq('id', _uid ?? '')
            .maybeSingle();
        final chatId = row?['telegram_chat_id'] as String?;
        if (chatId != null && mounted) {
          timer.cancel();
          setState(() {
            _telegramChatId = chatId;
            _telegramLink = null;
          });
        }
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.userMessage), backgroundColor: context.palette.danger),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: const Text('Could not generate a connection link. Please try again.'),
              backgroundColor: context.palette.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _connectingTelegram = false);
    }
  }

  Future<void> _confirmDisconnectTelegram() async {
    final hasActive = _activeConversationBookingId != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Disconnect Telegram?'),
        content: Text(
          hasActive
              ? "You'll stop getting guest alerts here. You currently have "
                'an active Telegram conversation — reply from the dashboard '
                'instead after disconnecting.'
              : "You'll stop getting guest alerts here. You can reconnect "
                'anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _disconnectTelegram();
  }

  Future<void> _disconnectTelegram() async {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _disconnectingTelegram = true);
    try {
      // Same RLS-scoped direct-write pattern as _save() -- host_profiles'
      // update policy is row-level only (id = auth.uid()), no column
      // restriction, so this needs no backend endpoint (unlike Connect,
      // which mints a server-only secret code).
      await _db.from('host_profiles').update({
        'telegram_chat_id': null,
        'active_conversation_booking_id': null,
      }).eq('id', uid);
      if (mounted) {
        setState(() {
          _telegramChatId = null;
          _activeConversationBookingId = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not disconnect Telegram. Please try again.'),
            backgroundColor: context.palette.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _disconnectingTelegram = false);
    }
  }

  static const List<List<String>> _telegramHelpLines = [
    ['When a guest needs you, you\'ll get an alert here with their message, '
        'Alfred\'s draft, and a ', 'Mark Resolved', ' button.'],
    ['Just ', 'type to reply', ' — it goes straight to that guest, no need '
        'to tap anything first.'],
    ['Multiple guests waiting at once? You\'ll see a ', 'list', ' to pick '
        'from. Or you can also ', 'reply directly', ' to a specific guest\'s ',
        'alert message', ' to jump straight to them.'],
    ['Send ', '/switch', ' anytime to bring that list back up.'],
    ['Tap ', 'Mark Resolved', ' when you\'re done — Alfred takes back over '
        'and the guest is notified.'],
  ];

  /// Odd-indexed entries in each row are the bold spans (the pattern reads
  /// as plain/bold/plain/bold/... starting with plain).
  List<InlineSpan> _telegramHelpSpans(List<String> parts, AppPalette palette) {
    return [
      for (var i = 0; i < parts.length; i++)
        TextSpan(
          text: parts[i],
          style: i.isOdd
              ? TextStyle(fontWeight: FontWeight.w700, color: palette.textPrimary)
              : null,
        ),
    ];
  }

  void _toggleTelegramHelp() {
    if (_tgHelpOverlay != null) {
      _tgHelpOverlay?.remove();
      _tgHelpOverlay = null;
      return;
    }
    final screenW = MediaQuery.sizeOf(context).width;
    if (screenW < 900) {
      // Not enough room to dock a side panel without it overflowing the
      // viewport — a plain centered dialog reads fine on a narrow screen.
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('How Telegram replies work'),
          content: SizedBox(
            width: 360,
            child: _buildTelegramHelpBody(context.palette),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
      return;
    }

    final entry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        width: 340,
        child: CompositedTransformFollower(
          link: _tgHelpDockLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topRight,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(12, -12),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.palette.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.palette.border),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 24, offset: Offset(0, 8)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'How Telegram replies work',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: context.palette.textPrimary,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: _toggleTelegramHelp,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(Icons.close_rounded,
                              size: 16, color: context.palette.textMuted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildTelegramHelpBody(context.palette),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    _tgHelpOverlay = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  Widget _buildTelegramHelpBody(AppPalette palette) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in _telegramHelpLines) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ',
                  style: GoogleFonts.inter(fontSize: 12, color: palette.textSecondary)),
              Expanded(
                child: Text.rich(
                  TextSpan(children: _telegramHelpSpans(line, palette)),
                  style: GoogleFonts.inter(
                      fontSize: 12, height: 1.5, color: palette.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildTelegramSection(AppPalette palette) {
    if (_telegramChatId != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 16, color: palette.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Telegram connected — you'll get an alert there when a guest "
                  'needs you.',
                  style: GoogleFonts.inter(fontSize: 12, color: palette.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _disconnectingTelegram ? null : _confirmDisconnectTelegram,
              child: Text(
                _disconnectingTelegram ? 'Disconnecting…' : 'Disconnect',
                style: TextStyle(fontSize: 12, color: palette.danger),
              ),
            ),
          ),
        ],
      );
    }

    if (_telegramLink != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Open this link on your phone, or scan the QR code, then tap '
            'Start in Telegram.',
            style: GoogleFonts.inter(fontSize: 12, color: palette.textSecondary),
          ),
          const SizedBox(height: 10),
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: QrImageView(data: _telegramLink!, size: 140),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  _telegramLink!,
                  style: GoogleFonts.robotoMono(
                    fontSize: 12,
                    color: palette.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18),
                tooltip: 'Copy',
                onPressed: () => _copy(_telegramLink!),
              ),
            ],
          ),
        ],
      );
    }

    return OutlinedButton.icon(
      onPressed: _connectingTelegram ? null : _connectTelegram,
      icon: const Icon(Icons.send_rounded, size: 16),
      label: Text(_connectingTelegram ? 'Generating…' : 'Connect Telegram'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return AlertDialog(
      backgroundColor: palette.surface,
      insetPadding: isMobile
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 24)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      title: const Text('Your profile'),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 400,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            : _loadError
                ? _buildLoadError(palette)
                : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: _buildAvatar(palette)),
                    const SizedBox(height: 20),
                    _label('Name', palette),
                    // Semantics wraps here associate the visible label above
                    // with the field for a screen reader -- previously only
                    // the (non-semantic) hintText and a separate Text widget
                    // existed, with no programmatic link between them.
                    Semantics(
                      label: 'Name',
                      child: TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          hintText: 'Your name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _label('Nickname', palette),
                    Semantics(
                      label: 'Nickname',
                      child: TextField(
                        controller: _nicknameController,
                        decoration: const InputDecoration(
                          hintText: 'What guests should call you',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _label('Short bio', palette),
                    Semantics(
                      label: 'Short bio',
                      child: TextField(
                        controller: _bioController,
                        minLines: 2,
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: 'A sentence or two about you',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _readOnlyRow(Icons.email_outlined, 'Email',
                        _email.isEmpty ? '—' : _email, palette),
                    const SizedBox(height: 8),
                    _readOnlyRow(Icons.home_work_outlined, 'Registered properties',
                        '${widget.propertyCount}', palette),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(child: _label('Telegram alerts', palette)),
                        CompositedTransformTarget(
                          link: _tgHelpDockLink,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: _toggleTelegramHelp,
                            child: const Text('How to use', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      key: _telegramSectionKey,
                      child: _buildTelegramSection(palette),
                    ),
                    const SizedBox(height: 28),
                    const Divider(),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _deleting ? null : _confirmDeleteAccount,
                      icon: Icon(Icons.delete_forever_outlined,
                          size: 16, color: palette.danger),
                      label: Text(
                        _deleting ? 'Deleting…' : 'Delete account',
                        style: TextStyle(color: palette.danger),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.danger,
                        side: BorderSide(
                            color: palette.danger.withValues(alpha: 0.5)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Permanently deletes your account and all your property '
                      'data.',
                      style: TextStyle(
                          fontSize: 11, color: palette.textMuted),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: (_saving || _deleting) ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // _uploading added: without it, Save could commit while an avatar
          // upload was still in flight, persisting a profile that doesn't
          // reflect the photo the host just picked. _loadError added: don't
          // let a failed load's blank fields overwrite real existing data.
          onPressed: (_saving || _loading || _deleting || _uploading || _loadError)
              ? null
              : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  /// Irreversible and it takes the guest conversations' owner with it, so a
  /// two-tap red button (the pattern used for deleting a single property) is not
  /// enough here — the host types the word out. This is the only typed
  /// confirmation in the app, and deliberately so.
  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAccountConfirmDialog(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      final token = _db.auth.currentSession?.accessToken;
      await ApiClient.postJson('/api/host/delete-account', const {}, bearer: token);

      // The account is gone — the session is now a token for a user who doesn't
      // exist. Tear it down and go back to sign-in, past every dashboard route.
      await _db.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      final msg = e is ApiException ? e.userMessage : '$e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: context.palette.danger,
          content: Text('Could not delete your account: $msg'),
        ),
      );
    }
  }

  Widget _buildLoadError(AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 32, color: palette.danger),
          const SizedBox(height: 12),
          Text(
            "Couldn't load your profile.",
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Check your connection and try again.',
            style: GoogleFonts.inter(fontSize: 12, color: palette.textMuted),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(AppPalette palette) {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        CircleAvatar(
          radius: 44,
          backgroundColor: palette.primaryContainer,
          backgroundImage:
              (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                  ? NetworkImage(_avatarUrl!)
                  : null,
          child: (_avatarUrl == null || _avatarUrl!.isEmpty)
              ? Icon(Icons.person_rounded, size: 44, color: palette.primary)
              : null,
        ),
        // The visual badge stays small (~28px) — only the tap target grows,
        // to the ~44px minimum touch-target guidance. Previously they were
        // the same size, at the corner of a larger avatar where mis-taps
        // were easy.
        SizedBox(
          width: 40,
          height: 40,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _uploading ? null : _pickAvatar,
              child: Center(
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                      color: palette.primary, shape: BoxShape.circle),
                  child: Center(
                    child: _uploading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.camera_alt_rounded,
                            size: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _label(String text, AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: palette.textSecondary,
        ),
      ),
    );
  }

  Widget _readOnlyRow(
      IconData icon, String label, String value, AppPalette palette) {
    return Row(
      children: [
        Icon(icon, size: 16, color: palette.textMuted),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: GoogleFonts.inter(fontSize: 12, color: palette.textMuted),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: palette.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Typed confirmation for account deletion. States what is destroyed, and asks
/// the host to type the word out. What happens to past conversations is covered
/// by the ToS they accepted at sign-up — repeating it here only invites doubt at
/// the worst moment, so it is deliberately not mentioned.
class _DeleteAccountConfirmDialog extends StatefulWidget {
  const _DeleteAccountConfirmDialog();

  @override
  State<_DeleteAccountConfirmDialog> createState() =>
      _DeleteAccountConfirmDialogState();
}

class _DeleteAccountConfirmDialogState
    extends State<_DeleteAccountConfirmDialog> {
  static const _phrase = 'DELETE';
  final _controller = TextEditingController();
  bool _matches = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final ok = _controller.text.trim().toUpperCase() == _phrase;
      if (ok != _matches) setState(() => _matches = ok);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      backgroundColor: palette.surface,
      title: Row(children: [
        Icon(Icons.warning_amber_rounded, color: palette.danger),
        const SizedBox(width: 8),
        const Flexible(child: Text('Delete account')),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This cannot be undone.',
            style: GoogleFonts.inter(
                fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _bullet('Your account and login are permanently removed.'),
          _bullet('All your properties and their training data are deleted.'),
          _bullet('Your profile and avatar are deleted.'),
          const SizedBox(height: 18),
          Text(
            'Type $_phrase to confirm',
            style: GoogleFonts.inter(
                fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              hintText: _phrase,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              _matches ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: palette.danger,
            disabledBackgroundColor: palette.border,
          ),
          child: const Text('Delete my account'),
        ),
      ],
    );
  }

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•  '),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.inter(fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ),
      );
}
