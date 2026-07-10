import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
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
  bool _saving = false;
  bool _uploading = false;

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
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final row = await _db
          .from('host_profiles')
          .select('display_name, nickname, bio, avatar_url')
          .eq('id', _uid ?? '')
          .maybeSingle();
      if (row != null) {
        _nameController.text = row['display_name'] as String? ?? '';
        _nicknameController.text = row['nickname'] as String? ?? '';
        _bioController.text = row['bio'] as String? ?? '';
        _avatarUrl = row['avatar_url'] as String?;
      }
    } catch (_) {
      // First-time host with no row yet, or a transient read error — start blank.
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
      final backendUrl = dotenv.env['BACKEND_URL'] ?? 'http://localhost:8000';
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload photo: $e')),
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
          SnackBar(content: Text('Failed to save profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: _buildAvatar(palette)),
                    const SizedBox(height: 20),
                    _label('Name', palette),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        hintText: 'Your name',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _label('Nickname', palette),
                    TextField(
                      controller: _nicknameController,
                      decoration: const InputDecoration(
                        hintText: 'What guests should call you',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _label('Short bio', palette),
                    TextField(
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
                    const SizedBox(height: 18),
                    _readOnlyRow(Icons.email_outlined, 'Email',
                        _email.isEmpty ? '—' : _email, palette),
                    const SizedBox(height: 8),
                    _readOnlyRow(Icons.home_work_outlined, 'Registered properties',
                        '${widget.propertyCount}', palette),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_saving || _loading) ? null : _save,
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
        Material(
          color: palette.primary,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _uploading ? null : _pickAvatar,
            child: Padding(
              padding: const EdgeInsets.all(6),
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
