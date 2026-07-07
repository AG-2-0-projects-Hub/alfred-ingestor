import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'chat_live_dialog.dart';

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
      // Chat History = archived conversations (auto-archived once the
      // reservation ended, or manually archived by the host). Active ones live
      // on the dashboard. Joined to the guest for name + booking display.
      final data = await Supabase.instance.client
          .from('conversations')
          .select('booking_id, archived_at, guests(name, created_at)')
          .eq('property_id', widget.propertyId)
          .not('archived_at', 'is', null)
          .order('archived_at', ascending: false);
      final guests = [
        for (final c in data)
          {
            'booking_id': c['booking_id'],
            'name': (c['guests'] as Map?)?['name'] ?? 'Guest',
            'created_at': c['archived_at'],
          }
      ];
      if (mounted) {
        setState(() => _guests = List<Map<String, dynamic>>.from(guests));
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _openChat(Map<String, dynamic> guest) {
    final bookingId = guest['booking_id'] as String? ?? '';
    if (bookingId.isEmpty) return;
    // Open the tapped past conversation in the same consolidated (and
    // mobile-responsive) ChatLiveDialog every other entry point uses, stacked
    // on top of this history list so closing it returns here — instead of the
    // old full-page HostPanelScreen → ChatLiveScreen (crushed on mobile).
    ChatLiveDialog.show(
      context,
      bookingId: bookingId,
      propertyId: widget.propertyId,
      propertyName: widget.propertyName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 600;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: context.palette.surface,
      insetPadding: isMobile
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 24)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
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
                      color: context.palette.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.history_rounded,
                        color: context.palette.primary, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chat History',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                            color: context.palette.textPrimary,
                          ),
                        ),
                        Text(
                          widget.propertyName,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: context.palette.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        size: 20, color: context.palette.textMuted),
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
                      child: CircularProgressIndicator(),
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
                                  color: context.palette.surfaceAlt,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 28,
                                    color: context.palette.textMuted),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No past chats yet.',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: context.palette.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Guest conversations will appear here.',
                                style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: context.palette.textSecondary),
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
                                backgroundColor: context.palette.primaryContainer,
                                child: Text(
                                  name.isNotEmpty
                                      ? name[0].toUpperCase()
                                      : '?',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: context.palette.primary,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              title: Text(
                                name,
                                style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: context.palette.textPrimary),
                              ),
                              subtitle: Text(
                                '$bookingId · $date',
                                style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: context.palette.textSecondary),
                              ),
                              trailing: Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 13,
                                color: context.palette.textMuted,
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
