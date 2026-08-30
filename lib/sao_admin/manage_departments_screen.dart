// lib/sao_admin/manage_departments_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../core/navigation/main_scaffold.dart';
import '../widgets/safe_button.dart';
import '../widgets/apple_ui.dart';


class ManageDepartmentsScreen extends StatefulWidget {
  const ManageDepartmentsScreen({super.key});

  @override
  State<ManageDepartmentsScreen> createState() =>
      _ManageDepartmentsScreenState();
}

class _ManageDepartmentsScreenState extends State<ManageDepartmentsScreen> {
  final _supabase = Supabase.instance.client;
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  List<Map<String, dynamic>> _departments = [];
  bool _isLoading = true;

  // When non-null we are in edit mode

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────

  Future<void> _loadDepartments() async {
    setState(() => _isLoading = true);
    try {
      final data = await _supabase
          .from('department_name')
          .select('id, d_name, d_code')
          .order('d_name', ascending: true);
      if (mounted) {
        setState(() {
          _departments = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('ManageDepts load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Department Detail Sheet ────────────────────────────────────

  void _showDepartmentDetail(Map<String, dynamic> dept) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DepartmentDetailSheet(
        deptId: dept['id'],
        deptName: dept['d_name'] as String,
      ),
    );
  }

  // ── CRUD ──────────────────────────────────────────────────────

  void _showAddEditDialog([Map<String, dynamic>? dept]) {
    if (dept != null) {
      _nameController.text = dept['d_name'];
      _codeController.text = dept['d_code'] ?? '';
    } else {
      _nameController.clear();
      _codeController.clear();
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool isSaving = false;
        final isEditing = dept != null;

        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              Icon(isEditing ? Icons.edit_rounded : Icons.add_business,
                  color: isEditing ? AppColors.warning : AppColors.primary),
              const SizedBox(width: 8),
              Text(isEditing ? 'Edit Department' : 'Add Department',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
            content: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isEditing)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline,
                                color: AppColors.warning, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                                child: Text(
                                    'Reminder: Are you sure you want to add a new department? Please ensure the official name is correct.',
                                    style: TextStyle(
                                        color: AppColors.warning, fontSize: 13))),
                          ],
                        ),
                      ),
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Department Name *',
                        hintText: 'e.g. College of Engineering...',
                        prefixIcon: const Icon(Icons.domain, color: AppColors.primary),
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (v.trim().length < 3) return 'At least 3 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _codeController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Department Code *',
                        hintText: 'e.g. CTE, CS, IT...',
                        prefixIcon: const Icon(Icons.badge_outlined, color: AppColors.primary),
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving
                    ? null
                    : () {
                        _clearForm();
                        Navigator.pop(context);
                      },
                child: const Text('Cancel',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (!(_formKey.currentState?.validate() ?? false)) {
                          return;
                        }
                        final name = _nameController.text.trim();
                        // Captured up front: everything below this point runs
                        // after at least one await.
                        final navigator = Navigator.of(context);

                        // Show confirmation only when adding
                        if (!isEditing) {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              title: const Row(children: [
                                Icon(Icons.help_outline,
                                    color: AppColors.primary),
                                SizedBox(width: 8),
                                Text('Confirm Add'),
                              ]),
                              content: RichText(
                                text: TextSpan(
                                  style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textPrimary),
                                  children: [
                                    const TextSpan(
                                        text:
                                            'Are you sure you want to add '),
                                    TextSpan(
                                      text: '"$name"',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary),
                                    ),
                                    const TextSpan(
                                        text: ' as a new department?'),
                                  ],
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, false),
                                  child: const Text('Cancel',
                                      style: TextStyle(
                                          color: AppColors.textSecondary)),
                                ),
                                ElevatedButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(8)),
                                  ),
                                  child: const Text('Yes, Add',
                                      style:
                                          TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true) return;
                        }

                        setState(() => isSaving = true);

                        try {
                          final code = _codeController.text.trim().toUpperCase();
                          if (isEditing) {
                            await _supabase
                                .from('department_name')
                                .update({'d_name': name, 'd_code': code}).eq('id', dept['id']);
                            _showSnack('Department updated successfully');
                          } else {
                            final existing = await _supabase
                                .from('department_name')
                                .select('id')
                                .ilike('d_name', name)
                                .maybeSingle();
                            if (existing != null) {
                              _showSnack('Department already exists', isError: true);
                              setState(() => isSaving = false);
                              return;
                            }
                            await _supabase
                                .from('department_name')
                                .insert({'d_name': name, 'd_code': code});
                            _showSnack('Department added successfully');
                          }
                          navigator.pop();
                          _clearForm();
                          await _loadDepartments();
                        } catch (e) {
                          _showSnack('Error: $e', isError: true);
                          setState(() => isSaving = false);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isEditing ? AppColors.warning : AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(isEditing ? 'Save' : 'Add',
                        style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );
  }

  void _startEdit(Map<String, dynamic> dept) {
    _showAddEditDialog(dept);
  }

  void _clearForm() {
    _nameController.clear();
    _codeController.clear();
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
          tooltip: 'Open menu',
          onPressed: () => MainScaffold.drawerKey.currentState?.openDrawer(),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Department Management',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold)),
            Text('Add or edit departments',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
        actions: [
          SafeIconButton(
            icon: const Icon(Icons.add_business, color: AppColors.primary),
            onPressed: () async { _showAddEditDialog(); },
            tooltip: 'Add Department',
          ),
          SafeIconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            onPressed: _loadDepartments,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const AppleLoadingState(label: 'Loading departments…')
          : RefreshIndicator(
              onRefresh: _loadDepartments,
              color: AppColors.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppleSectionHeader(
                      title: 'All Departments (${_departments.length})',
                      subtitle: 'Select a department to review its head, instructors, and evaluation health.',
                    ),
                    const SizedBox(height: 12),
                    _departments.isEmpty
                        ? _buildEmptyState()
                        : _buildDepartmentList(),
                  ],
                ),
              ),
            ),
    );
  }



  Widget _buildDepartmentList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _departments.length,
      itemBuilder: (context, index) {
        final dept = _departments[index];

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.solidSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.glassBorder,
              width: 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: AppColors.glassShadow,
                blurRadius: 22,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _showDepartmentDetail(dept),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              child: Row(children: [
                // Avatar
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: Text(
                    dept['d_name'].toString().isNotEmpty
                        ? dept['d_name'].toString()[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Name & hint
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dept['d_name'],
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap to view details',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Edit
                IconButton(
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  onPressed: () => _startEdit(dept),
                  tooltip: 'Edit',
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return const AppleEmptyState(
      icon: Icons.domain_disabled_outlined,
      title: 'No departments yet',
      message: 'Use Add Department to create the first academic unit.',
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Department Detail Bottom Sheet
// ═══════════════════════════════════════════════════════════════

class _DepartmentDetailSheet extends StatefulWidget {
  final dynamic deptId;
  final String deptName;

  const _DepartmentDetailSheet({
    required this.deptId,
    required this.deptName,
  });

  @override
  State<_DepartmentDetailSheet> createState() =>
      _DepartmentDetailSheetState();
}

class _DepartmentDetailSheetState extends State<_DepartmentDetailSheet> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String _headName = 'No department head assigned';
  double _deptScore = 0.0;
  int _totalEvals = 0;
  List<Map<String, dynamic>> _instructors = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // 1. Get active term
      final settings = await _supabase
          .from('system_settings')
          .select('current_term_id')
          .maybeSingle();
      final termId = settings?['current_term_id'];

      // 2. Get all users in this department with their roles
      final members = await _supabase
          .from('department_table')
          .select('''
            user_id,
            roles:roles(id, Roles),
            user_info!user_id(first_name, last_name)
          ''')
          .eq('Department_name_ID', widget.deptId);

      String headName = 'No department head assigned';
      final List<Map<String, dynamic>> instructors = [];

      for (final m in (members as List)) {
        final ui = m['user_info'];
        if (ui == null) continue;
        final name =
            '${ui['first_name'] ?? ''} ${ui['last_name'] ?? ''}'.trim();
        final roleRaw = m['roles'];
        final roleName = roleRaw is Map
            ? (roleRaw['Roles'] ?? '').toString()
            : '';

        if (roleName.toLowerCase().contains('head') ||
            roleName.toLowerCase().contains('dean')) {
          headName = name;
        } else {
          instructors.add({
            'id': m['user_id'],
            'name': name,
            'role': roleName,
            'score': 0.0,
            'evals': 0,
          });
        }
      }

      // 3. Pull scores for all members from overall_total_survey
      if (termId != null && members.isNotEmpty) {
        final allIds = (members as List)
            .where((m) => m['user_id'] != null)
            .map((m) => m['user_id'] as String)
            .toList();

        final scores = await _supabase
            .from('overall_total_survey')
            .select(
                'instructor_id, overall_mean, combined_score_mean, management_mean, performance_mean, total_responses')
            .eq('term_id', termId)
            .filter('instructor_id', 'in', allIds);

        double totalScore = 0;
        int totalEvals = 0;
        int scoreCount = 0;

        for (final s in (scores as List)) {
          final id = s['instructor_id'] as String?;
          final overall = (s['combined_score_mean'] as num?)?.toDouble() ?? (s['overall_mean'] as num?)?.toDouble() ?? 0.0;
          final mgmt =
              (s['management_mean'] as num?)?.toDouble() ?? 0.0;
          final perf =
              (s['performance_mean'] as num?)?.toDouble() ?? 0.0;
          final evalsCount = (s['total_responses'] as int?) ?? 0;

          final computedScore = overall > 0
              ? overall
              : (mgmt > 0 || perf > 0)
                  ? (mgmt + perf) / 2
                  : 0.0;

          totalScore += computedScore;
          totalEvals += evalsCount;
          if (computedScore > 0) scoreCount++;

          // Attach score to instructor
          for (final inst in instructors) {
            if (inst['id'] == id) {
              inst['score'] =
                  double.parse(computedScore.toStringAsFixed(2));
              inst['evals'] = evalsCount;
            }
          }
        }

        // Sort instructors: highest score first
        instructors.sort((a, b) =>
            (b['score'] as double).compareTo(a['score'] as double));

        final deptScore =
            scoreCount > 0 ? totalScore / scoreCount : 0.0;

        if (mounted) {
          setState(() {
            _headName = headName;
            _deptScore =
                double.parse(deptScore.toStringAsFixed(2));
            _totalEvals = totalEvals;
            _instructors = instructors;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _headName = headName;
            _instructors = instructors;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('DeptDetailSheet error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _scoreColor(double score) {
    if (score >= 4.0) return AppColors.success;
    if (score >= 3.0) return AppColors.warning;
    if (score > 0) return AppColors.error;
    return AppColors.textTertiary;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.borderHairline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: const BoxDecoration(
              color: AppColors.textPrimary,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.domain,
                    color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.deptName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const Text('Department Overview',
                        style: TextStyle(
                            color: Colors.white60, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white60),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),

          // Body
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary))
                : ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(20),
                    children: [
                      // ── Score + Head row ─────────────────────
                      Row(children: [
                        // Score card
                        Expanded(
                          child: _infoCard(
                            icon: Icons.star_rounded,
                            iconColor: _deptScore >= 4.0
                                ? AppColors.success
                                : _deptScore >= 3.0
                                    ? AppColors.warning
                                    : _deptScore > 0
                                        ? AppColors.error
                                        : AppColors.textTertiary,
                            label: 'Dept. Average',
                            value: _deptScore > 0
                                ? _deptScore.toStringAsFixed(2)
                                : '—',
                            sub: '/ 5.0',
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Total evals
                        Expanded(
                          child: _infoCard(
                            icon: Icons.assignment_turned_in_outlined,
                            iconColor: AppColors.primary,
                            label: 'Total Evals',
                            value: '$_totalEvals',
                            sub: 'this term',
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Instructor count
                        Expanded(
                          child: _infoCard(
                            icon: Icons.people_outline,
                            iconColor: AppColors.primaryDeep,
                            label: 'Instructors',
                            value: '${_instructors.length}',
                            sub: 'in dept.',
                          ),
                        ),
                      ]),
                      const SizedBox(height: 20),

                      // ── Department Head ───────────────────────
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: AppColors.primary
                                  .withValues(alpha: 0.3)),
                        ),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.primary
                                  .withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.person_pin,
                                color: AppColors.primary, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const Text('Department Head',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w500)),
                                const SizedBox(height: 2),
                                Text(_headName,
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary)),
                              ],
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 24),

                      // ── Instructors List ──────────────────────
                      Row(children: [
                        const Icon(Icons.school_outlined,
                            color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Instructors (${_instructors.length})',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppColors.textPrimary),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      if (_instructors.isEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No instructors assigned to this department yet.',
                              style: TextStyle(
                                  color: AppColors.textSecondary
                                      .withValues(alpha: 0.7),
                                  fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      else
                        ...List.generate(_instructors.length, (i) {
                          final inst = _instructors[i];
                          final score =
                              (inst['score'] as double?) ?? 0.0;
                          final evals = (inst['evals'] as int?) ?? 0;
                          final color = _scoreColor(score);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: score > 0 && score < 3.0
                                      ? AppColors.error
                                          .withValues(alpha: 0.3)
                                      : AppColors.borderHairline),
                            ),
                            child: Row(children: [
                              // Rank badge
                              SizedBox(
                                width: 28,
                                child: Text('#${i + 1}',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: i == 0
                                            ? AppColors.success
                                            : AppColors.textTertiary)),
                              ),
                              // Avatar
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: color
                                    .withValues(alpha: 0.12),
                                child: Text(
                                  inst['name'].toString().isNotEmpty
                                      ? inst['name']
                                          .toString()[0]
                                          .toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                      color: color,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Name & role
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(inst['name'],
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color:
                                                AppColors.textPrimary),
                                        overflow: TextOverflow.ellipsis),
                                    if ((inst['role'] as String)
                                        .isNotEmpty)
                                      Text(inst['role'],
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors
                                                  .textSecondary),
                                          overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                              // Score badge
                              Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    score > 0
                                        ? score.toStringAsFixed(2)
                                        : '—',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: color),
                                  ),
                                  Text(
                                    evals > 0 ? '$evals evals' : 'No data',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ]),
                          );
                        }),
                    ],
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String sub,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderHairline),
      ),
      child: Column(children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: iconColor)),
        Text(sub,
            style: const TextStyle(
                fontSize: 10, color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500),
            textAlign: TextAlign.center),
      ]),
    );
  }
}
