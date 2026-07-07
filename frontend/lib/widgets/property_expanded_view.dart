import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'conversation_pill.dart';
import 'generate_guest_link_dialog.dart';
import 'chat_live_dialog.dart';

class PropertyExpandedView extends StatefulWidget {
  final Map<String, dynamic> property;
  final List<Map<String, dynamic>> activeConversations;
  // Forwarded to ChatLiveDialog so the dashboard can refresh optimistically
  // when the host resolves an escalation from inside this expanded view.
  final VoidCallback? onChatResolved;
  const PropertyExpandedView({
    super.key,
    required this.property,
    required this.activeConversations,
    this.onChatResolved,
  });

  @override
  State<PropertyExpandedView> createState() => _PropertyExpandedViewState();
}

class _PropertyExpandedViewState extends State<PropertyExpandedView> {
  bool _archivedExpanded = false;
  bool _loadingArchived = false;
  List<Map<String, dynamic>> _archivedConvs = [];

  late List<Map<String, dynamic>> _activeConversations;
  StreamSubscription<List<Map<String, dynamic>>>? _convStream;
  Map<String, String> _guestNamesByBooking = {};

  @override
  void initState() {
    super.initState();
    _activeConversations =
        List<Map<String, dynamic>>.from(widget.activeConversations);
    for (final c in _activeConversations) {
      final bid = c['booking_id'] as String?;
      final name = c['guestName'] as String?;
      if (bid != null && name != null) {
        _guestNamesByBooking[bid] = name;
      }
    }
    _subscribeConversations();
  }

  @override
  void dispose() {
    _convStream?.cancel();
    super.dispose();
  }

  void _subscribeConversations() {
    _convStream = Supabase.instance.client
        .from('conversations')
        .stream(primaryKey: ['id'])
        .eq('property_id', widget.property['id'] as String)
        .listen((rows) {
          if (mounted) _applyConversations(rows);
        });
  }

  // One-shot fetch used after a host action (e.g. resolve) when we can't
  // afford to wait for the stream to fire. Same merge/sort logic as the
  // stream listener, so the UI state stays consistent across both paths.
  Future<void> _refreshLocalConversations() async {
    try {
      final rows = await Supabase.instance.client
          .from('conversations')
          .select()
          .eq('property_id', widget.property['id'] as String);
      if (mounted) _applyConversations(List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      // Silent — the stream + parent dashboard refresh will fill in eventually.
    }
  }

  void _applyConversations(List<Map<String, dynamic>> rows) {
    final merged = <Map<String, dynamic>>[
      for (final c in rows)
        <String, dynamic>{
          ...c,
          'guestName':
              _guestNamesByBooking[c['booking_id'] as String? ?? ''] ?? 'Guest',
        }
    ];
    merged.sort((a, b) {
      int priority(Map<String, dynamic> x) {
        final reason = x['escalation_reason'] as String?;
        if (reason != null && reason.startsWith('emergency_')) return 0;
        if (x['requires_attention'] == true) return 1;
        if (x['mode'] == 'intervene') return 2;
        if (x['has_guest_message'] != true) return 4; // pending — awaiting reply, last
        return 3;
      }
      return priority(a).compareTo(priority(b));
    });
    setState(() => _activeConversations = merged);
  }

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
      final activeIds = _activeConversations
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
    ChatLiveDialog.show(
      context,
      bookingId: bookingId,
      propertyId: widget.property['id'] as String,
      propertyName: widget.property['name'] as String? ?? '',
      onResolved: () {
        // Refresh the popup's own pill list immediately so the resolved
        // conversation visibly drops out of the emergency colour band,
        // then forward to the parent (dashboard) for its own refresh.
        _refreshLocalConversations();
        widget.onChatResolved?.call();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 600;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: isMobile
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 32)
          : const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
            decoration: BoxDecoration(
              color: palette.glassTintStrong,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: palette.glassBorderStrong),
            ),
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 16 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.property['name'] as String? ?? 'Property',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 20, fontWeight: FontWeight.w300,
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
                  Text('Conversations',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_activeConversations.isEmpty)
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
                            for (final c in _activeConversations)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: ConversationPill(
                                        conv: c, compact: false,
                                        pending: c['has_guest_message'] != true,
                                        showPendingLabel: true,
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
                            style: GoogleFonts.plusJakartaSans(
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
