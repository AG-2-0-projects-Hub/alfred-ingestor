import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_live_screen.dart';
import '../widgets/generate_guest_link_dialog.dart';

class HostPanelScreen extends StatefulWidget {
  final String propertyId;

  const HostPanelScreen({super.key, required this.propertyId});

  @override
  State<HostPanelScreen> createState() => _HostPanelScreenState();
}

class _HostPanelScreenState extends State<HostPanelScreen> {
  List<Map<String, dynamic>> _guests = [];
  String _propertyName = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Fetch property name
      final prop = await Supabase.instance.client
          .from('properties')
          .select('name')
          .eq('id', widget.propertyId)
          .maybeSingle();
      _propertyName = prop?['name'] as String? ?? 'Property';

      // Fetch guests joined with conversations
      final data = await Supabase.instance.client
          .from('guests')
          .select('id, booking_id, name, guest_chat_url, host_chat_url, conversations(mode, last_message_at, requires_attention, ai_status)')
          .eq('property_id', widget.propertyId)
          .order('booking_id');

      if (mounted) {
        setState(() => _guests = List<Map<String, dynamic>>.from(data));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load guests: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openChat(Map<String, dynamic> guest) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatLiveScreen(
        bookingId: guest['booking_id'] as String,
        propertyId: widget.propertyId,
      ),
    ));
  }

  void _openGuestLink() {
    showDialog(
      context: context,
      builder: (_) => GenerateGuestLinkDialog(
        property: {'id': widget.propertyId, 'name': _propertyName},
        onCreated: _load,
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$_propertyName — Conversations'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _buildList(),
            ),
    );
  }

  Widget _buildList() {
    if (_guests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('No guests yet.',
                style: TextStyle(color: Colors.grey, fontSize: 16)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _openGuestLink,
              icon: const Icon(Icons.add_link),
              label: const Text('+ New Guest Link'),
            ),
          ],
        ),
      );
    }

    return ListView(
      children: [
        ..._guests.map((guest) => _buildGuestTile(guest)),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.add_link, color: Colors.indigo),
          title: const Text('+ New Guest Link',
              style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.w600)),
          onTap: _openGuestLink,
        ),
      ],
    );
  }

  Widget _buildGuestTile(Map<String, dynamic> guest) {
    final conv = (guest['conversations'] as List<dynamic>?)?.firstOrNull
        as Map<String, dynamic>?;
    final requiresAttention = conv?['requires_attention'] as bool? ?? false;
    final mode = conv?['mode'] as String? ?? 'autopilot';
    final lastMessageAt = conv?['last_message_at'] as String?;
    final name = guest['name'] as String? ?? 'Guest';

    return ListTile(
      tileColor: requiresAttention ? Colors.orange.shade50 : null,
      leading: CircleAvatar(
        backgroundColor:
            requiresAttention ? Colors.orange.shade100 : Colors.indigo.shade50,
        child: Icon(
          requiresAttention ? Icons.warning_amber_rounded : Icons.person_outline,
          color: requiresAttention ? Colors.orange.shade800 : Colors.indigo,
          size: 20,
        ),
      ),
      title: Row(
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          _ModeBadge(mode: mode),
        ],
      ),
      subtitle: lastMessageAt != null
          ? Text(_timeAgo(lastMessageAt),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12))
          : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openChat(guest),
    );
  }

  String _timeAgo(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }
}

class _ModeBadge extends StatelessWidget {
  final String mode;
  const _ModeBadge({required this.mode});

  @override
  Widget build(BuildContext context) {
    final isIntervene = mode == 'intervene';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isIntervene ? Colors.orange.shade100 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        mode,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isIntervene ? Colors.orange.shade800 : Colors.green.shade800,
        ),
      ),
    );
  }
}
