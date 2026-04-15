import 'package:flutter/material.dart';

class FileStatusList extends StatelessWidget {
  final List<Map<String, String>> statuses;

  const FileStatusList({super.key, required this.statuses});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('File Processing',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...statuses.map((s) => _FileStatusRow(
              filename: s['file'] ?? '',
              status: s['status'] ?? '',
              message: s['message'] ?? '',
            )),
      ],
    );
  }
}

class _FileStatusRow extends StatelessWidget {
  final String filename;
  final String status;
  final String message;

  const _FileStatusRow({
    required this.filename,
    required this.status,
    this.message = '',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusIcon(status: status),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  filename,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _StatusLabel(status: status),
            ],
          ),
          if (status == 'error' && message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 2),
              child: Text(
                message,
                style: const TextStyle(fontSize: 11, color: Colors.red),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final String status;
  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'queued':
        return const Icon(Icons.hourglass_empty, size: 18, color: Colors.grey);
      case 'processing':
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case 'done':
        return const Icon(Icons.check_circle, size: 18, color: Colors.green);
      case 'skipped':
        return const Icon(Icons.skip_next, size: 18, color: Colors.orange);
      case 'error':
        return const Icon(Icons.error, size: 18, color: Colors.red);
      default:
        return const SizedBox(width: 18);
    }
  }
}

class _StatusLabel extends StatelessWidget {
  final String status;
  const _StatusLabel({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'queued' => ('Queued', Colors.grey),
      'processing' => ('Processing...', Colors.blue),
      'done' => ('Done', Colors.green),
      'skipped' => ('Skipped', Colors.orange),
      'error' => ('Error', Colors.red),
      _ => (status, Colors.grey),
    };
    return Text(label,
        style: TextStyle(
            fontSize: 12, color: color, fontWeight: FontWeight.w500));
  }
}
