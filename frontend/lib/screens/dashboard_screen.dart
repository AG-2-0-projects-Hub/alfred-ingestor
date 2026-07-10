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
import '../widgets/feedback_dialog.dart';
import '../widgets/profile_dialog.dart';
import '../services/push_notification_service.dart';
import 'auth_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _properties = [];
  Map<String, bool> _hasEscalation = {};
  Map<String, bool> _hasEmergency = {};
  Map<String, List<Map<String, dynamic>>> _conversationPreviews = {};
  Map<String, String> _guestNamesByBooking = {};
  bool _loading = true;

  // Host impact stats (get_host_stats RPC). Null until first load.
  Map<String, dynamic>? _hostStats;
  String? _hostAvatarUrl;

  StreamSubscription? _convStreamSub;
  StreamSubscription? _guestStreamSub;
  StreamSubscription? _propertyStreamSub;
  Timer? _silentRefreshTimer;

  // Push-notification edge detection
  final Map<String, bool> _prevRequiresAttention = {};
  String _notifPermission = 'default';
  bool _showNotifChip = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notifPermission = PushNotificationService.permissionState;
    _loadHostStats();
    _loadHostAvatar();
    _loadProperties().then((_) {
      if (!mounted) return;
      _subscribeRealtime();
      // Safety net: Supabase free-tier realtime can lag or silently drop
      // updates to low-traffic tables (conversations, properties). A short
      // silent re-fetch closes any gap the streams miss, without the spinner
      // flash the old 30s reload caused.
      _silentRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (mounted) _loadProperties(silent: true);
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _convStreamSub?.cancel();
    _guestStreamSub?.cancel();
    _propertyStreamSub?.cancel();
    _silentRefreshTimer?.cancel();
    super.dispose();
  }

  // Supabase realtime WebSockets can silently drop while a tab is backgrounded.
  // On resume, tear down and re-subscribe so updates flow again instantly.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _convStreamSub?.cancel();
      _guestStreamSub?.cancel();
      _propertyStreamSub?.cancel();
      _subscribeRealtime();
    }
  }

  // [silent=true] skips toggling _loading so the safety-net timer and the
  // post-resolve optimistic refresh don't blank the UI. Used for background
  // syncs; user-initiated loads pass [silent=false] so the spinner shows.
  Future<void> _loadProperties({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final data = await Supabase.instance.client
          .from('properties')
          .select(
              'id, name, status, airbnb_url, created_at, master_json, file_fingerprints, Conflict_status')
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);

      final properties = List<Map<String, dynamic>>.from(data);

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
          final bid = g['booking_id'] as String?;
          if (bid != null) {
            guestNames[bid] = g['name'] as String? ?? 'Guest';
          }
        }
        final convRows = await Supabase.instance.client
            .from('conversations')
            .select(
                'id, property_id, booking_id, mode, requires_attention, escalation_reason, has_guest_message, archived_at')
            .inFilter('property_id', ids)
            .isFilter('archived_at', null)
            .order('created_at', ascending: false);

        _processConversations(convRows, guestNames, hasEscalation, hasEmergency, previews);
      }

      if (mounted) {
        setState(() {
          _properties = properties;
          _hasEscalation = hasEscalation;
          _hasEmergency = hasEmergency;
          _conversationPreviews = previews;
          _guestNamesByBooking = guestNames;
        });
      }
    } catch (e) {
      // Silent refreshes must not surface SnackBar errors — they fire every
      // 10s in the background and the user can't act on them.
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load properties: $e')),
        );
      }
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
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
      // Archived conversations drop off the dashboard active list. The load
      // path already filters these out in SQL; this also handles the realtime
      // stream path, where a cron/API archive pushes the row with archived_at set.
      if (c['archived_at'] != null) continue;
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
          if (x['has_guest_message'] != true) return 4; // pending — awaiting reply, last
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
            onResolved: _onChatResolved,
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
          final updated = _properties
              .map((p) {
                final fresh = byId[p['id'] as String];
                return fresh != null ? {...p, ...fresh} : p;
              })
              // B5: if a property is soft-deleted in another session, the stream
              // pushes the row with deleted_at set — drop it so it disappears
              // immediately instead of lingering with status "deleted".
              .where((p) => p['deleted_at'] == null)
              .toList();
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
          final names = <String, String>{};
          for (final g in rows) {
            final bid = g['booking_id'] as String?;
            if (bid != null) {
              names[bid] = g['name'] as String? ?? 'Guest';
            }
          }
          setState(() {
            _guestNamesByBooking = names;
          });
        });
  }

  // Impact stats for the dashboard strip (single RPC call, scoped to the host
  // by auth.uid() inside the SECURITY DEFINER function). Best-effort — the
  // strip simply hides if this fails.
  Future<void> _loadHostStats() async {
    try {
      final res = await Supabase.instance.client.rpc('get_host_stats');
      if (mounted && res is Map) {
        setState(() => _hostStats = Map<String, dynamic>.from(res));
      }
    } catch (_) {
      // Ignore — no stats strip rather than an error.
    }
  }

  Future<void> _loadHostAvatar() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final row = await Supabase.instance.client
          .from('host_profiles')
          .select('avatar_url')
          .eq('id', uid)
          .maybeSingle();
      if (mounted) {
        setState(() => _hostAvatarUrl = row?['avatar_url'] as String?);
      }
    } catch (_) {
      // Ignore — fall back to the default person glyph.
    }
  }

  Widget _profileGlyph(double size, Color color) {
    final url = _hostAvatarUrl;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: Colors.transparent,
        backgroundImage: NetworkImage(url),
      );
    }
    return Icon(Icons.person_outline_rounded, size: size, color: color);
  }

  Future<void> _openProfile() async {
    await ProfileDialog.show(context, propertyCount: _properties.length);
    // The host may have changed their avatar — refresh the app-bar glyph.
    _loadHostAvatar();
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
        onChatResolved: _onChatResolved,
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
      onResolved: _onChatResolved,
    );
  }

  // Optimistic dashboard refresh after the host resolves an escalation from
  // any chat dialog. Silent — no spinner. Closes the gap between the resolve
  // API returning and Supabase realtime propagating the conversation update.
  void _onChatResolved() {
    if (mounted) {
      _loadProperties(silent: true);
      _loadHostStats();
    }
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
                if (!isNarrow)
                  IconButton(
                    tooltip: 'Profile',
                    icon: _profileGlyph(22, palette.textSecondary),
                    onPressed: _openProfile,
                  ),
                IconButton(
                  tooltip: 'Send feedback',
                  icon: const Icon(Icons.feedback_outlined, size: 18),
                  onPressed: () =>
                      FeedbackDialog.show(context, route: 'dashboard'),
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
                  // Narrow screens hide the inline email (no room in the bar),
                  // so surface identity + logout together behind an account menu.
                  PopupMenuButton<String>(
                    tooltip: 'Account',
                    icon: _profileGlyph(24, palette.textSecondary),
                    color: palette.surface,
                    onSelected: (v) {
                      if (v == 'logout') _logout();
                      if (v == 'profile') _openProfile();
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem<String>(
                        enabled: false,
                        child: Text(
                          email.isEmpty ? 'Signed in' : email,
                          style: GoogleFonts.inter(
                              fontSize: 12, color: palette.textSecondary),
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem<String>(
                        value: 'profile',
                        child: Row(
                          children: [
                            Icon(Icons.person_outline_rounded,
                                size: 16, color: palette.textSecondary),
                            const SizedBox(width: 8),
                            const Text('Profile'),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'logout',
                        child: Row(
                          children: [
                            Icon(Icons.logout_rounded,
                                size: 16, color: palette.textSecondary),
                            const SizedBox(width: 8),
                            const Text('Logout'),
                          ],
                        ),
                      ),
                    ],
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
    // When the impact-stats strip is shown it sits below the app bar and clears
    // it, so the grid drops its own big top inset. When stats haven't loaded
    // (or failed), the grid keeps clearing the app bar itself.
    if (_hostStats == null) return _buildGrid();
    return Column(
      children: [
        _buildStatsStrip(palette),
        Expanded(
          child: _buildGrid(topInsetDesktop: 12, topInsetMobile: 12),
        ),
      ],
    );
  }

  Widget _buildStatsStrip(AppPalette palette) {
    final s = _hostStats;
    if (s == null) return const SizedBox.shrink();
    final replies = '${s['alfred_replies'] ?? 0}';
    final hours = _fmtHours(s['hours_saved']);
    final autop = s['autopilot_rate'] == null
        ? '—'
        : '${(s['autopilot_rate'] as num).round()}%';
    final guests = '${s['guests_helped'] ?? 0}';
    final tiles = <Widget>[
      _statTile(palette, Icons.smart_toy_outlined, replies, 'Alfred replies'),
      _statTile(palette, Icons.schedule_rounded, hours, 'Hours saved (est.)'),
      _statTile(palette, Icons.auto_mode_rounded, autop, 'Autopilot rate'),
      _statTile(palette, Icons.groups_outlined, guests, 'Guests helped'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 12, 16, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (int i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              tiles[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _statTile(
      AppPalette palette, IconData icon, String value, String label) {
    return Container(
      constraints: const BoxConstraints(minWidth: 116),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: palette.glassTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: palette.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              Text(
                label,
                style: GoogleFonts.inter(
                    fontSize: 11, color: palette.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Format hours_saved (a numeric like 1.9 or 2.0) → "1.9h" / "2h".
  String _fmtHours(dynamic v) {
    final n = (v is num) ? v : 0;
    final s = n.toStringAsFixed(1);
    return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}h';
  }

  Widget _buildGrid({
    double topInsetDesktop = kToolbarHeight + 28.0,
    double topInsetMobile = kToolbarHeight + 16.0,
  }) {
    final items = [..._properties, <String, dynamic>{}];
    final n = items.length;

    return LayoutBuilder(builder: (context, constraints) {
      final viewportW = constraints.maxWidth;
      final viewportH = constraints.maxHeight;

      // Mobile: single column, banner-style cards, scrollable.
      // Height must clear the 160px hero + name + optional alert pill + the
      // action row (+ Guest / Settings / calendar / history), PLUS leave room
      // for at least one conversation pill and the "+N more active" line above
      // the actions (340 ≈ 160 hero + ~90 pill area + name/actions). 220 clipped
      // the actions; 300 left the pill area too short so the count line was cut.
      // Vertical scroll is expected — don't try to fit everything in viewport.
      if (viewportW < 500) {
        const mobilePadH = 16.0;
        final mobilePadTop = topInsetMobile;
        const mobilePadBottom = 24.0;
        const mobileGap = 14.0;
        final mobileCardW = viewportW - mobilePadH * 2;
        const mobileCardH = 340.0;
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
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
                    activeChatCount:
                        (_conversationPreviews[item['id'] as String] ?? const [])
                            .length,
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
      final padTop = topInsetDesktop;
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
        padding: EdgeInsets.fromLTRB(padH, padTop, padH, padBottom),
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
                  activeChatCount:
                      (_conversationPreviews[item['id'] as String] ?? const [])
                          .length,
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
