// lib/core/navigation/main_scaffold.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// MainScaffold — the shared shell for all non-gatherer roles.
//
// Responsibilities:
//   • Reads the RoleNavConfig for the current role from role_nav_config.dart
//   • Renders a Material 3 NavigationBar (bottom) with per-tab nested Navigators
//     so Android back button pops sub-screens before exiting a tab
//   • Renders a NavigationDrawer (side) with drawer items + Logout pinned at bottom
//   • Uses IndexedStack to preserve each tab's Navigator state when switching tabs
//
// ─── TECHNICAL DEBT: Gatherer passthrough ────────────────────────────────────
// The gatherer role (UserRole.gatherer) BYPASSES this widget entirely.
// DataGathererScreen self-manages 5 internal tabs (Dashboard, Scanner,
// Validation, Sync Queue, Settings) using its own _currentIndex + a manual
// screens-list pattern.  All of those tabs share tightly coupled mutable state:
//   - _localQueue     (scan task list, persisted to SharedPreferences)
//   - _isSyncing / _isPaused  (upload flow control flags)
//   - _n8nOnline      (server health status)
//   - _scannedToday   (progress counter driving the dashboard progress bar)
//
// Decomposing that into separate top-level tab bodies that MainScaffold can
// control would require extracting all shared state into a Provider or
// InheritedWidget, which is a sizeable refactor outside the scope of this PR.
//
// Resolution path: lift DataGathererScreen's shared state into a
// GathererStateProvider, then give each internal view its own NavItem entry
// in roleNavConfigs[UserRole.gatherer], and route the gatherer through
// MainScaffold like the other roles.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../login_screen.dart';
import '../../core/services/auth_service.dart';
import '../services/push_notification_service.dart';
import '../../widgets/logout_confirmation_dialog.dart';
import '../../widgets/apple_ui.dart';
import 'role_nav_config.dart';
import 'role_switch_screen.dart';
import '../../gatherer/data_gatherer_screen.dart';

class MainScaffold extends StatefulWidget {
  final UserRole role;
  final String userId;

  /// If the user switched roles (e.g. Dept Head viewing as Instructor),
  /// this tracks their real role so they can return to it.
  final UserRole? originalRole;

  /// Static key so any inner dashboard screen can call
  ///   MainScaffold.drawerKey.currentState?.openDrawer()
  /// to open the outer drawer even when nested inside its own Scaffold.
  /// Now dynamically tracked to support role switching (multiple scaffolds).
  static GlobalKey<ScaffoldState>? _activeDrawerKey;
  static GlobalKey<ScaffoldState> get drawerKey {
    _activeDrawerKey ??= GlobalKey<ScaffoldState>();
    return _activeDrawerKey!;
  }

  const MainScaffold({
    super.key,
    required this.role,
    required this.userId,
    this.originalRole,
  });

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  final _authService = AuthService();

  /// Which bottom-nav tab is currently visible.
  int _selectedIndex = 0;

  /// True while a drawer-pushed screen is on top of the active tab's Navigator.
  /// When true, the bottom nav shows NO item highlighted (index = -1 effectively).
  bool _drawerRouteActive = false;

  /// One `GlobalKey<NavigatorState>` per bottom-nav tab.
  /// Kept in a list so we can address the active tab's navigator directly.
  late final List<GlobalKey<NavigatorState>> _navKeys;

  /// One NavigatorObserver per tab (needed only if you want route-aware widgets
  /// inside a tab; kept as an empty default for now).
  late final List<List<NavigatorObserver>> _navObservers;

  String _userName = '';

  /// The unique Scaffold key for this specific instance of MainScaffold.
  late final GlobalKey<ScaffoldState> _myDrawerKey;

  @override
  void initState() {
    super.initState();
    _myDrawerKey = GlobalKey<ScaffoldState>();
    MainScaffold._activeDrawerKey = _myDrawerKey;

    final config = roleNavConfigs[widget.role]!;
    _navKeys = List.generate(
      config.bottomNavItems.length,
      (_) => GlobalKey<NavigatorState>(),
    );
    _navObservers = List.generate(config.bottomNavItems.length, (_) => []);
    _fetchUserInfo();

    // Initialize push notifications after user login
    try {
      PushNotificationService().init();
    } catch (e) {
      debugPrint('Error init push notifications: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // If we pop back to this screen, we are the active one again.
    if (ModalRoute.of(context)?.isCurrent == true) {
      MainScaffold._activeDrawerKey = _myDrawerKey;
    }
  }

  Future<void> _fetchUserInfo() async {
    try {
      final info = await _authService.getUserInfo(widget.userId);
      if (mounted && info != null) {
        setState(() {
          _userName = '${info['first_name']} ${info['last_name']}';
        });
      }
    } catch (_) {}
  }

  // ── Logout ────────────────────────────────────────────────────────────────
  Future<void> _handleLogout(BuildContext ctx) async {
    final navigator = Navigator.of(ctx);
    final confirm = await showLogoutConfirmationDialog(ctx);
    if (confirm == true) {
      if (!ctx.mounted) return;
      showLoggingOutOverlay(ctx);
      await Future.delayed(
        const Duration(milliseconds: 1500),
      ); // wait for overlay
      await _authService.signOut();
      if (mounted) {
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  // ── Build one nested Navigator (one per bottom-nav tab) ───────────────────
  // Each tab gets its own Navigator so pushing sub-screens (e.g. SubjectDetail
  // from My Subjects) stays inside the tab and the back button pops them before
  // switching tabs.
  Widget _buildTabNavigator(int index, NavItem item) {
    return Navigator(
      key: _navKeys[index],
      observers: _navObservers[index],
      onGenerateRoute: (settings) {
        // The root route for this tab.
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => item.builder(widget.userId),
        );
      },
    );
  }

  // ── Drawer item builder ───────────────────────────────────────────────────
  Widget _buildDrawerNavItem(
    BuildContext ctx,
    NavItem item, {
    bool isLogout = false,
  }) {
    final color = isLogout ? AppColors.error : AppColors.textPrimary;
    return ListTile(
      leading: Icon(item.icon, color: color),
      title: Text(
        item.label,
        style: TextStyle(color: color, fontWeight: FontWeight.w500),
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        Navigator.pop(ctx); // close the drawer first
        if (!isLogout) {
          // Mark that a drawer screen is now active → unhighlight bottom nav.
          setState(() => _drawerRouteActive = true);
          // Push the drawer destination on top of the currently active tab's
          // Navigator, so the back button returns to wherever the user was.
          _navKeys[_selectedIndex].currentState
              ?.push(MaterialPageRoute(builder: (_) => item.builder(widget.userId)))
              .then((_) {
            // User popped back — check if tab is back at root, restore highlight.
            final innerNav = _navKeys[_selectedIndex].currentState;
            if (innerNav != null && !innerNav.canPop()) {
              if (mounted) setState(() => _drawerRouteActive = false);
            }
          });
        }
      },
    );
  }

  // ── Drawer ────────────────────────────────────────────────────────────────
  Widget _buildDrawer(BuildContext ctx, RoleNavConfig config) {
    final displayName = _userName.isNotEmpty ? _userName : '...';
    final initials = _userName.isNotEmpty
        ? _userName
              .trim()
              .split(' ')
              .take(2)
              .map((w) => w.isNotEmpty ? w[0] : '')
              .join()
        : '?';

    return Drawer(
      backgroundColor: AppColors.surface,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: AppColors.heroGradient,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.textInvertedFaint,
                  child: Text(
                    initials.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.surface,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  displayName,
                  style: const TextStyle(
                    color: AppColors.surface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _roleDisplayName(widget.originalRole ?? widget.role),
                  style: const TextStyle(
                    color: AppColors.textInvertedDim,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // ── Drawer nav items ────────────────────────────────────────────
          ...config.drawerItems.map((item) => _buildDrawerNavItem(ctx, item)),

          const Divider(),

          // ── Role Switcher ────────────────────────────────────────────────
          // Allow SAO Admin to jump to Gatherer Screen
          if (widget.role == UserRole.saoAdmin && widget.originalRole == null)
            ListTile(
              leading: const Icon(
                Icons.document_scanner_rounded,
                color: AppColors.primary,
              ),
              title: const Text(
                'Switch to Data Gatherer View',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx); // Close drawer
                Navigator.push(
                  ctx,
                  PageRouteBuilder(
                    pageBuilder: (_, _, _) => RoleSwitchScreen(
                      targetRoleName: 'Data Gatherer',
                      targetIcon: Icons.document_scanner_rounded,
                      onComplete: (switchCtx) {
                        Navigator.pushReplacement(
                          switchCtx,
                          PageRouteBuilder(
                            pageBuilder: (_, _, _) => DataGathererScreen(
                              userId: widget.userId,
                              originalRole: UserRole.saoAdmin,
                            ),
                            transitionsBuilder: (_, anim, _, child) =>
                                FadeTransition(opacity: anim, child: child),
                            transitionDuration: const Duration(
                              milliseconds: 300,
                            ),
                          ),
                        );
                      },
                    ),
                    transitionsBuilder: (_, anim, _, child) =>
                        FadeTransition(opacity: anim, child: child),
                  ),
                );
              },
            ),

          // Allow Dept Head to jump into their own Instructor Dashboard
          if (widget.role == UserRole.deptHead && widget.originalRole == null)
            ListTile(
              leading: const Icon(
                Icons.switch_account_rounded,
                color: AppColors.primary,
              ),
              title: const Text(
                'Switch to Instructor View',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx); // Close drawer
                // Push the transition screen first
                Navigator.push(
                  ctx,
                  PageRouteBuilder(
                    pageBuilder: (_, _, _) => RoleSwitchScreen(
                      targetRoleName: 'Instructor',
                      targetIcon: Icons.menu_book_rounded,
                      onComplete: (switchCtx) {
                        // Once animation is done, replace the transition screen with the actual Instructor view
                        Navigator.pushReplacement(
                          switchCtx,
                          PageRouteBuilder(
                            pageBuilder: (_, _, _) => MainScaffold(
                              role: UserRole.instructor,
                              userId: widget.userId,
                              originalRole: UserRole.deptHead,
                            ),
                            transitionsBuilder: (_, anim, _, child) =>
                                FadeTransition(opacity: anim, child: child),
                            transitionDuration: const Duration(
                              milliseconds: 300,
                            ),
                          ),
                        );
                      },
                    ),
                    transitionsBuilder: (_, anim, _, child) =>
                        FadeTransition(opacity: anim, child: child),
                  ),
                );
              },
            ),

          // If they are currently viewing as an Instructor, let them go back
          if (widget.originalRole != null)
            ListTile(
              leading: const Icon(
                Icons.keyboard_return_rounded,
                color: AppColors.primary,
              ),
              title: Text(
                'Return to ${_roleDisplayName(widget.originalRole!)}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx); // Close drawer
                // Push the transition screen over the current UI
                Navigator.push(
                  ctx,
                  PageRouteBuilder(
                    pageBuilder: (_, _, _) => RoleSwitchScreen(
                      targetRoleName: _roleDisplayName(widget.originalRole!),
                      targetIcon:
                          Icons.account_balance_rounded, // or assignment_ind
                      onComplete: (switchCtx) {
                        // Safely pop twice to return to the original MainScaffold
                        int count = 0;
                        Navigator.of(switchCtx).popUntil((_) => count++ >= 2);
                      },
                    ),
                    transitionsBuilder: (_, anim, _, child) =>
                        FadeTransition(opacity: anim, child: child),
                  ),
                );
              },
            ),

          if ((widget.role == UserRole.deptHead &&
                  widget.originalRole == null) ||
              (widget.role == UserRole.saoAdmin &&
                  widget.originalRole == null) ||
              widget.originalRole != null)
            const Divider(),

          // ── Logout — always pinned at the bottom ────────────────────────
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: AppColors.error),
            title: const Text(
              'Log Out',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: () => _handleLogout(ctx),
          ),
        ],
      ),
    );
  }

  // ── Role display helpers ──────────────────────────────────────────────────
  String _roleDisplayName(UserRole role) {
    switch (role) {
      case UserRole.saoAdmin:
        return 'SAO Administrator';
      case UserRole.instructor:
        return 'Instructor';
      case UserRole.deptHead:
        return 'Department Head';
      case UserRole.gatherer:
        return 'Data Gatherer';
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final config = roleNavConfigs[widget.role]!;

    // Wrap in the role-specific providers (e.g. SubjectsProvider for instructors).
    return wrapWithRoleProviders(
      widget.role,
      // PopScope intercepts Android back-button presses.
      // If the active tab's inner Navigator has pages to pop, we pop them first
      // and cancel the system pop (canPop: false + manual pop inside the callback).
      PopScope(
        canPop: false, // we decide manually in the callback
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          final innerNav = _navKeys[_selectedIndex].currentState;
          if (innerNav != null && innerNav.canPop()) {
            innerNav.pop(); // pop sub-screen inside the active tab
            // If the drawer screen was active and we just popped the last one,
            // restore the bottom nav highlight.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final nav = _navKeys[_selectedIndex].currentState;
              if (nav != null && !nav.canPop() && _drawerRouteActive) {
                setState(() => _drawerRouteActive = false);
              }
            });
          }
          // If nothing to pop, the system handles minimise/exit naturally.
        },
        child: Scaffold(
          key:
              _myDrawerKey, // uniquely assigned in initState, but accessible globally via getter
          backgroundColor: AppColors.background,
          drawer: _buildDrawer(context, config),
          // We use IndexedStack to preserve tab state for everyone EXCEPT Dept Head and Instructor,
          // because their tabs are incredibly heavy (charts, lists, AI clouds)
          // and keeping them all alive causes UI thread freezing during drawer slide.
          body:
              (widget.role == UserRole.deptHead ||
                  widget.role == UserRole.instructor)
              ? _buildTabNavigator(
                  _selectedIndex,
                  config.bottomNavItems[_selectedIndex],
                )
              : IndexedStack(
                  index: _selectedIndex,
                  children: List.generate(
                    config.bottomNavItems.length,
                    (i) => _buildTabNavigator(i, config.bottomNavItems[i]),
                  ),
                ),
          bottomNavigationBar: AppleFloatingTabBar(
            // When a drawer-pushed screen is on top, pass -1 so no tab is highlighted.
            selectedIndex: _drawerRouteActive ? -1 : _selectedIndex,
            onSelected: (index) {
              // Tapping a bottom nav tab always clears the drawer-screen state.
              setState(() => _drawerRouteActive = false);
              if (index == _selectedIndex) {
                // Same tab tapped — pop any sub-screens back to root
                _navKeys[index].currentState?.popUntil((r) => r.isFirst);
              } else {
                // Different tab — clear any stale pushed screens on the destination
                // tab before switching to it. Without this, drawer-pushed screens
                // (e.g. Account Settings pushed onto Dashboard tab) would still show
                // when returning to that tab from another tab.
                _navKeys[index].currentState?.popUntil((r) => r.isFirst);
                setState(() => _selectedIndex = index);
              }
            },
            items: config.bottomNavItems
                .map(
                  (item) => AppleTabItem(
                    icon: item.icon,
                    selectedIcon: item.icon,
                    label: item.label,
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}
