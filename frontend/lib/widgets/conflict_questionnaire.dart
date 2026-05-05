import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ConflictQuestionnaireWidget extends StatefulWidget {
  const ConflictQuestionnaireWidget({
    super.key,
    required this.propertyId,
    required this.conflictReport,
    required this.backendUrl,
    required this.onResolved,
  });

  final String propertyId;
  final List<dynamic> conflictReport;
  final String backendUrl;
  final void Function(String status, Map<String, dynamic> masterJson) onResolved;

  @override
  State<ConflictQuestionnaireWidget> createState() =>
      _ConflictQuestionnaireWidgetState();
}

class _ConflictQuestionnaireWidgetState
    extends State<ConflictQuestionnaireWidget> {
  late final Map<String, String?> _selectedValues;
  late final Map<String, TextEditingController> _otherControllers;
  bool _isSubmitting = false;
  bool _submitSuccess = false;
  Map<String, dynamic>? _resolveResult;

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

  bool get _hasCompleteAnswer => _selectedValues.entries.any((e) {
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
      final response = await http.post(
        Uri.parse('${widget.backendUrl}/api/resolve/${widget.propertyId}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'resolutions': resolutions}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _submitSuccess = true;
          _resolveResult = data;
        });
      } else {
        _showError('Resolve failed (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      _showError('Resolve failed: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    if (_submitSuccess && _resolveResult != null) {
      return _buildSuccessState();
    }
    return _buildForm();
  }

  Widget _buildSuccessState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        border: Border.all(color: Colors.green.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade700),
              const SizedBox(width: 8),
              Text(
                'Answers saved to database',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => widget.onResolved(
              _resolveResult!['status'] as String,
              _resolveResult!['master_json'] as Map<String, dynamic>,
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Update Knowledge'),
          ),
        ],
      ),
    );
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

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          if (contextText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              contextText,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 12),
          ...options.map(
            (option) => RadioListTile<String>(
              value: option,
              groupValue: selected,
              onChanged: (v) => setState(() => _selectedValues[id] = v),
              title: Text(option, style: const TextStyle(fontSize: 14)),
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
