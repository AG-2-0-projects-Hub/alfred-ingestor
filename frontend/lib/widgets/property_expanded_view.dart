import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'conversation_pill.dart';
import 'generate_guest_link_dialog.dart';
import '../screens/chat_live_screen.dart';

class PropertyExpandedView extends StatefulWidget {
  final Map<String, dynamic> property;
  final List<Map<String, dynamic>> activeConversations;
  const PropertyExpandedView({
    super.key,
    required this.property,
    required this.activeConversations,
  });

  @override
  State<PropertyExpandedView> createState() => _PropertyExpandedViewState();
}

class _PropertyExpandedViewState extends State<PropertyExpandedView> {
  bool _archivedExpanded = false;
  bool _loadingArchived = false;
  List<Map<String, dynamic>> _archivedConvs = [];

  Future<void> _toggleArchived() async {
    if (_archivedExpanded) {
      setState(() => _archivedExpanded = false);
      return;
    }
    setState(() {
      _archivedExpanded = true;
      _loadingArchived = true;
    });
    // No `is_archived` column exists yet (see Future Backend Work in CONTEXT.md).
    // "Archived" here = past guests for this property whose booking_id is NOT
    // in the active conversations list. Matches the existing
    // ArchivedChatsDialog behavior of querying the `guests` table directly.
    try {
      final activeIds = widget.activeConversations
          .map((c) => c['booking_id'] as String?)
          .whereType<String>()
          .toSet();
      final guests = await Supabase.instance.client
          .from('guests')
          .select('booking_id, name, created_at')
          .eq('property_id', widget.property['id'])
          .order('created_at', ascending: false);
      final archived = [
        for (final g in guests)
          if (!activeIds.contains(g['booking_id']))
            {
              'booking_id': g['booking_id'],
              'guestName': g['name'] ?? 'Guest',
              'mode': 'archived',
              'requires_attention': false,
              'escalation_reason': null,
            }
      ];
      if (mounted) setState(() {
        _archivedConvs = archived;
        _loadingArchived = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _loadingArchived = false;
        _archivedConvs = [];
      });
    }
  }

  void _openChat(String bookingId) {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatLiveScreen(
        bookingId: bookingId,
        propertyId: widget.property['id'] as String,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
            decoration: BoxDecoration(
              color: palette.glassTintStrong,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: palette.glassBorderStrong),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.property['name'] as String? ?? 'Property',
                          style: GoogleFonts.poppins(
                            fontSize: 20, fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Active Conversations',
                    style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (widget.activeConversations.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('No active conversations yet.',
                        style: GoogleFonts.inter(fontSize: 12, color: palette.textMuted),
                      ),
                    )
                  else
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final c in widget.activeConversations)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: ConversationPill(
                                        conv: c, compact: false,
                                        onTap: () => _openChat(c['booking_id'] as String),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _toggleArchived,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(
                            _archivedExpanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 18, color: palette.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text('Archived',
                            style: GoogleFonts.poppins(
                              fontSize: 13, fontWeight: FontWeight.w600,
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_archivedExpanded) ...[
                    if (_loadingArchived)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      )
                    else if (_archivedConvs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('No archived chats.',
                          style: GoogleFonts.inter(fontSize: 11, color: palette.textMuted),
                        ),
                      )
                    else
                      for (final c in _archivedConvs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: ConversationPill(
                            conv: c, compact: false,
                            onTap: () => _openChat(c['booking_id'] as String),
                          ),
                        ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      showDialog(
                        context: context,
                        builder: (_) => GenerateGuestLinkDialog(property: widget.property),
                      );
                    },
                    icon: const Icon(Icons.link_rounded, size: 16),
                    label: const Text('New Guest Link'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
