import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';

class ConflictQuestionnaireWidget extends StatefulWidget {
  const ConflictQuestionnaireWidget({
    super.key,
    required this.propertyId,
    required this.conflictReport,
    required this.onResolved,
    this.onAnswersSubmitted,
  });

  final String propertyId;
  final List<dynamic> conflictReport;
  final void Function(String status, Map<String, dynamic> masterJson) onResolved;
  // Fires once the resolutions are saved server-side (before the host clicks
  // "Update Knowledge"). Lets the parent retitle its status badge to reflect
  // that conflicts are answered but the knowledge update is still pending.
  final VoidCallback? onAnswersSubmitted;

  @override
  State<ConflictQuestionnaireWidget> createState() =>
      _ConflictQuestionnaireWidgetState();
}

class _ConflictQuestionnaireWidgetState
    extends State<ConflictQuestionnaireWidget> {
  late final Map<String, String?> _selectedValues;
  late final Map<String, TextEditingController> _otherControllers;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedValues = {
      for (final item in widget.conflictReport)
        (item as Map<String, dynamic>)['id'] as String: null,
    };
    _otherControllers = {
      for (final item in widget.conflictReport)
        (item as Map<String, dynamic>)['id'] as String: TextEditingController(),
    };
  }

  @override
  void dispose() {
    for (final c in _otherControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // Was .any — enabled submit once a single conflict was answered, silently
  // submitting the rest unresolved while the parent screen's success dialog
  // implied full resolution either way. Requires every conflict answered now.
  bool get _hasCompleteAnswer => _selectedValues.entries.every((e) {
        final selected = e.value;
        if (selected == null) return false;
        if (selected != 'other') return true;
        return _otherControllers[e.key]!.text.trim().isNotEmpty;
      });

  Future<void> _submit() async {
    final resolutions = <Map<String, dynamic>>[];
    for (final raw in widget.conflictReport) {
      final item = raw as Map<String, dynamic>;
      final id = item['id'] as String;
      final selected = _selectedValues[id];
      if (selected == null) continue;
      final isOther = selected == 'other';
      final value = isOther ? _otherControllers[id]!.text.trim() : selected;
      if (isOther && value.isEmpty) continue;
      resolutions.add({
        'field': id,
        'value': value,
        'input_method': isOther ? 'custom' : 'selected',
      });
    }

    if (resolutions.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      // ApiClient.postJson resolves BACKEND_URL itself and applies a real
      // timeout + one transient-failure retry — previously this widget took a
      // raw backendUrl string (one caller had it falling back to
      // 'http://localhost:8000' if unset) and called http.post directly with
      // no timeout at all, so a cold-starting backend could leave a host
      // stuck on "Saving..." during onboarding's conflict-resolution step
      // with no way out.
      final data = await ApiClient.postJson(
        '/api/resolve/${widget.propertyId}',
        {'resolutions': resolutions},
        // This call runs a real Gemini pass over the full master_json and can
        // legitimately run past the default 60s on a large property — give it
        // more room rather than showing an error for work that's still
        // quietly succeeding server-side (Cloud Run's own timeout is 300s).
        timeout: const Duration(seconds: 120),
      );
      widget.onAnswersSubmitted?.call();
      // Auto-apply the resolution — no separate "Update Knowledge" step.
      // The parent updates status + master_json and shows the completion
      // popup directly. This widget is torn down on the resulting rebuild.
      // Defensive: the backend now always includes master_json (fixed
      // 2026-09-15 — a duplicate/retried resolve call used to omit it
      // entirely and crash this cast), but don't let a future gap here take
      // the whole flow down again.
      widget.onResolved(
        data['status'] as String,
        data['master_json'] as Map<String, dynamic>? ?? const {},
      );
    } on ApiException catch (e) {
      // RequestTimeoutException's generic "Tap retry" message assumes a
      // dedicated retry button, which this SnackBar-only widget doesn't have
      // — the real action is just tapping Submit Resolutions again.
      final msg = e is RequestTimeoutException
          ? 'Alfred took longer than usual. Tap Submit Resolutions again.'
          : e.userMessage;
      _showError(msg);
    } catch (e) {
      _showError('Resolve failed: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: context.palette.danger));
  }

  @override
  Widget build(BuildContext context) {
    return _buildForm();
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final raw in widget.conflictReport) ...[
          _buildConflictItem(raw as Map<String, dynamic>),
          const SizedBox(height: 16),
        ],
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _hasCompleteAnswer && !_isSubmitting ? _submit : null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 18),
            textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2),
          ),
          child: _isSubmitting
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    ),
                    SizedBox(width: 12),
                    Text('Saving...'),
                  ],
                )
              : const Text('SUBMIT RESOLUTIONS'),
        ),
      ],
    );
  }

  Widget _buildConflictItem(Map<String, dynamic> item) {
    final id = item['id'] as String;
    final question = item['question'] as String? ?? id;
    final contextText = item['context'] as String? ?? '';
    final options =
        (item['options'] as List).map((o) => o.toString()).toList();
    final selected = _selectedValues[id];

    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.warningContainer,
        border: Border.all(color: palette.warning.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          if (contextText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              contextText,
              style: GoogleFonts.inter(fontSize: 13, color: palette.textSecondary),
            ),
          ],
          const SizedBox(height: 12),
          ...options.map(
            (option) => RadioListTile<String>(
              value: option,
              groupValue: selected,
              onChanged: (v) => setState(() => _selectedValues[id] = v),
              title: Text(option,
                  style: GoogleFonts.inter(fontSize: 14, color: palette.textPrimary)),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
          if (selected == 'other') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _otherControllers[id],
              decoration: const InputDecoration(
                labelText: 'Your answer',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ],
      ),
    );
  }
}
