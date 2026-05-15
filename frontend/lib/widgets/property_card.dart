import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'conversation_pill.dart';

class PropertyCard extends StatelessWidget {
  final Map<String, dynamic> property;
  final void Function(String bookingId) onOpenChat;
  final VoidCallback onOpenExpanded;
  final VoidCallback onOpenSettings;
  final VoidCallback onGuestLink;
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
    required this.onOpenChat,
    required this.onOpenExpanded,
    required this.onOpenSettings,
    required this.onGuestLink,
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
        onOpenChat = _noopChat,
        onOpenExpanded = _noop,
        onOpenSettings = _noop,
        onGuestLink = _noop,
        onArchivedChats = _noop,
        onCalendar = _noop,
        activeChatCount = 0,
        hasEscalation = false,
        hasEmergency = false,
        conversationPreviews = const [];

  static void _noop() {}
  static void _noopChat(String _) {}

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
      onOpenChat: onOpenChat,
      onOpenExpanded: onOpenExpanded,
      onOpenSettings: onOpenSettings,
      onGuestLink: onGuestLink,
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
    final palette = context.palette;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: _hovered ? palette.primaryContainer : palette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered ? palette.primary : palette.primaryHover,
              width: _hovered ? 1.5 : 1,
              style: BorderStyle.solid,
            ),
            boxShadow: _hovered ? palette.cardShadowHover : [],
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
                      ? palette.primary.withValues(alpha: 0.12)
                      : palette.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.add_rounded,
                  size: 32,
                  color: palette.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Add Property',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: palette.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Connect your Airbnb listing',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: palette.textMuted,
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
  final void Function(String bookingId) onOpenChat;
  final VoidCallback onOpenExpanded;
  final VoidCallback onOpenSettings;
  final VoidCallback onGuestLink;
  final VoidCallback onArchivedChats;
  final VoidCallback onCalendar;

  const _PropertyCard({
    required this.property,
    required this.activeChatCount,
    required this.hasEscalation,
    required this.hasEmergency,
    required this.conversationPreviews,
    required this.onOpenChat,
    required this.onOpenExpanded,
    required this.onOpenSettings,
    required this.onGuestLink,
    required this.onArchivedChats,
    required this.onCalendar,
  });

  @override
  State<_PropertyCard> createState() => _PropertyCardState();
}

class _PropertyCardState extends State<_PropertyCard> {
  bool _hovered = false;
  bool _pressed = false;

  List<BoxShadow> _statusGlow(AppPalette p) {
    if (widget.hasEmergency) {
      return [
        BoxShadow(
          color: p.danger.withValues(alpha: 0.40),
          blurRadius: 18,
          spreadRadius: 2,
        ),
      ];
    }
    if (widget.hasEscalation) {
      return [
        BoxShadow(
          color: p.warning.withValues(alpha: 0.35),
          blurRadius: 16,
          spreadRadius: 2,
        ),
      ];
    }
    if (widget.activeChatCount > 0) {
      return [
        BoxShadow(
          color: p.success.withValues(alpha: 0.25),
          blurRadius: 14,
          spreadRadius: 1,
        ),
      ];
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final status = widget.property['status'] as String? ?? '';
    final name = widget.property['name'] as String? ?? 'Unnamed';
    final propertyId = widget.property['id'] as String;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onOpenExpanded,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 200),
          curve: AppTheme.standardEasing,
          scale: _pressed ? AppTheme.pressScale : (_hovered ? 1.012 : 1.0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: _hovered ? palette.glassTintStrong : palette.glassTint,
              gradient: AppTheme.glassInnerHighlight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _hovered
                    ? palette.primaryHover.withValues(alpha: 0.5)
                    : palette.glassBorderStrong,
                width: 1,
              ),
              boxShadow: [
                ..._statusGlow(palette),
                ...(_hovered ? palette.cardShadowHover : palette.cardShadow),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 160,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _HeroImage(propertyId: propertyId, status: status),
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
                      Positioned(
                        top: 10,
                        right: 10,
                        child: _StatusBadge(status: status),
                      ),
                      if (widget.activeChatCount > 0)
                        Positioned(
                          bottom: 8,
                          left: 12,
                          child: _ChatBadge(count: widget.activeChatCount),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: palette.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        if (widget.hasEmergency) ...[
                          const SizedBox(height: 6),
                          _AlertPill(
                            label: 'Emergency',
                            icon: Icons.warning_amber_rounded,
                            bg: palette.dangerContainer,
                            fg: palette.danger,
                          ),
                        ] else if (widget.hasEscalation) ...[
                          const SizedBox(height: 6),
                          _AlertPill(
                            label: 'Needs Attention',
                            icon: Icons.notifications_active_rounded,
                            bg: palette.warningContainer,
                            fg: palette.warning,
                          ),
                        ],
                        if (widget.conversationPreviews.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Expanded(
                            child: _PillPreviewList(
                              previews: widget.conversationPreviews,
                              onOpenChat: widget.onOpenChat,
                              onOpenAll: widget.onOpenExpanded,
                            ),
                          ),
                        ] else
                          const Spacer(),
                        _buildActions(context, status, palette),
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

  Widget _buildActions(BuildContext context, String status, AppPalette palette) {
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
            color: palette.accent,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Processing…',
          style: GoogleFonts.inter(
              fontSize: 12, color: palette.textSecondary),
        ),
      ]);
    }

    if (isError) {
      return Row(children: [
        Icon(Icons.error_outline_rounded, size: 15, color: palette.danger),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: widget.onOpenSettings,
          child: Text(
            'Re-ingest',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.danger,
            ),
          ),
        ),
      ]);
    }

    if (isConflict) {
      return Row(children: [
        Icon(Icons.warning_amber_rounded, size: 15, color: palette.warning),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: widget.onOpenSettings,
          child: Text(
            'Resolve conflicts',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.warning,
            ),
          ),
        ),
      ]);
    }

    if (isReady) {
      return _ReadyActions(
        onGuestLink: widget.onGuestLink,
        onOpenSettings: widget.onOpenSettings,
        onArchivedChats: widget.onArchivedChats,
        onCalendar: widget.onCalendar,
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: _CardAction(
        icon: Icons.open_in_new_rounded,
        label: 'Details',
        onTap: widget.onOpenSettings,
      ),
    );
  }
}

// ── Ready-state action row ────────────────────────────────────────────────
class _ReadyActions extends StatelessWidget {
  final VoidCallback onGuestLink;
  final VoidCallback onOpenSettings;
  final VoidCallback onArchivedChats;
  final VoidCallback onCalendar;

  const _ReadyActions({
    required this.onGuestLink,
    required this.onOpenSettings,
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
          icon: Icons.settings_rounded,
          label: 'Settings',
          onTap: onOpenSettings,
        ),
        const Spacer(),
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
    final palette = context.palette;
    final color = accent ? palette.accent : palette.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 15, color: context.palette.textMuted),
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
    final p = context.palette;
    final (label, bg, fg) = switch (status) {
      'Ingesting' || 'Training' => ('Processing', p.accentContainer, p.accent),
      'Ingested' => ('Ingested', p.warningContainer, p.warning),
      'Merged' || 'Trained' || 'Resolved' => ('Ready', p.successContainer, p.success),
      'Active' => ('Active', p.successContainer, p.success),
      'Conflict_Pending' => ('Conflicts', p.warningContainer, p.warning),
      String s when s.contains('Error') => ('Error', p.dangerContainer, p.danger),
      _ => (
          status.isNotEmpty ? status : 'Unknown',
          p.surfaceAlt,
          p.textSecondary,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
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
          borderRadius: BorderRadius.circular(100),
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
        color: context.palette.success,
        borderRadius: BorderRadius.circular(100),
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

// ── Hero image with gradient placeholder ──────────────────────────────────
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
    final palette = context.palette;
    if (!_loaded) {
      return ColoredBox(color: palette.primaryContainer);
    }
    if (_url != null) {
      return Image.network(
        _url!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _placeholder(palette),
      );
    }
    return _placeholder(palette);
  }

  Widget _placeholder(AppPalette palette) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.primary,
            palette.background,
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

// ── Pill preview list (replaces _ConversationPreviewList) ─────────────────
class _PillPreviewList extends StatelessWidget {
  final List<Map<String, dynamic>> previews;
  final void Function(String bookingId) onOpenChat;
  final VoidCallback onOpenAll;
  const _PillPreviewList({
    required this.previews,
    required this.onOpenChat,
    required this.onOpenAll,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      const perPill = 32.0;
      final available = constraints.maxHeight;
      final int maxFit = (available / perPill).floor().clamp(2, 5);
      final shown = previews.take(maxFit).toList();
      final overflow = previews.length - shown.length;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in shown)
            ConversationPill(
              conv: c,
              compact: true,
              onTap: () => onOpenChat(c['booking_id'] as String),
            ),
          if (overflow > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InkWell(
                onTap: onOpenAll,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    '+$overflow more active',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: ctx.palette.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}
