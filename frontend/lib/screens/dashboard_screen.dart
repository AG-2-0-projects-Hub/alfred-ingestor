import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/aurora_background.dart';
import '../widgets/property_card.dart';
import '../widgets/property_detail_drawer.dart';
import '../widgets/property_expanded_view.dart';
import '../widgets/archived_chats_dialog.dart';
import '../widgets/chat_live_dialog.dart';
import 'add_property_screen.dart';
import '../widgets/generate_guest_link_dialog.dart';
import '../services/push_notification_service.dart';
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
  Map<String, String> _guestNamesByBooking = {};
  bool _loading = true;

  StreamSubscription? _convStreamSub;
  StreamSubscription? _guestStreamSub;
  StreamSubscription? _propertyStreamSub;
  Timer? _refreshTimer;

  // Push-notification edge detection
  final Map<String, bool> _prevRequiresAttention = {};
  String _notifPermission = 'default';
  bool _showNotifChip = true;

  @override
  void initState() {
    super.initState();
    _notifPermission = PushNotificationService.permissionState;
    _loadProperties().then((_) {
      if (!mounted) return;
      _subscribeRealtime();
      // Belt-and-suspenders: Supabase realtime streams can silently drop on
      // the free tier. Re-fetch every 30s so stale state self-heals without
      // a manual refresh.
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) _loadProperties();
      });
    });
  }

  @override
  void dispose() {
    _convStreamSub?.cancel();
    _guestStreamSub?.cancel();
    _propertyStreamSub?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
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

      Map<String, int> counts = {};
      Map<String, bool> hasEscalation = {};
      Map<String, bool> hasEmergency = {};
      Map<String, List<Map<String, dynamic>>> previews = {};
      Map<String, String> guestNames = {};
      if (properties.isNotEmpty) {
        final ids = properties.map((p) => p['id'] as String).toList();
        final guests = await Supabase.instance.client
            .from('guests')
            .select('property_id, booking_id, name')
            .inFilter('property_id', ids);
        for (final g in guests) {
          final pid = g['property_id'] as String;
          counts[pid] = (counts[pid] ?? 0) + 1;
          final bid = g['booking_id'] as String?;
          if (bid != null) {
            guestNames[bid] = g['name'] as String? ?? 'Guest';
          }
        }
        final convRows = await Supabase.instance.client
            .from('conversations')
            .select(
                'id, property_id, booking_id, mode, requires_attention, escalation_reason')
            .inFilter('property_id', ids)
            .order('created_at', ascending: false);

        _processConversations(convRows, guestNames, hasEscalation, hasEmergency, previews);
      }

      if (mounted) {
        setState(() {
          _properties = properties;
          _chatCounts = counts;
          _hasEscalation = hasEscalation;
          _hasEmergency = hasEmergency;
          _conversationPreviews = previews;
          _guestNamesByBooking = guestNames;
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

  void _processConversations(
    List<dynamic> convRows,
    Map<String, String> guestNames,
    Map<String, bool> esc,
    Map<String, bool> emer,
    Map<String, List<Map<String, dynamic>>> previews,
  ) {
    for (final c in convRows) {
      final pid = c['property_id'] as String;
      final bid = c['booking_id'] as String? ?? '';
      if (c['requires_attention'] == true) {
        esc[pid] = true;
        final reason = c['escalation_reason'] as String?;
        if (reason != null && reason.startsWith('emergency_')) {
          emer[pid] = true;
        }
      }
      final merged = <String, dynamic>{...c, 'guestName': guestNames[bid] ?? 'Guest'};
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
    _checkForNewEscalations(convRows);
  }

  String _resolvePropertyName(String propertyId) {
    final p = _properties.firstWhere(
      (x) => x['id'] == propertyId,
      orElse: () => <String, dynamic>{},
    );
    return p['name'] as String? ?? 'Property';
  }

  Future<void> _checkForNewEscalations(List<dynamic> rows) async {
    for (final row in rows) {
      final id = row['id'] as String?;
      if (id == null) continue;
      final current = row['requires_attention'] == true;
      final hadPrev = _prevRequiresAttention.containsKey(id);
      final previous = _prevRequiresAttention[id] ?? false;
      _prevRequiresAttention[id] = current;

      // Only fire on a confirmed false→true edge — skip the seeding pass
      // (no previous entry means we're learning the row for the first time).
      if (!hadPrev || !current || previous) continue;

      if (PushNotificationService.permissionState == 'default') {
        await PushNotificationService.requestPermission();
        if (mounted) {
          setState(() => _notifPermission = PushNotificationService.permissionState);
        }
      }
      if (PushNotificationService.permissionState != 'granted') continue;

      final propertyId = row['property_id'] as String? ?? '';
      final bookingId = row['booking_id'] as String? ?? '';
      final reason = row['escalation_reason'] as String?;
      final isEmergency = reason?.startsWith('emergency_') == true;
      final propertyName = _resolvePropertyName(propertyId);

      PushNotificationService.showEscalationAlert(
        propertyName: propertyName,
        bookingId: bookingId,
        reason: reason,
        isEmergency: isEmergency,
        onTap: () {
          if (!mounted) return;
          ChatLiveDialog.show(
            context,
            bookingId: bookingId,
            propertyId: propertyId,
            propertyName: propertyName,
          );
        },
      );
    }
  }

  void _subscribeRealtime() {
    final ids = _properties.map((p) => p['id'] as String).toList();
    if (ids.isEmpty) return;

    _propertyStreamSub = Supabase.instance.client
        .from('properties')
        .stream(primaryKey: ['id'])
        .inFilter('id', ids)
        .listen((rows) {
          if (!mounted) return;
          final byId = {for (final p in rows) p['id'] as String: p};
          final updated = _properties.map((p) {
            final fresh = byId[p['id'] as String];
            return fresh != null ? {...p, ...fresh} : p;
          }).toList();
          setState(() => _properties = updated);
        });

    _convStreamSub = Supabase.instance.client
        .from('conversations')
        .stream(primaryKey: ['id'])
        .inFilter('property_id', ids)
        .listen((rows) {
          if (!mounted) return;
          final Map<String, bool> esc = {};
          final Map<String, bool> emer = {};
          final Map<String, List<Map<String, dynamic>>> previews = {};
          _processConversations(rows, _guestNamesByBooking, esc, emer, previews);
          setState(() {
            _hasEscalation = esc;
            _hasEmergency = emer;
            _conversationPreviews = previews;
          });
        });

    _guestStreamSub = Supabase.instance.client
        .from('guests')
        .stream(primaryKey: ['id'])
        .inFilter('property_id', ids)
        .listen((rows) {
          if (!mounted) return;
          final counts = <String, int>{};
          final names = <String, String>{};
          for (final g in rows) {
            final pid = g['property_id'] as String;
            counts[pid] = (counts[pid] ?? 0) + 1;
            final bid = g['booking_id'] as String?;
            if (bid != null) {
              names[bid] = g['name'] as String? ?? 'Guest';
            }
          }
          setState(() {
            _chatCounts = counts;
            _guestNamesByBooking = names;
          });
        });
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
            .animate(CurvedAnimation(parent: anim, curve: AppTheme.standardEasing)),
        child: child,
      ),
    );
  }

  void _openExpandedView(Map<String, dynamic> property) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => PropertyExpandedView(
        property: property,
        activeConversations: _conversationPreviews[property['id']] ?? [],
      ),
      transitionBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  void _openChatLive(String bookingId, String propertyId) {
    ChatLiveDialog.show(
      context,
      bookingId: bookingId,
      propertyId: propertyId,
      propertyName: _resolvePropertyName(propertyId),
    );
  }

  void _openGuestLink(Map<String, dynamic> property) {
    showDialog(
      context: context,
      builder: (_) => GenerateGuestLinkDialog(property: property),
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
    final palette = context.palette;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [
          Icon(Icons.calendar_month_rounded, color: palette.primary),
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
                color: palette.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.calendar_month_rounded,
                  size: 36, color: palette.primary),
            ),
            const SizedBox(height: 16),
            Text(
              property['name'] as String? ?? 'Property',
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w500, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              'Reservations calendar coming soon.',
              style: GoogleFonts.inter(
                  color: palette.textSecondary, fontSize: 13),
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
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final palette = context.palette;
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    final screenW = MediaQuery.of(context).size.width;
    final isNarrow = screenW < 480;
    final isMedium = screenW < 700;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: AppBar(
              backgroundColor: palette.glassTint,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              title: Row(
                children: [
                  Icon(Icons.home_work_outlined,
                      color: palette.textPrimary, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Alfred',
                    style: GoogleFonts.plusJakartaSans(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w300,
                      fontSize: 22,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              actions: [
                if (_notifPermission == 'denied' && _showNotifChip)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Center(
                      child: isMedium
                          ? IconButton(
                              tooltip: 'Notifications blocked — enable in browser settings',
                              icon: Icon(
                                Icons.notifications_off_rounded,
                                size: 18,
                                color: palette.warning,
                              ),
                              onPressed: () => setState(() => _showNotifChip = false),
                            )
                          : Chip(
                              avatar: Icon(
                                Icons.notifications_off_rounded,
                                size: 14,
                                color: palette.warning,
                              ),
                              label: Text(
                                'Enable notifications in browser settings',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: palette.textSecondary,
                                ),
                              ),
                              backgroundColor: palette.warningContainer.withValues(alpha: 0.6),
                              side: BorderSide(color: palette.warning.withValues(alpha: 0.35)),
                              onDeleted: () => setState(() => _showNotifChip = false),
                              deleteIconColor: palette.textMuted,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                    ),
                  ),
                if (!isNarrow)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: isMedium ? 140 : 240),
                        child: Text(
                          email,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              fontSize: 13, color: palette.textSecondary),
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: themeController.isDark
                      ? 'Switch to Daylight'
                      : 'Switch to Midnight',
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, anim) => RotationTransition(
                      turns: anim,
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: Icon(
                      themeController.isDark
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                      key: ValueKey(themeController.isDark),
                      size: 18,
                    ),
                  ),
                  onPressed: () async {
                    await themeController.toggle();
                  },
                ),
                if (isNarrow)
                  IconButton(
                    tooltip: 'Logout',
                    onPressed: _logout,
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    color: palette.textSecondary,
                  )
                else
                  TextButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout_rounded, size: 17),
                    label: const Text('Logout'),
                    style: TextButton.styleFrom(
                      foregroundColor: palette.textSecondary,
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
            ? Center(child: CircularProgressIndicator(color: palette.primary))
            : RefreshIndicator(
                color: palette.primary,
                onRefresh: _loadProperties,
                child: _buildBody(palette),
              ),
      ),
    );
  }

  Widget _buildBody(AppPalette palette) {
    if (_properties.isEmpty) {
      return LayoutBuilder(builder: (ctx, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(40, kToolbarHeight + 40, 40, 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [
                          palette.primary,
                          palette.accent,
                        ]),
                      ),
                      child: const Icon(Icons.home_work_rounded,
                          size: 48, color: Colors.white),
                    ),
                    const SizedBox(height: 24),
                    Text('Welcome to Alfred',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w300,
                          color: palette.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add your first Airbnb property to get started. Alfred will read your files and become your AI co-host.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          color: palette.textSecondary,
                          height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _openAddProperty,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add Your First Property'),
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 14)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      });
    }
    return _buildGrid();
  }

  Widget _buildGrid() {
    final items = [..._properties, <String, dynamic>{}];
    final n = items.length;

    return LayoutBuilder(builder: (context, constraints) {
      final viewportW = constraints.maxWidth;
      final viewportH = constraints.maxHeight;

      // Mobile: single column, banner-style cards (~220 tall), scrollable.
      // Don't try to fit everything in viewport — vertical scroll is expected.
      if (viewportW < 500) {
        const mobilePadH = 16.0;
        const mobilePadTop = kToolbarHeight + 16.0;
        const mobilePadBottom = 24.0;
        const mobileGap = 14.0;
        final mobileCardW = viewportW - mobilePadH * 2;
        const mobileCardH = 220.0;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
              mobilePadH, mobilePadTop, mobilePadH, mobilePadBottom),
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 1,
            crossAxisSpacing: mobileGap,
            mainAxisSpacing: mobileGap,
            childAspectRatio: mobileCardW / mobileCardH,
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
                    onOpenChat: (bookingId) =>
                        _openChatLive(bookingId, item['id'] as String),
                    onOpenExpanded: () => _openExpandedView(item),
                    onOpenSettings: () => _openDrawer(item),
                    onGuestLink: () => _openGuestLink(item),
                    onAddProperty: _openAddProperty,
                    onArchivedChats: () => _openArchivedChats(item),
                    onCalendar: () => _openCalendar(item),
                  );
            return _StaggeredEntry(
              delayMs: (index * 40).clamp(0, 240),
              child: card,
            );
          },
        );
      }

      const minCardW = 240.0;
      const minCardH = 280.0;
      const gap = 18.0;
      const padH = 28.0;
      const padTop = kToolbarHeight + 28.0;
      const padBottom = 32.0;

      // Pick the largest column count whose card width is >= minCardW.
      int bestCols = 1;
      for (int cols = 1; cols <= 6; cols++) {
        final cardW = (viewportW - padH * 2 - gap * (cols - 1)) / cols;
        if (cardW >= minCardW) bestCols = cols;
      }

      final rows = (n / bestCols).ceil();
      final cardW =
          (viewportW - padH * 2 - gap * (bestCols - 1)) / bestCols;
      final availH = viewportH - padTop - padBottom - gap * (rows - 1);
      final fillH = availH / rows;

      // If all rows fit at minCardH or taller, fill the viewport.
      // Otherwise, fall back to a scrollable grid with a sensible aspect.
      final fits = fillH >= minCardH;
      // Cap the fill height so a lone card on a tall viewport doesn't get
      // stretched into a ridiculous portrait.
      final maxCardH = cardW * 1.6;
      final cardH = fits
          ? (fillH > maxCardH ? maxCardH : fillH)
          : (cardW * 340 / 280);
      final aspect = cardW / cardH;

      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(padH, padTop, padH, padBottom),
        physics: fits
            ? const NeverScrollableScrollPhysics()
            : const AlwaysScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: bestCols,
          crossAxisSpacing: gap,
          mainAxisSpacing: gap,
          childAspectRatio: aspect,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final card = item.isEmpty
              ? PropertyCard.add(onAddProperty: _openAddProperty)
              : PropertyCard(
                  property: item,
                  activeChatCount: _chatCounts[item['id'] as String] ?? 0,
                  hasEscalation: _hasEscalation[item['id'] as String] ?? false,
                  hasEmergency: _hasEmergency[item['id'] as String] ?? false,
                  conversationPreviews:
                      _conversationPreviews[item['id'] as String] ?? [],
                  onOpenChat: (bookingId) =>
                      _openChatLive(bookingId, item['id'] as String),
                  onOpenExpanded: () => _openExpandedView(item),
                  onOpenSettings: () => _openDrawer(item),
                  onGuestLink: () => _openGuestLink(item),
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
