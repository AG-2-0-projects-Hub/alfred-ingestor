import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../widgets/aurora_background.dart';
import '../widgets/property_card.dart';
import '../widgets/property_detail_drawer.dart';
import '../widgets/archived_chats_dialog.dart';
import 'add_property_screen.dart';
import 'host_panel_screen.dart';
import '../widgets/generate_guest_link_dialog.dart';
import 'auth_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Map<String, dynamic>> _properties = [];
  Map<String, int> _chatCounts = {};
  Map<String, bool> _hasEscalation = {};
  Map<String, bool> _hasEmergency = {};
  Map<String, List<Map<String, dynamic>>> _conversationPreviews = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProperties();
  }

  Future<void> _loadProperties() async {
    setState(() => _loading = true);
    try {
      final data = await Supabase.instance.client
          .from('properties')
          .select(
              'id, name, status, airbnb_url, created_at, master_json, file_fingerprints, Conflict_status')
          .order('created_at', ascending: false);

      final properties = List<Map<String, dynamic>>.from(data);

      // Load guest counts per property for the active chat indicator
      Map<String, int> counts = {};
      Map<String, bool> hasEscalation = {};
      Map<String, bool> hasEmergency = {};
      Map<String, List<Map<String, dynamic>>> previews = {};
      if (properties.isNotEmpty) {
        final ids = properties.map((p) => p['id'] as String).toList();
        final guests = await Supabase.instance.client
            .from('guests')
            .select('property_id')
            .inFilter('property_id', ids);
        for (final g in guests) {
          final pid = g['property_id'] as String;
          counts[pid] = (counts[pid] ?? 0) + 1;
        }
        // Load active escalation/emergency state + conversation previews per property
        final convRows = await Supabase.instance.client
            .from('conversations')
            .select(
                'id, property_id, booking_id, mode, requires_attention, escalation_reason')
            .inFilter('property_id', ids)
            .order('created_at', ascending: false);

        for (final a in convRows) {
          final pid = a['property_id'] as String;
          if (a['requires_attention'] == true) {
            hasEscalation[pid] = true;
            final reason = a['escalation_reason'] as String?;
            if (reason != null && reason.startsWith('emergency_')) {
              hasEmergency[pid] = true;
            }
          }
        }

        // Fetch guest names for conversation previews
        final bookingIds = convRows
            .map((c) => c['booking_id'] as String?)
            .whereType<String>()
            .toList();
        final Map<String, String> guestNames = {};
        if (bookingIds.isNotEmpty) {
          final guestsData = await Supabase.instance.client
              .from('guests')
              .select('booking_id, name')
              .inFilter('booking_id', bookingIds);
          for (final g in guestsData) {
            guestNames[g['booking_id'] as String] =
                g['name'] as String? ?? 'Guest';
          }
        }

        // previews declared above the if block for setState scope
        for (final c in convRows) {
          final pid = c['property_id'] as String;
          final bid = c['booking_id'] as String? ?? '';
          final merged = {...c, 'guestName': guestNames[bid] ?? 'Guest'};
          previews[pid] = [...(previews[pid] ?? []), merged];
        }
        for (final pid in previews.keys) {
          previews[pid]!.sort((a, b) {
            int priority(Map<String, dynamic> x) {
              final reason = x['escalation_reason'] as String?;
              if (reason != null && reason.startsWith('emergency_')) return 0;
              if (x['requires_attention'] == true) return 1;
              if (x['mode'] == 'intervene') return 2;
              return 3;
            }
            return priority(a).compareTo(priority(b));
          });
        }
      }

      if (mounted) {
        setState(() {
          _properties = properties;
          _chatCounts = counts;
          _hasEscalation = hasEscalation;
          _hasEmergency = hasEmergency;
          _conversationPreviews = previews;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load properties: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (_) => false,
      );
    }
  }

  void _openAddProperty() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddPropertyScreen()),
    );
    _loadProperties();
  }

  void _openDrawer(Map<String, dynamic> property) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => Align(
        alignment: Alignment.centerRight,
        child: PropertyDetailDrawer(
          property: property,
          onRefresh: _loadProperties,
        ),
      ),
      transitionBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
        child: child,
      ),
    );
  }

  void _openGuestLink(Map<String, dynamic> property) {
    showDialog(
      context: context,
      builder: (_) => GenerateGuestLinkDialog(property: property),
    );
  }

  void _openHostChat(Map<String, dynamic> property) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HostPanelScreen(propertyId: property['id'] as String),
      ),
    );
  }

  void _openArchivedChats(Map<String, dynamic> property) {
    showDialog(
      context: context,
      builder: (_) => ArchivedChatsDialog(
        propertyId: property['id'] as String,
        propertyName: property['name'] as String? ?? 'Property',
      ),
    );
  }

  void _openCalendar(Map<String, dynamic> property) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.calendar_month_rounded, color: AppTheme.primary),
          const SizedBox(width: 10),
          const Text('Reservations'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.calendar_month_rounded,
                  size: 36, color: AppTheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
              property['name'] as String? ?? 'Property',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              'Reservations calendar coming soon.',
              style: GoogleFonts.inter(
                  color: AppTheme.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: AppBar(
              backgroundColor: AppTheme.glassTint,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTheme.primary, AppTheme.accent],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.home_work_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Alfred',
                    style: GoogleFonts.poppins(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    child: Text(
                      email,
                      style: GoogleFonts.inter(
                          fontSize: 13, color: AppTheme.textSecondary),
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout_rounded, size: 17),
                  label: const Text('Logout'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    textStyle: GoogleFonts.inter(
                        fontWeight: FontWeight.w500, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
      body: AuroraBackground(
        intensity: 0.50,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.primary))
            : RefreshIndicator(
                color: AppTheme.primary,
                onRefresh: _loadProperties,
                child: _buildGrid(),
              ),
      ),
    );
  }

  Widget _buildGrid() {
    final items = [..._properties, <String, dynamic>{}]; // trailing "+" card

    return LayoutBuilder(builder: (context, constraints) {
      int columns;
      if (constraints.maxWidth > 1100) {
        columns = 4;
      } else if (constraints.maxWidth > 800) {
        columns = 3;
      } else if (constraints.maxWidth > 520) {
        columns = 2;
      } else {
        columns = 1;
      }

      return GridView.builder(
        padding: EdgeInsets.fromLTRB(28, kToolbarHeight + 28, 28, 48),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 18,
          mainAxisSpacing: 18,
          childAspectRatio: 280 / 390,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final card = item.isEmpty
              ? PropertyCard.add(onAddProperty: _openAddProperty)
              : PropertyCard(
                  property: item,
                  activeChatCount: _chatCounts[item['id'] as String] ?? 0,
                  hasEscalation:
                      _hasEscalation[item['id'] as String] ?? false,
                  hasEmergency:
                      _hasEmergency[item['id'] as String] ?? false,
                  conversationPreviews:
                      _conversationPreviews[item['id'] as String] ?? [],
                  onExpand: () => _openDrawer(item),
                  onGuestLink: () => _openGuestLink(item),
                  onHostChat: () => _openHostChat(item),
                  onAddProperty: _openAddProperty,
                  onArchivedChats: () => _openArchivedChats(item),
                  onCalendar: () => _openCalendar(item),
                );
          return _StaggeredEntry(
            delayMs: (index * 50).clamp(0, 400),
            child: card,
          );
        },
      );
    });
  }
}

/// Subtle fade + 12px upward slide for each grid item, staggered by index.
class _StaggeredEntry extends StatefulWidget {
  final Widget child;
  final int delayMs;
  const _StaggeredEntry({required this.child, required this.delayMs});

  @override
  State<_StaggeredEntry> createState() => _StaggeredEntryState();
}

class _StaggeredEntryState extends State<_StaggeredEntry> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      offset: _shown ? Offset.zero : const Offset(0, 0.06),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 280),
        opacity: _shown ? 1 : 0,
        child: widget.child,
      ),
    );
  }
}
