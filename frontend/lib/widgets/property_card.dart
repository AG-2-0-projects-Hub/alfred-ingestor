import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PropertyCard extends StatelessWidget {
  final Map<String, dynamic> property;
  final VoidCallback onExpand;
  final VoidCallback onGuestLink;
  final VoidCallback onHostChat;
  final VoidCallback onAddProperty;
  final VoidCallback onArchivedChats;
  final VoidCallback onCalendar;
  final int activeChatCount;

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
        activeChatCount = 0;

  static void _noop() {}

  bool get _isAddCard => property.isEmpty;

  @override
  Widget build(BuildContext context) {
    if (_isAddCard) return _buildAddCard(context);
    return _buildPropertyCard(context);
  }

  Widget _buildAddCard(BuildContext context) {
    return GestureDetector(
      onTap: onAddProperty,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.indigo.shade200, width: 1.5),
        ),
        child: const SizedBox(
          width: 280,
          height: 320,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline, size: 48, color: Colors.indigo),
              SizedBox(height: 12),
              Text('Add Property',
                  style: TextStyle(
                      color: Colors.indigo, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPropertyCard(BuildContext context) {
    final status = property['status'] as String? ?? '';
    final name = property['name'] as String? ?? 'Unnamed';
    final propertyId = property['id'] as String;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 280,
        height: 320,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hero image (160px)
            SizedBox(
              height: 160,
              child: _HeroImage(propertyId: propertyId, status: status),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _StatusBadge(status: status),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Info row: active chats + utility icons
                    Row(
                      children: [
                        if (activeChatCount > 0) ...[
                          Icon(Icons.chat_bubble,
                              size: 13, color: Colors.green.shade600),
                          const SizedBox(width: 3),
                          Text(
                            '$activeChatCount ${activeChatCount == 1 ? 'chat' : 'chats'}',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                        const Spacer(),
                        _TinyIconBtn(
                          icon: Icons.calendar_month_outlined,
                          tooltip: 'Reservations',
                          onTap: onCalendar,
                        ),
                        const SizedBox(width: 6),
                        _TinyIconBtn(
                          icon: Icons.history,
                          tooltip: 'Chat History',
                          onTap: onArchivedChats,
                        ),
                      ],
                    ),
                    const Spacer(),
                    _buildActions(context, status),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, String status) {
    final isProcessing = status == 'Ingesting' || status == 'Training';
    final isConflict = status == 'Conflict_Pending';
    final isError = status.contains('Error');
    final isReady =
        status == 'Trained' || status == 'Active' || status == 'Resolved' || status == 'Merged';

    if (isProcessing) {
      return const Row(children: [
        SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 8),
        Text('Processing…', style: TextStyle(fontSize: 12, color: Colors.grey)),
      ]);
    }

    if (isError) {
      return Row(children: [
        const Icon(Icons.error_outline, size: 16, color: Colors.red),
        const SizedBox(width: 6),
        TextButton(
          onPressed: onAddProperty,
          style: TextButton.styleFrom(
              padding: EdgeInsets.zero, foregroundColor: Colors.red),
          child: const Text('Re-ingest', style: TextStyle(fontSize: 12)),
        ),
      ]);
    }

    if (isConflict) {
      return Row(children: [
        const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
        const SizedBox(width: 6),
        TextButton(
          onPressed: onExpand,
          style: TextButton.styleFrom(
              padding: EdgeInsets.zero, foregroundColor: Colors.orange),
          child: const Text('Resolve', style: TextStyle(fontSize: 12)),
        ),
      ]);
    }

    if (isReady) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _SmallButton(icon: Icons.link, label: '+ Guest', onTap: onGuestLink),
          _SmallButton(
              icon: Icons.chat_bubble_outline, label: 'Chats', onTap: onHostChat),
          _SmallButton(
              icon: Icons.open_in_new, label: 'Details', onTap: onExpand),
        ],
      );
    }

    // Ingested / unknown — show expand only
    return Align(
      alignment: Alignment.centerRight,
      child: _SmallButton(
          icon: Icons.open_in_new, label: 'Details', onTap: onExpand),
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
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, size: 16, color: Colors.grey.shade500),
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SmallButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.indigo.shade700),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.indigo.shade700,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'Ingesting' || 'Training' => ('Processing', Colors.blue),
      'Ingested' => ('Ingested', Colors.amber.shade700),
      'Merged' || 'Trained' || 'Resolved' => ('Ready', Colors.green.shade700),
      'Active' => ('Active', Colors.green.shade800),
      'Conflict_Pending' => ('Conflicts', Colors.orange.shade800),
      String s when s.contains('Error') => ('Error', Colors.red),
      _ => (status, Colors.grey.shade700),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        border: Border.all(color: color.withAlpha(80)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

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
          .createSignedUrl('${widget.propertyId}/hero_image/main.jpg', 3600);
      if (mounted) setState(() => _url = url);
    } catch (_) {
      // No hero image — show gradient placeholder
    } finally {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const ColoredBox(color: Color(0xFFE8EAF6));
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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.indigo.shade100, Colors.indigo.shade300],
        ),
      ),
      child: const Center(
        child: Icon(Icons.home_outlined, size: 48, color: Colors.white),
      ),
    );
  }
}
