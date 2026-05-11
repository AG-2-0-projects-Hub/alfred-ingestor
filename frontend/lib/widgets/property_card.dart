import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

class PropertyCard extends StatelessWidget {
  final Map<String, dynamic> property;
  final VoidCallback onExpand;
  final VoidCallback onGuestLink;
  final VoidCallback onHostChat;
  final VoidCallback onAddProperty;
  final VoidCallback onArchivedChats;
  final VoidCallback onCalendar;
  final int activeChatCount;
  final bool hasEscalation;
  final bool hasEmergency;
  final List<Map<String, dynamic>> conversationPreviews;

  const PropertyCard({
    super.key,
    required this.property,
    required this.onExpand,
    required this.onGuestLink,
    required this.onHostChat,
    required this.onAddProperty,
    this.onArchivedChats = _noop,
    this.onCalendar = _noop,
    this.activeChatCount = 0,
    this.hasEscalation = false,
    this.hasEmergency = false,
    this.conversationPreviews = const [],
  });

  const PropertyCard.add({
    super.key,
    required this.onAddProperty,
  })  : property = const {},
        onExpand = _noop,
        onGuestLink = _noop,
        onHostChat = _noop,
        onArchivedChats = _noop,
        onCalendar = _noop,
        activeChatCount = 0,
        hasEscalation = false,
        hasEmergency = false,
        conversationPreviews = const [];

  static void _noop() {}

  bool get _isAddCard => property.isEmpty;

  @override
  Widget build(BuildContext context) {
    if (_isAddCard) return _AddPropertyCard(onTap: onAddProperty);
    return _PropertyCard(
      property: property,
      activeChatCount: activeChatCount,
      hasEscalation: hasEscalation,
      hasEmergency: hasEmergency,
      conversationPreviews: conversationPreviews,
      onExpand: onExpand,
      onGuestLink: onGuestLink,
      onHostChat: onHostChat,
      onArchivedChats: onArchivedChats,
      onCalendar: onCalendar,
    );
  }
}

// ── Add Property Card ─────────────────────────────────────────────────────
class _AddPropertyCard extends StatefulWidget {
  final VoidCallback onTap;
  const _AddPropertyCard({required this.onTap});

  @override
  State<_AddPropertyCard> createState() => _AddPropertyCardState();
}

class _AddPropertyCardState extends State<_AddPropertyCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: _hovered
                ? AppTheme.primaryContainer
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hovered ? AppTheme.primary : AppTheme.primaryHover,
              width: _hovered ? 1.5 : 1,
              style: BorderStyle.solid,
            ),
            boxShadow: _hovered ? AppTheme.cardShadowHover : [],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _hovered
                      ? AppTheme.primary.withValues(alpha: 0.12)
                      : AppTheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.add_rounded,
                  size: 32,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Add Property',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Connect your Airbnb listing',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Property Card ─────────────────────────────────────────────────────────
class _PropertyCard extends StatefulWidget {
  final Map<String, dynamic> property;
  final int activeChatCount;
  final bool hasEscalation;
  final bool hasEmergency;
  final List<Map<String, dynamic>> conversationPreviews;
  final VoidCallback onExpand;
  final VoidCallback onGuestLink;
  final VoidCallback onHostChat;
  final VoidCallback onArchivedChats;
  final VoidCallback onCalendar;

  const _PropertyCard({
    required this.property,
    required this.activeChatCount,
    required this.hasEscalation,
    required this.hasEmergency,
    required this.conversationPreviews,
    required this.onExpand,
    required this.onGuestLink,
    required this.onHostChat,
    required this.onArchivedChats,
    required this.onCalendar,
  });

  @override
  State<_PropertyCard> createState() => _PropertyCardState();
}

class _PropertyCardState extends State<_PropertyCard> {
  bool _hovered = false;
  bool _pressed = false;

  List<BoxShadow> _statusGlow() {
    if (widget.hasEmergency) {
      return [
        BoxShadow(
          color: AppTheme.danger.withValues(alpha: 0.40),
          blurRadius: 18,
          spreadRadius: 2,
        ),
      ];
    }
    if (widget.hasEscalation) {
      return [
        BoxShadow(
          color: AppTheme.warning.withValues(alpha: 0.35),
          blurRadius: 16,
          spreadRadius: 2,
        ),
      ];
    }
    if (widget.activeChatCount > 0) {
      return [
        BoxShadow(
          color: AppTheme.success.withValues(alpha: 0.25),
          blurRadius: 14,
          spreadRadius: 1,
        ),
      ];
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.property['status'] as String? ?? '';
    final name = widget.property['name'] as String? ?? 'Unnamed';
    final propertyId = widget.property['id'] as String;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onExpand,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          scale: _pressed ? 0.98 : (_hovered ? 1.012 : 1.0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: _hovered ? AppTheme.glassTintStrong : AppTheme.glassTint,
              gradient: AppTheme.glassInnerHighlight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _hovered
                    ? AppTheme.primaryHover.withValues(alpha: 0.5)
                    : AppTheme.glassBorderStrong,
                width: 1,
              ),
              boxShadow: [
                ..._statusGlow(),
                ...(_hovered
                    ? AppTheme.cardShadowHover
                    : AppTheme.cardShadow),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hero image with status badge overlay
              SizedBox(
                height: 160,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _HeroImage(propertyId: propertyId, status: status),
                    // Gradient fade at bottom for text legibility
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      height: 56,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.28),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Status badge top-right
                    Positioned(
                      top: 10,
                      right: 10,
                      child: _StatusBadge(status: status),
                    ),
                    // Active chat indicator bottom-left
                    if (widget.activeChatCount > 0)
                      Positioned(
                        bottom: 8,
                        left: 12,
                        child: _ChatBadge(count: widget.activeChatCount),
                      ),
                  ],
                ),
              ),
              // Card body
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Property name
                      Text(
                        name,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      if (widget.hasEmergency) ...[
                        const SizedBox(height: 6),
                        const _AlertPill(
                          label: 'Emergency',
                          icon: Icons.warning_amber_rounded,
                          bg: AppTheme.dangerContainer,
                          fg: AppTheme.danger,
                        ),
                      ] else if (widget.hasEscalation) ...[
                        const SizedBox(height: 6),
                        const _AlertPill(
                          label: 'Needs Attention',
                          icon: Icons.notifications_active_rounded,
                          bg: AppTheme.warningContainer,
                          fg: AppTheme.warning,
                        ),
                      ],
                      if (widget.conversationPreviews.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _ConversationPreviewList(
                            previews: widget.conversationPreviews),
                      ],
                      const Spacer(),
                      _buildActions(context, status),
                    ],
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

  Widget _buildActions(BuildContext context, String status) {
    final isProcessing = status == 'Ingesting' || status == 'Training';
    final isConflict = status == 'Conflict_Pending';
    final isError = status.contains('Error');
    final isReady = status == 'Trained' ||
        status == 'Active' ||
        status == 'Resolved' ||
        status == 'Merged';

    if (isProcessing) {
      return Row(children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.accent,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Processing…',
          style: GoogleFonts.inter(
              fontSize: 12, color: AppTheme.textSecondary),
        ),
      ]);
    }

    if (isError) {
      return Row(children: [
        const Icon(Icons.error_outline_rounded,
            size: 15, color: AppTheme.danger),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: widget.onExpand,
          child: Text(
            'Re-ingest',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.danger,
            ),
          ),
        ),
      ]);
    }

    if (isConflict) {
      return Row(children: [
        const Icon(Icons.warning_amber_rounded,
            size: 15, color: AppTheme.warning),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: widget.onExpand,
          child: Text(
            'Resolve conflicts',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.warning,
            ),
          ),
        ),
      ]);
    }

    if (isReady) {
      return _ReadyActions(
        onGuestLink: widget.onGuestLink,
        onHostChat: widget.onHostChat,
        onExpand: widget.onExpand,
        onArchivedChats: widget.onArchivedChats,
        onCalendar: widget.onCalendar,
      );
    }

    // Ingested / unknown
    return Align(
      alignment: Alignment.centerRight,
      child: _CardAction(
        icon: Icons.open_in_new_rounded,
        label: 'Details',
        onTap: widget.onExpand,
      ),
    );
  }
}

// ── Ready-state action row ────────────────────────────────────────────────
class _ReadyActions extends StatelessWidget {
  final VoidCallback onGuestLink;
  final VoidCallback onHostChat;
  final VoidCallback onExpand;
  final VoidCallback onArchivedChats;
  final VoidCallback onCalendar;

  const _ReadyActions({
    required this.onGuestLink,
    required this.onHostChat,
    required this.onExpand,
    required this.onArchivedChats,
    required this.onCalendar,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CardAction(
          icon: Icons.link_rounded,
          label: '+ Guest',
          onTap: onGuestLink,
          accent: true,
        ),
        const SizedBox(width: 6),
        _CardAction(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Chats',
          onTap: onHostChat,
        ),
        const Spacer(),
        // Utility icons
        _TinyIconBtn(
          icon: Icons.calendar_month_outlined,
          tooltip: 'Reservations',
          onTap: onCalendar,
        ),
        const SizedBox(width: 4),
        _TinyIconBtn(
          icon: Icons.history_rounded,
          tooltip: 'Chat History',
          onTap: onArchivedChats,
        ),
      ],
    );
  }
}

// ── Individual action button ──────────────────────────────────────────────
class _CardAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  const _CardAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ? AppTheme.accent : AppTheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tiny utility icon button ──────────────────────────────────────────────
class _TinyIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _TinyIconBtn(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 15, color: AppTheme.textMuted),
        ),
      ),
    );
  }
}

// ── Status badge ──────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      'Ingesting' || 'Training' => (
          'Processing',
          AppTheme.accentContainer,
          AppTheme.accent,
        ),
      'Ingested' => (
          'Ingested',
          AppTheme.warningContainer,
          AppTheme.warning,
        ),
      'Merged' || 'Trained' || 'Resolved' => (
          'Ready',
          AppTheme.successContainer,
          AppTheme.success,
        ),
      'Active' => (
          'Active',
          AppTheme.successContainer,
          AppTheme.success,
        ),
      'Conflict_Pending' => (
          'Conflicts',
          AppTheme.warningContainer,
          AppTheme.warning,
        ),
      String s when s.contains('Error') => (
          'Error',
          AppTheme.dangerContainer,
          AppTheme.danger,
        ),
      _ => (
          status.isNotEmpty ? status : 'Unknown',
          AppTheme.surfaceAlt,
          AppTheme.textSecondary,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ── Alert pill (escalation / emergency) ───────────────────────────────────
class _AlertPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;

  const _AlertPill({
    required this.label,
    required this.icon,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: fg,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Active chat count badge ───────────────────────────────────────────────
class _ChatBadge extends StatelessWidget {
  final int count;
  const _ChatBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.success,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, size: 6, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            '$count ${count == 1 ? 'chat' : 'chats'}',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hero image with sky-gradient placeholder ──────────────────────────────
class _HeroImage extends StatefulWidget {
  final String propertyId;
  final String status;
  const _HeroImage({required this.propertyId, required this.status});

  @override
  State<_HeroImage> createState() => _HeroImageState();
}

class _HeroImageState extends State<_HeroImage> {
  String? _url;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  Future<void> _loadUrl() async {
    try {
      final url = await Supabase.instance.client.storage
          .from('Property_assets')
          .createSignedUrl(
              '${widget.propertyId}/hero_image/main.jpg', 3600);
      if (mounted) setState(() => _url = url);
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const ColoredBox(color: AppTheme.primaryContainer);
    }
    if (_url != null) {
      return Image.network(
        _url!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF6366F1), // Electric Indigo
            Color(0xFF0D0D12), // Void Slate
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.home_outlined,
          size: 48,
          color: Colors.white.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

// ── Conversation preview list ─────────────────────────────────────────────
class _ConversationPreviewList extends StatelessWidget {
  final List<Map<String, dynamic>> previews;
  const _ConversationPreviewList({required this.previews});

  @override
  Widget build(BuildContext context) {
    final shown = previews.take(5).toList();
    final overflow = previews.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in shown) _ConvPreviewRow(conv: c),
        if (overflow > 0)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              '+$overflow more',
              style: GoogleFonts.inter(
                  fontSize: 10, color: AppTheme.textMuted),
            ),
          ),
      ],
    );
  }
}

class _ConvPreviewRow extends StatelessWidget {
  final Map<String, dynamic> conv;
  const _ConvPreviewRow({required this.conv});

  Color _dotColor() {
    final reason = conv['escalation_reason'] as String?;
    if (reason != null && reason.startsWith('emergency_')) {
      return AppTheme.danger;
    }
    if (conv['requires_attention'] == true) return AppTheme.warning;
    return AppTheme.success;
  }

  @override
  Widget build(BuildContext context) {
    final guestName = conv['guestName'] as String? ?? 'Guest';
    final isIntervene = conv['mode'] == 'intervene';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _dotColor(),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              guestName,
              style: GoogleFonts.inter(
                  fontSize: 11, color: AppTheme.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isIntervene) ...[
            const SizedBox(width: 4),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Live',
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
