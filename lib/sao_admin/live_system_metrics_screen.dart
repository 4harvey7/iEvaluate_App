// lib/sao_admin/live_system_metrics_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../core/services/system_settings_service.dart';

class LiveSystemMetricsScreen extends StatefulWidget {
  const LiveSystemMetricsScreen({super.key});

  @override
  State<LiveSystemMetricsScreen> createState() => _LiveSystemMetricsScreenState();
}

class _LiveSystemMetricsScreenState extends State<LiveSystemMetricsScreen> {
  final _supabase = Supabase.instance.client;
  final _settingsService = SystemSettingsService();

  bool _isLoading = true;
  String? _currentTermId;

  // AI Accuracy
  int _autoCount = 0;
  int _manualCount = 0;
  int _correctedCount = 0;

  // Productivity per staff
  List<Map<String, dynamic>> _staffProductivity = [];

  // Campus Evaluation Progress per department
  List<Map<String, dynamic>> _deptProgress = [];

  @override
  void initState() {
    super.initState();
    _loadAllMetrics();
  }

  Future<void> _loadAllMetrics() async {
    setState(() => _isLoading = true);
    try {
      final settings = await _settingsService.getSettings();
      _currentTermId = settings.termId;

      await Future.wait([
        _loadAiAccuracy(),
        _loadStaffProductivity(),
        _loadDeptProgress(),
      ]);
    } catch (e) {
      debugPrint('LiveMetrics error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── AI Processing Accuracy ─────────────────────────────────────
  Future<void> _loadAiAccuracy() async {
    try {
      var query = _supabase.from('raw_GoogleSheet_data_result').select('id, validation_status');
      if (_currentTermId != null) query = query.eq('term_id', _currentTermId!);
      final rows = await query;

      int auto = 0, manual = 0, corrected = 0;
      for (final r in (rows as List)) {
        final status = r['validation_status'] ?? 'auto';
        if (status == 'corrected') {
          corrected++;
        } else if (status == 'manual_review') {
          manual++;
        } else {
          auto++;
        }
      }
      if (mounted) setState(() { _autoCount = auto; _manualCount = manual; _correctedCount = corrected; });
    } catch (e) {
      debugPrint('loadAiAccuracy error: $e');
    }
  }

  // ── Data Gatherer Productivity ─────────────────────────────────
  Future<void> _loadStaffProductivity() async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day).toUtc().toIso8601String();

      // raw_GoogleSheet_data_result has sao_staff_id referencing user_info
      var query = _supabase
          .from('raw_GoogleSheet_data_result')
          .select('sao_staff_id, created_at, user_info!sao_staff_id(first_name, last_name)');
      if (_currentTermId != null) query = query.eq('term_id', _currentTermId!);
      final rows = await query;

      // Group by sao_staff_id
      final Map<String, Map<String, dynamic>> grouped = {};
      for (final r in (rows as List)) {
        final uid = r['sao_staff_id']?.toString() ?? 'unknown';
        if (!grouped.containsKey(uid)) {
          final ui = r['user_info'];
          grouped[uid] = {
            'name': ui != null ? '${ui['first_name']} ${ui['last_name']}' : 'Unknown Staff',
            'total': 0,
            'today': 0,
            'lastUpload': '',
          };
        }
        grouped[uid]!['total'] = (grouped[uid]!['total'] as int) + 1;
        final createdAt = r['created_at'] as String? ?? '';
        if (createdAt.compareTo(startOfDay) >= 0) {
          grouped[uid]!['today'] = (grouped[uid]!['today'] as int) + 1;
        }
        if (createdAt.compareTo(grouped[uid]!['lastUpload'] as String) > 0) {
          grouped[uid]!['lastUpload'] = createdAt;
        }
      }

      if (mounted) setState(() => _staffProductivity = grouped.values.toList());
    } catch (e) {
      debugPrint('loadStaffProductivity error: $e');
    }
  }

  // ── Campus Evaluation Progress per Department ──────────────────
  Future<void> _loadDeptProgress() async {
    try {
      // overall_total_survey has no department_id — join via instructor_id → department_table
      var query = _supabase.from('overall_total_survey').select('''
        total_responses,
        user_info!instructor_id(
          department_table!user_id(
            department_name!Department_name_ID(d_name)
          )
        )
      ''');
      if (_currentTermId != null) query = query.eq('term_id', _currentTermId!);
      final rows = await query;

      // Group by dept name
      final Map<String, Map<String, dynamic>> grouped = {};
      for (final r in (rows as List)) {
        final ui = r['user_info'];
        if (ui == null) continue;
        final deptTables = ui['department_table'];
        if (deptTables == null) continue;
        final deptList = deptTables is List ? deptTables : [deptTables];
        if (deptList.isEmpty || deptList[0] == null) continue;
        final deptNameObj = deptList[0]['department_name'];
        final deptName = deptNameObj is Map
            ? (deptNameObj['d_name'] ?? 'Unknown')
            : (deptNameObj is List && deptNameObj.isNotEmpty ? deptNameObj[0]['d_name'] : 'Unknown');
        if (!grouped.containsKey(deptName)) {
          grouped[deptName] = {'name': deptName, 'total': 0};
        }
        grouped[deptName]!['total'] =
            (grouped[deptName]!['total'] as int) + (r['total_responses'] as int? ?? 0);
      }

      final list = grouped.values.toList();
      final maxVal = list.isEmpty ? 1 : list.map((d) => d['total'] as int).reduce((a, b) => a > b ? a : b);
      for (final d in list) {
        d['progress'] = maxVal == 0 ? 0.0 : (d['total'] as int) / maxVal;
      }
      list.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));

      if (mounted) setState(() => _deptProgress = list);
    } catch (e) {
      debugPrint('loadDeptProgress error: $e');
      await _loadDeptProgressFallback();
    }
  }

  Future<void> _loadDeptProgressFallback() async {
    try {
      final rows = await _supabase
          .from('department_name')
          .select('id, d_name');

      if (mounted) {
        setState(() {
          _deptProgress = (rows as List).map((d) => {
            'name': d['d_name'] ?? 'Unknown',
            'total': 0,
            'progress': 0.0,
          }).toList();
        });
      }
    } catch (_) {}
  }

  // ── Helpers ───────────────────────────────────────────────────
  String _formatLastUpload(String iso) {
    if (iso.isEmpty) return 'No uploads yet';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        title: const Text('Live System Metrics', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: AppColors.primary), onPressed: _loadAllMetrics),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAllMetrics,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Real-time tracking for AI processing, staff productivity, and evaluation progress.',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 24),

                    // ── AI Processing Accuracy ─────────────────────
                    _buildSectionTitle('AI Processing Accuracy'),
                    const SizedBox(height: 12),
                    _buildAiAccuracyCard(),
                    const SizedBox(height: 32),

                    // ── Staff Productivity ─────────────────────────
                    _buildSectionTitle('Data Gatherer Productivity'),
                    const SizedBox(height: 12),
                    _buildProductivitySection(),
                    const SizedBox(height: 32),

                    // ── Campus Evaluation Progress ─────────────────
                    _buildSectionTitle('Campus Evaluation Progress'),
                    const SizedBox(height: 12),
                    _buildDeptProgressCard(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) =>
      Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold));

  Widget _buildAiAccuracyCard() {
    final total = _autoCount + _manualCount + _correctedCount;
    final autoRate = total == 0 ? 0.0 : _autoCount / total;
    final manualRate = total == 0 ? 0.0 : (_manualCount + _correctedCount) / total;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _aiStat('Auto-Processed', _autoCount, AppColors.success, Icons.check_circle_outline)),
              Container(width: 1, height: 70, color: AppColors.borderHairline),
              Expanded(child: _aiStat('Manual Review', _manualCount, AppColors.warning, Icons.warning_amber_outlined)),
              Container(width: 1, height: 70, color: AppColors.borderHairline),
              Expanded(child: _aiStat('Corrected', _correctedCount, AppColors.primary, Icons.edit_note)),
            ],
          ),
          const SizedBox(height: 16),
          if (total == 0)
            Text('No scan data yet for this term.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('AI Accuracy', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                Text('${(autoRate * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Expanded(flex: (_autoCount * 100 ~/ (total == 0 ? 1 : total)).clamp(1, 99),
                      child: Container(height: 12, color: AppColors.success)),
                  Expanded(
                      flex: (((manualRate) * 100).round()).clamp(1, 99),
                      child: Container(height: 12, color: AppColors.warning)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text('Total this term: $total scans', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _aiStat(String label, int count, Color color, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text('$count', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildProductivitySection() {
    if (_staffProductivity.isEmpty) {
      return _emptyCard('No staff scan data for this term.');
    }
    return Column(
      children: _staffProductivity.map((staff) {
        final total = staff['total'] as int;
        final today = staff['today'] as int;
        final lastUpload = _formatLastUpload(staff['lastUpload'] as String);
        final name = staff['name'] as String;
        final initials = name.trim().split(' ').take(2).map((w) => w.isNotEmpty ? w[0] : '').join().toUpperCase();

        return Card(
          color: AppColors.surface,
          elevation: 1,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                      child: Text(initials, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          Text('Last upload: $lastUpload',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('$total total', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                        Text('$today today', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDeptProgressCard() {
    if (_deptProgress.isEmpty) {
      return _emptyCard('No evaluation data for this term.');
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: _deptProgress.map((dept) {
          final progress = (dept['progress'] as double).clamp(0.0, 1.0);
          final total = dept['total'] as int;
          final isTop = progress == 1.0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                        child: Text(dept['name'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Text('$total responses',
                        style: TextStyle(fontWeight: FontWeight.bold, color: isTop ? AppColors.success : AppColors.primary)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.background,
                    color: isTop ? AppColors.success : AppColors.primary,
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _emptyCard(String msg) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
      child: Center(child: Text(msg, style: const TextStyle(color: AppColors.textSecondary))),
    );
  }
}