import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

/// In-app beta feedback "chatbox". A host taps the feedback icon, picks an
/// optional type, types anything, and it lands in the `feedback` table (with
/// quiet context: which screen, who, when) for later triage.
///
/// Insert goes direct to Supabase under the `feedback_insert_own` RLS policy —
/// no backend endpoint needed. `host_id` is filled by the table's
/// `default auth.uid()`; we send `host_email` for easy reading.
class FeedbackDialog extends StatefulWidget {
  /// A label for the screen the host was on when they opened this (context for
  /// triage), e.g. 'dashboard'.
  final String? route;

  const FeedbackDialog({super.key, this.route});

  /// Convenience opener.
  static Future<void> show(BuildContext context, {String? route}) {
    return showDialog<void>(
      context: context,
      builder: (_) => FeedbackDialog(route: route),
    );
  }

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackType {
  final String value;
  final String emoji;
  final String label;
  const _FeedbackType(this.value, this.emoji, this.label);
}

const _types = <_FeedbackType>[
  _FeedbackType('bug', '🐛', 'Bug'),
  _FeedbackType('idea', '💡', 'Idea'),
  _FeedbackType('confusing', '😕', 'Confusing'),
  _FeedbackType('other', '💬', 'Other'),
];

class _FeedbackDialogState extends State<FeedbackDialog> {
  final _messageController = TextEditingController();
  String _type = 'other';
  bool _loading = false;
  bool _sent = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;
    setState(() => _loading = true);
    try {
      final email = Supabase.instance.client.auth.currentUser?.email;
      await Supabase.instance.client.from('feedback').insert({
        'type': _type,
        'message': message,
        'route': widget.route,
        'host_email': email,
      });
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Couldn't send feedback: $e"),
            backgroundColor: context.palette.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (_sent) {
      return AlertDialog(
        title: const Text('Thanks — got it ✨'),
        content: Text(
          "Your feedback is in. I'll review it and we'll sort out a fix together.",
          style: GoogleFonts.inter(fontSize: 14, color: palette.textSecondary),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      );
    }

    return AlertDialog(
      insetPadding: isMobile
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 24)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      title: const Text('Send feedback'),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Spotted a bug or have an idea? Tell me anything — it goes straight to the team.',
              style:
                  GoogleFonts.inter(fontSize: 13, color: palette.textSecondary),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _types.map((t) {
                final selected = t.value == _type;
                return ChoiceChip(
                  label: Text('${t.emoji}  ${t.label}'),
                  selected: selected,
                  onSelected:
                      _loading ? null : (_) => setState(() => _type = t.value),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _messageController,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              enabled: !_loading,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'What happened, or what would make this better?',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_loading || _messageController.text.trim().isEmpty)
              ? null
              : _send,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                )
              : const Text('Send'),
        ),
      ],
    );
  }
}
