String relativeTime(DateTime then) {
  final now = DateTime.now();
  final diff = now.difference(then);
  if (diff.inSeconds < 45) return 'Just now';
  if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  if (now.year == then.year) {
    return '${_month(then.month)} ${then.day}';
  }
  return '${_month(then.month)} ${then.day}, ${then.year}';
}

String _month(int m) => const [
  'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
][m - 1];

DateTime? parseTime(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  if (raw is String) return DateTime.tryParse(raw)?.toLocal();
  return null;
}
