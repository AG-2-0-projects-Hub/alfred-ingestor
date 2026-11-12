import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';

/// The browser's IANA time zone ("America/Mexico_City"), or null if it can't be
/// read. Only used as the LAST fallback when the listing's own zone is unknown
/// (the backend decides; see backend/services/stay.py `resolve_zone`).
String? browserTimeZone() {
  try {
    final intl = globalContext['Intl'] as JSObject?;
    final fmt = intl?.callMethod<JSObject>('DateTimeFormat'.toJS);
    final opts = fmt?.callMethod<JSObject>('resolvedOptions'.toJS);
    final tz = (opts?['timeZone'] as JSString?)?.toDart;
    return (tz == null || tz.isEmpty) ? null : tz;
  } catch (_) {
    return null;
  }
}

/// Host-token calls for the stay dates. The server does all time-zone math.
class GuestStayApi {
  GuestStayApi._();

  static String? get _token =>
      Supabase.instance.client.auth.currentSession?.accessToken;

  /// {timezone, timezone_source, check_in_time, check_out_time} of the listing;
  /// anything unknown is null.
  static Future<Map<String, dynamic>> defaults(String propertyId) {
    final tz = browserTimeZone();
    final q = tz == null ? '' : '?browser_tz=${Uri.encodeQueryComponent(tz)}';
    return ApiClient.getJson('/api/properties/$propertyId/stay-defaults$q',
        bearer: _token);
  }

  /// The guest's stay as the host reads it (see backend `stay.describe`).
  static Future<Map<String, dynamic>> stay(String bookingId) =>
      ApiClient.getJson('/api/guests/$bookingId/stay', bearer: _token);

  static Future<Map<String, dynamic>> save(
          String bookingId, Map<String, dynamic> body) =>
      ApiClient.postJson('/api/guests/$bookingId/stay', body, bearer: _token);
}

/// What the host typed: check-in/out dates (YYYY-MM-DD) and optional HH:MM times.
/// Dates start empty; times are pre-filled from the listing and editable.
class GuestStayController extends ChangeNotifier {
  final checkInDate = TextEditingController();
  final checkInTime = TextEditingController();
  final checkOutDate = TextEditingController();
  final checkOutTime = TextEditingController();

  List<TextEditingController> get _all =>
      [checkInDate, checkInTime, checkOutDate, checkOutTime];

  GuestStayController() {
    for (final c in _all) {
      c.addListener(notifyListeners);
    }
  }

  static final _timeRe = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

  /// A real calendar date typed as YYYY-MM-DD (2026-02-31 is not one).
  static DateTime? parseDate(String s) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return null;
    final d = DateTime.tryParse(s);
    return (d != null && formatDate(d) == s) ? d : null;
  }

  static String formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static bool validTime(String s) => _timeRe.hasMatch(s);

  bool get _timesValid =>
      (checkInTime.text.isEmpty || validTime(checkInTime.text)) &&
      (checkOutTime.text.isEmpty || validTime(checkOutTime.text));

  /// The one visible error line (null = nothing to complain about yet).
  String? get error {
    final din = parseDate(checkInDate.text);
    final dout = parseDate(checkOutDate.text);
    if (din != null && dout != null) {
      if (dout.isBefore(din)) return 'Check-out is before check-in.';
      if (dout == din &&
          validTime(checkInTime.text) &&
          validTime(checkOutTime.text) &&
          checkOutTime.text.compareTo(checkInTime.text) <= 0) {
        return 'Check-out is before check-in.';
      }
    }
    return null;
  }

  bool get complete =>
      parseDate(checkInDate.text) != null &&
      parseDate(checkOutDate.text) != null &&
      _timesValid &&
      error == null;

  /// Request body for POST /api/guests (spread) or /api/guests/{id}/stay.
  Map<String, dynamic> toBody(String timezone) => {
        'check_in_date': checkInDate.text,
        'check_out_date': checkOutDate.text,
        'stay_timezone': timezone,
        if (checkInTime.text.isNotEmpty) 'check_in_time': checkInTime.text,
        if (checkOutTime.text.isNotEmpty) 'check_out_time': checkOutTime.text,
      };

  void load({
    String? inDate,
    String? inTime,
    String? outDate,
    String? outTime,
  }) {
    checkInDate.text = inDate ?? '';
    checkInTime.text = inTime ?? '';
    checkOutDate.text = outDate ?? '';
    checkOutTime.text = outTime ?? '';
  }

  /// Fill the times from the listing's defaults, only where still empty.
  void fillTimes(Map<String, dynamic> defaults) {
    final i = defaults['check_in_time'] as String?;
    final o = defaults['check_out_time'] as String?;
    if (checkInTime.text.isEmpty && i != null) checkInTime.text = i;
    if (checkOutTime.text.isEmpty && o != null) checkOutTime.text = o;
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }
}

const _timeTip =
    'Times come from the listing. Change them for an early or late agreement.';
const _checkOutTip = 'The chat stays open until 24 h after check-out.';

/// Check-in / Check-out rows: a typed-or-picked date and an optional time each.
/// Explanations live in hover tooltips (long-press on phones); only an error
/// is ever shown as text.
class GuestStayFields extends StatelessWidget {
  final GuestStayController controller;
  final bool compact; // the 320 px live-chat panel
  const GuestStayFields(
      {super.key, required this.controller, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final err = controller.error;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _row(context, 'Check-in', controller.checkInDate,
                controller.checkInTime, null, err != null),
            SizedBox(height: compact ? 8 : 10),
            _row(context, 'Check-out', controller.checkOutDate,
                controller.checkOutTime, _checkOutTip, err != null),
            if (err != null) ...[
              const SizedBox(height: 4),
              Text(err,
                  style: GoogleFonts.inter(
                      fontSize: 11, color: context.palette.danger)),
            ],
          ],
        );
      },
    );
  }

  Widget _row(BuildContext context, String label, TextEditingController date,
      TextEditingController time, String? dateTip, bool pairError) {
    // Red only once the text is fully typed (a half-typed date isn't "wrong" yet).
    final dateInvalid =
        date.text.length == 10 && GuestStayController.parseDate(date.text) == null;
    final timeInvalid =
        time.text.length == 5 && !GuestStayController.validTime(time.text);
    final dateField = _field(
      context,
      controller: date,
      label: label,
      hint: 'YYYY-MM-DD',
      icon: Icons.calendar_today_outlined,
      invalid: dateInvalid || pairError && label == 'Check-out',
      formatter: RegExp(r'[0-9-]'),
      maxLen: 10,
      onPick: () => _pickDate(context, date),
    );
    final timeField = Tooltip(
      message: _timeTip,
      waitDuration: const Duration(milliseconds: 500),
      child: _field(
        context,
        controller: time,
        label: 'Time',
        hint: 'HH:MM',
        icon: Icons.schedule_rounded,
        invalid: timeInvalid,
        formatter: RegExp(r'[0-9:]'),
        maxLen: 5,
        onPick: () => _pickTime(context, time),
      ),
    );
    return Row(
      children: [
        Expanded(
          child: dateTip == null
              ? dateField
              : Tooltip(
                  message: dateTip,
                  waitDuration: const Duration(milliseconds: 500),
                  child: dateField),
        ),
        const SizedBox(width: 10),
        SizedBox(width: compact ? 90 : 112, child: timeField),
      ],
    );
  }

  Widget _field(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool invalid,
    required RegExp formatter,
    required int maxLen,
    required VoidCallback onPick,
  }) {
    final p = context.palette;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: w));
    return TextField(
      controller: controller,
      keyboardType: TextInputType.datetime,
      style: TextStyle(fontSize: compact ? 13 : 14),
      inputFormatters: [
        FilteringTextInputFormatter.allow(formatter),
        LengthLimitingTextInputFormatter(maxLen),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(12, 14, 4, 10),
        suffixIcon: IconButton(
          icon: Icon(icon, size: 16),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          color: invalid ? p.danger : p.textSecondary,
          onPressed: onPick,
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 32),
        enabledBorder: border(invalid ? p.danger : p.border),
        focusedBorder: border(invalid ? p.danger : p.primary, 1.5),
      ),
    );
  }

  Future<void> _pickDate(
      BuildContext context, TextEditingController ctrl) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: GuestStayController.parseDate(ctrl.text) ??
          (ctrl == controller.checkOutDate
              ? GuestStayController.parseDate(controller.checkInDate.text)
              : null) ??
          now,
      firstDate: DateTime(now.year - 1),
      lastDate: now.add(const Duration(days: 366)),
    );
    if (picked != null) ctrl.text = GuestStayController.formatDate(picked);
  }

  Future<void> _pickTime(
      BuildContext context, TextEditingController ctrl) async {
    final m = RegExp(r'^(\d\d):(\d\d)$').firstMatch(ctrl.text);
    final picked = await showTimePicker(
      context: context,
      initialTime: m == null
          ? const TimeOfDay(hour: 12, minute: 0)
          : TimeOfDay(hour: int.parse(m[1]!), minute: int.parse(m[2]!)),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      ctrl.text =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    }
  }
}
