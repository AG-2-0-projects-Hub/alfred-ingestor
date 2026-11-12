import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';
import 'guest_stay_fields.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// '2026-11-12' -> '12 Nov' (with the year when it isn't the current one).
String _day(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final y = d.year == DateTime.now().year ? '' : ' ${d.year}';
  return '${d.day} ${_months[d.month - 1]}$y';
}

String _dayTime(String date, String? time) =>
    time == null ? _day(date) : '${_day(date)} $time';

/// The "Stay" block of the host's live-chat side panel / sheet: the guest's
/// check-in/out as a one-line summary, with an inline editor. One widget for
/// both chat screens. Everything shown comes from GET /api/guests/{id}/stay
/// (local dates and times in the listing's zone, computed by the server).
class GuestStayPanel extends StatefulWidget {
  final String bookingId;
  final String propertyId;
  const GuestStayPanel(
      {super.key, required this.bookingId, required this.propertyId});

  @override
  State<GuestStayPanel> createState() => _GuestStayPanelState();
}

class _GuestStayPanelState extends State<GuestStayPanel> {
  final _c = GuestStayController();
  Map<String, dynamic>? _stay;
  Map<String, dynamic>? _defaults; // only fetched when the stay has no zone yet
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await GuestStayApi.stay(widget.bookingId);
      if (mounted) setState(() => _stay = s);
    } catch (_) {
      // keeps the previous summary if there was one, else shows "unavailable"
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: context.palette.danger),
    );
  }

  Future<void> _startEdit() async {
    final s = _stay!;
    if (s['provisional'] == true) {
      // No confirmed dates yet: empty dates, times + zone from the listing.
      _c.load();
      try {
        _defaults ??= await GuestStayApi.defaults(widget.propertyId);
        _c.fillTimes(_defaults!);
      } on ApiException catch (e) {
        if (mounted) _snack(e.userMessage);
      } catch (_) {
        if (mounted) _snack("Couldn't load the listing's times.");
      }
    } else {
      _c.load(
        inDate: s['check_in_date'] as String?,
        inTime: s['check_in_time'] as String?,
        outDate: s['check_out_date'] as String?,
        outTime: s['check_out_time'] as String?,
      );
    }
    if (mounted) setState(() => _editing = true);
  }

  Future<void> _save() async {
    if (_saving || !_c.complete) return;
    final tz = (_stay!['timezone'] ?? _defaults?['timezone']) as String?;
    if (tz == null) {
      _snack("Couldn't work out the time zone for this listing.");
      return;
    }
    setState(() => _saving = true);
    try {
      await GuestStayApi.save(widget.bookingId, _c.toBody(tz));
      if (!mounted) return;
      setState(() => _editing = false);
      await _load();
    } on ApiException catch (e) {
      if (mounted) _snack(e.userMessage);
    } catch (_) {
      if (mounted) _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (_loading && _stay == null) return const SizedBox.shrink();
    if (_stay == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          Text('Stay dates unavailable',
              style: GoogleFonts.inter(fontSize: 11, color: p.textMuted)),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );
    }
    final s = _stay!;
    final provisional = s['provisional'] == true;
    final ended = s['ended'] == true;

    // Tinted only while showing a state; the editor is always neutral.
    final tinted = !_editing;
    final Color bg = tinted && ended
        ? p.dangerContainer
        : tinted && provisional
            ? p.warningContainer
            : p.surface;
    final Color edge = tinted && ended
        ? p.danger.withValues(alpha: 0.4)
        : tinted && provisional
            ? p.warning.withValues(alpha: 0.35)
            : p.border;
    final Color titleColor =
        ended ? p.danger : (provisional ? p.warning : p.textPrimary);

    final title = ended
        ? 'Stay ended'
        : provisional
            ? 'Stay — dates not set'
            : 'Stay';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: edge),
      ),
      child: _editing ? _editor() : _summary(s, title, titleColor),
    );
  }

  Widget _summary(Map<String, dynamic> s, String title, Color titleColor) {
    final p = context.palette;
    final provisional = s['provisional'] == true;
    final ended = s['ended'] == true;
    final verb = ended ? 'closed' : 'closes';

    String closes;
    if (provisional) {
      final at = DateTime.tryParse((s['closes_at'] as String?) ?? '')?.toLocal();
      closes = at == null
          ? ''
          : 'Chat $verb ${_day(GuestStayController.formatDate(at))}';
    } else if (s['closes_time'] != null) {
      closes =
          'Chat $verb ${_dayTime(s['closes_date'] as String, s['closes_time'] as String?)}';
    } else {
      closes = 'Chat $verb end of ${_day(s['closes_date'] as String)}';
    }

    final tip = ended
        ? "Alfred has stopped answering. You'll get an alert if the guest writes."
        : provisional
            ? null
            : 'Alfred answers until 24 h after check-out.';

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title,
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: titleColor)),
            ),
            if (!provisional) _smallButton('Edit', _startEdit),
          ],
        ),
        if (!provisional) ...[
          const SizedBox(height: 4),
          Text(
            '${_dayTime(s['check_in_date'] as String, s['check_in_time'] as String?)} → '
            '${_dayTime(s['check_out_date'] as String, s['check_out_time'] as String?)}',
            style: GoogleFonts.inter(
                fontSize: 13, fontWeight: FontWeight.w500, color: p.textPrimary),
          ),
        ],
        if (closes.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(closes,
              style: GoogleFonts.inter(fontSize: 11, color: p.textMuted)),
        ],
        if (provisional) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _startEdit,
              style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  textStyle: GoogleFonts.inter(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              child: const Text('Set dates'),
            ),
          ),
        ],
      ],
    );
    return tip == null
        ? body
        : Tooltip(
            message: tip,
            waitDuration: const Duration(milliseconds: 500),
            child: body);
  }

  Widget _editor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Stay',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: context.palette.textPrimary)),
        const SizedBox(height: 8),
        GuestStayFields(controller: _c, compact: true),
        const SizedBox(height: 10),
        ListenableBuilder(
          listenable: _c,
          builder: (_, __) => Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => setState(() => _editing = false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: "Applies from the guest's next message.",
                waitDuration: const Duration(milliseconds: 500),
                child: FilledButton(
                  onPressed: (_saving || !_c.complete) ? null : _save,
                  style: FilledButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      textStyle: GoogleFonts.inter(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  child: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Save dates'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _smallButton(String label, VoidCallback onTap) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
            minimumSize: const Size(0, 24),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle:
                GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12)),
        child: Text(label),
      );
}
