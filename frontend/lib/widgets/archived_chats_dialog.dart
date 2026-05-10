import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../screens/host_panel_screen.dart';

class ArchivedChatsDialog extends StatefulWidget {
  final String propertyId;
  final String propertyName;

  const ArchivedChatsDialog({
    super.key,
    required this.propertyId,
    required this.propertyName,
  });

  @override
  State<ArchivedChatsDialog> createState() => _ArchivedChatsDialogState();
}

class _ArchivedChatsDialogState extends State<ArchivedChatsDialog> {
  List<Map<String, dynamic>> _guests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Supabase.instance.client
          .from('guests')
          .select('id, booking_id, name, created_at, preferred_language')
          .eq('property_id', widget.propertyId)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() => _guests = List<Map<String, dynamic>>.from(data));
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _openChat(Map<String, dynamic> guest) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HostPanelScreen(propertyId: widget.propertyId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: AppTheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.history_rounded,
                        color: AppTheme.primary, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chat History',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          widget.propertyName,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 20, color: AppTheme.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Content
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(
                          color: AppTheme.primary),
                    )
                  : _guests.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(48),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceAlt,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 28,
                                    color: AppTheme.textMuted),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No past chats yet.',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Guest conversations will appear here.',
                                style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _guests.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final g = _guests[i];
                            final name = g['name'] as String? ?? 'Guest';
                            final bookingId =
                                g['booking_id'] as String? ?? '';
                            final date = _formatDate(
                                g['created_at'] as String? ?? '');
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 6),
                              leading: CircleAvatar(
                                radius: 20,
                                backgroundColor: AppTheme.primaryContainer,
                                child: Text(
                                  name.isNotEmpty
                                      ? name[0].toUpperCase()
                                      : '?',
                                  style: GoogleFonts.poppins(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              title: Text(
                                name,
                                style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: AppTheme.textPrimary),
                              ),
                              subtitle: Text(
                                '$bookingId · $date',
                                style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: AppTheme.textSecondary),
                              ),
                              trailing: const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 13,
                                color: AppTheme.textMuted,
                              ),
                              onTap: () => _openChat(g),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
