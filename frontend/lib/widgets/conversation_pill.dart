import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class ConversationPill extends StatefulWidget {
  final Map<String, dynamic> conv;
  final VoidCallback onTap;
  final bool compact;
  // Guest has a link + welcome but hasn't replied yet → faded/transparent style.
  final bool pending;
  // Show the "Awaiting reply" chip (overview only; not on the property card).
  final bool showPendingLabel;
  const ConversationPill({
    super.key,
    required this.conv,
    required this.onTap,
    this.compact = true,
    this.pending = false,
    this.showPendingLabel = false,
  });

  Color _statusColor(BuildContext ctx) {
    final reason = conv['escalation_reason'] as String?;
    if (reason != null && reason.startsWith('emergency_')) return ctx.palette.danger;
    if (conv['requires_attention'] == true) return ctx.palette.warning;
    return ctx.palette.success;
  }

  @override
  State<ConversationPill> createState() => _ConversationPillState();
}

class _ConversationPillState extends State<ConversationPill>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _pulse.stop();
      _pulse.value = 1.0;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conv;
    final guestName = c['guestName'] as String? ?? 'Guest';
    final pending = widget.pending;
    final isIntervene = !pending && c['mode'] == 'intervene';
    final isUnread = !pending && c['requires_attention'] == true;
    // Pending (awaiting-reply) pills render in a neutral, muted colour so they
    // read as "not started" rather than active.
    final statusColor =
        pending ? context.palette.textMuted : widget._statusColor(context);

    final pad = widget.compact
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 12)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 12);

    return Opacity(
      opacity: pending ? 0.6 : 1.0,
      child: MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: pad,
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: _hovered ? 0.18 : 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: statusColor.withValues(alpha: _hovered ? 0.6 : 0.35),
              width: 1,
            ),
            boxShadow: isUnread
                ? [BoxShadow(color: statusColor.withValues(alpha: 0.35), blurRadius: 8)]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: widget.compact ? 18 : 24,
                height: widget.compact ? 18 : 24,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    guestName.isNotEmpty ? guestName[0].toUpperCase() : '?',
                    style: GoogleFonts.inter(
                      fontSize: widget.compact ? 9 : 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  guestName,
                  style: GoogleFonts.inter(
                    fontSize: widget.compact ? 11 : 13,
                    color: context.palette.textPrimary,
                    fontWeight: isUnread ? FontWeight.w600 : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (pending && widget.showPendingLabel) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.palette.textMuted.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Awaiting reply',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: context.palette.textMuted,
                    ),
                  ),
                ),
              ],
              if (isIntervene) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Host is replying live',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Live',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
              if (isUnread) ...[
                const SizedBox(width: 6),
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    return Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor.withValues(alpha: 0.5 + 0.5 * _pulse.value),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    );
  }
}
