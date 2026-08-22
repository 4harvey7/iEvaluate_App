// lib/core/navigation/role_nav_config.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// SINGLE SOURCE OF TRUTH for role-based navigation.
//
// To add a new role      → add a value to UserRole and an entry to roleNavConfigs.
// To add a new tab       → add a NavItem to the relevant bottomNavItems list.
// To add a new drawer item → add a NavItem to the relevant drawerItems list.
// Do NOT scatter nav logic anywhere else. All roads lead here.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Role screens — SAO Admin
import '../../sao_admin/admin_dashboard.dart';
import '../../sao_admin/user_management_screen.dart';
import '../../sao_admin/personnel_management_screen.dart';
import '../../sao_admin/performance_analysis_screen.dart';
import '../../sao_admin/manage_subjects_screen.dart';
import '../../sao_admin/manage_departments_screen.dart';
import '../../sao_admin/live_system_metrics_screen.dart';
import '../../sao_admin/system_audit_screen.dart';
import '../../sao_admin/import_errors_screen.dart';
import '../../sao_admin/sao_admin_settings.dart';

// Role screens — Dept Head
import '../../dept_head/department_dashboard_screen.dart';
import '../../dept_head/faculty_roster_screen.dart';
import '../../dept_head/subject_analytics_screen.dart';
import '../../dept_head/intervention_reports_screen.dart';
import '../../dept_head/dept_head_settings_screen.dart';

// Role screens — Instructor
import '../../instructor/instructor_dashboard.dart';
import '../../instructor/my_subjects_screen.dart';
import '../../instructor/student_feedback_screen.dart';
import '../../instructor/past_semesters_screen.dart';
import '../../instructor/instructor_settings_screen.dart';
import '../../instructor/providers/subjects_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UserRole enum — add new roles here only.
// ─────────────────────────────────────────────────────────────────────────────
enum UserRole {
  saoAdmin,
  instructor,
  deptHead,

  /// TECHNICAL DEBT: The gatherer role bypasses MainScaffold's NavigationBar
  /// entirely. See main_scaffold.dart for the full explanation.
  gatherer,
}

// ─────────────────────────────────────────────────────────────────────────────
// NavItem — one entry in either the bottom nav bar or the side drawer.
//
// [builder] receives the userId string so screens that require it can be
// constructed. Screens that take no userId use `_` to ignore it.
// ─────────────────────────────────────────────────────────────────────────────
class NavItem {
  final IconData icon;
  final String label;

  /// Builds the destination screen. Receives the logged-in user's ID.
  final Widget Function(String userId) builder;

  const NavItem({
    required this.icon,
    required this.label,
    required this.builder,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// RoleNavConfig — complete nav spec for one role.
// ─────────────────────────────────────────────────────────────────────────────
class RoleNavConfig {
  /// Screens shown as tabs in the bottom NavigationBar.
  final List<NavItem> bottomNavItems;

  /// Screens shown as rows in the side Drawer (Logout is always appended by
  /// MainScaffold — do not add it here).
  final List<NavItem> drawerItems;

  const RoleNavConfig({
    required this.bottomNavItems,
    required this.drawerItems,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// roleNavConfigs — the actual map.  Edit this and nothing else changes.
// ─────────────────────────────────────────────────────────────────────────────
final Map<UserRole, RoleNavConfig> roleNavConfigs = {
  // ── SAO Admin ─────────────────────────────────────────────────────────────
  UserRole.saoAdmin: RoleNavConfig(
    bottomNavItems: [
      NavItem(
        icon: Icons.dashboard_rounded,
        label: 'Dashboard',
        builder: (uid) => AdminDashboardScreen(userId: uid),
      ),
      NavItem(
        icon: Icons.group_rounded,
        label: 'Users',
        builder: (_) => const UserManagementScreen(),
      ),
      NavItem(
        icon: Icons.manage_accounts_rounded,
        label: 'Personnel',
        builder: (_) => const PersonnelManagementScreen(),
      ),
      NavItem(
        icon: Icons.analytics_rounded,
        label: 'Analytics',
        builder: (_) => const PerformanceAnalysisScreen(),
      ),
    ],
    drawerItems: [
      NavItem(
        icon: Icons.book_rounded,
        label: 'Subject Management',
        builder: (_) => const ManageSubjectsScreen(),
      ),
      NavItem(
        icon: Icons.domain_rounded,
        label: 'Department Management',
        builder: (_) => const ManageDepartmentsScreen(),
      ),
      NavItem(
        icon: Icons.monitor_heart_rounded,
        label: 'Live System Metrics',
        builder: (_) => const LiveSystemMetricsScreen(),
      ),
      NavItem(
        icon: Icons.security_rounded,
        label: 'Security Audit Logs',
        builder: (_) => const SystemAuditScreen(),
      ),
      NavItem(
        icon: Icons.error_outline_rounded,
        label: 'Import Errors',
        builder: (_) => const ImportErrorsScreen(),
      ),
      NavItem(
        icon: Icons.settings_rounded,
        label: 'System Settings',
        builder: (_) => const SaoAdminSettings(),
      ),
    ],
  ),

  // ── Dept Head ─────────────────────────────────────────────────────────────
  UserRole.deptHead: RoleNavConfig(
    bottomNavItems: [
      NavItem(
        icon: Icons.dashboard_rounded,
        label: 'Overview',
        builder: (uid) => DepartmentDashboardScreen(userId: uid),
      ),
      NavItem(
        icon: Icons.people_rounded,
        label: 'Faculty',
        builder: (uid) => FacultyRosterScreen(userId: uid),
      ),
      NavItem(
        icon: Icons.library_books_rounded,
        label: 'Subjects',
        builder: (uid) => SubjectAnalyticsScreen(userId: uid),
      ),
      NavItem(
        icon: Icons.gavel_rounded,
        label: 'Reports',
        builder: (uid) => InterventionReportsScreen(userId: uid),
      ),
    ],
    drawerItems: [
      NavItem(
        icon: Icons.settings_rounded,
        label: 'Account Settings',
        builder: (_) => const DeptHeadSettingsScreen(),
      ),
    ],
  ),

  // ── Instructor ────────────────────────────────────────────────────────────
  //
  // NOTE: MainScaffold wraps all instructor tab bodies in a
  // ChangeNotifierProvider<SubjectsProvider> so every screen in this role
  // can call context.read/watch<SubjectsProvider>() safely.
  UserRole.instructor: RoleNavConfig(
    bottomNavItems: [
      NavItem(
        icon: Icons.dashboard_rounded,
        label: 'Dashboard',
        builder: (uid) => InstructorDashboardScreen(userId: uid),
      ),
      NavItem(
        icon: Icons.menu_book_rounded,
        label: 'My Subjects',
        builder: (uid) => MySubjectsScreen(userId: uid),
      ),
      NavItem(
        icon: Icons.forum_rounded,
        label: 'Feedback',
        // termId left null — MySubjectsScreen/StudentFeedbackScreen fetch the
        // current term themselves via SystemSettingsService.
        builder: (uid) => StudentFeedbackScreen(userId: uid),
      ),
      NavItem(
        icon: Icons.history_rounded,
        label: 'Past Terms',
        builder: (uid) => PastSemestersScreen(userId: uid),
      ),
    ],
    drawerItems: [
      NavItem(
        icon: Icons.settings_rounded,
        label: 'Account Settings',
        builder: (_) => const InstructorSettingsScreen(),
      ),
    ],
  ),

  // ── Gatherer ──────────────────────────────────────────────────────────────
  // TECHNICAL DEBT: The gatherer role has no RoleNavConfig entry here because
  // DataGathererScreen self-manages all 5 of its own tabs internally
  // (Dashboard, Scanner, Validation, Sync Queue, Settings). Decomposing it
  // into separate tab bodies that MainScaffold can control would require a
  // large internal refactor of DataGathererScreen's shared state (scan queue,
  // N8N upload status, sync pause flag, etc.).
  //
  // For now the gatherer is passed through as-is from main.dart without going
  // through MainScaffold. See screenForRole() in main.dart.
  //
  // When this debt is paid, add a full RoleNavConfig here and route the
  // gatherer through MainScaffold like every other role.
};

// ─────────────────────────────────────────────────────────────────────────────
// Helper — resolve a raw role string (from the DB / AuthResult) to UserRole.
// Add new string variants here when the DB grows more role names.
// ─────────────────────────────────────────────────────────────────────────────
UserRole? roleFromString(String? raw) {
  switch (raw?.toUpperCase().trim()) {
    case 'SAO_ADMIN':
      return UserRole.saoAdmin;
    case 'FULL-TIME':
    case 'PART-TIME':
    case 'INSTRUCTOR':
      return UserRole.instructor;
    case 'DEPARTMENT-HEAD':
    case 'DEPARTMENT_HEAD':
    case 'DEAN':
      return UserRole.deptHead;
    case 'SAO_STAFF':
      return UserRole.gatherer;
    default:
      return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper — wrap a widget in SubjectsProvider when the role needs it.
// Currently only the instructor role uses SubjectsProvider.
// ─────────────────────────────────────────────────────────────────────────────
Widget wrapWithRoleProviders(UserRole role, Widget child) {
  if (role == UserRole.instructor) {
    return ChangeNotifierProvider(
      create: (_) => SubjectsProvider(),
      child: child,
    );
  }
  return child;
}
