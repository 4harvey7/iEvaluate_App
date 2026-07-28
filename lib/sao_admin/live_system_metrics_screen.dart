// lib/sao_admin/live_system_metrics_screen.dart
// Real-time dashboard of how well (or badly) everything is running
// Shows AI accuracy, staff productivity, and dept evaluation progress
// If numbers look bad, dili ta ang blame — we just display the truth
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
  // supabase client — our direct line to the database gods
  final _supabase = Supabase.instance.client;
  // settings service — tells us which academic term we're currently working in
  final _settingsService = SystemSettingsService();

  bool _isLoading = true; // true while fetching all the metrics, pray it's fast
  String? _currentTermId; // the active term — all queries are filtered by this

  // AI Accuracy — counts how many records were auto-processed vs manually fixed
  int _autoCount = 0;     // AI got it right without help — the dream
  int _manualCount = 0;   // needed human review — AI struggled
  int _correctedCount = 0; // was wrong and then fixed — the most honest count

  // Productivity per staff — tracks how much each data gatherer uploaded
  List<Map<String, dynamic>> _staffProductivity = [];

  // Campus Evaluation Progress per department — who submitted how many responses
  List<Map<String, dynamic>> _deptProgress = [];

  @override
  void initState() {
    super.initState();
    // load everything when screen opens — no lazy initialization here
    _loadAllMetrics();
  }

  // master loader — gets the current term first, then fires all metric loaders in parallel
  // parallel loading because we're not animals — why wait one by one
  Future<void> _loadAllMetrics() async {
    setState(() => _isLoading = true);
    try {
      final settings = await _settingsService.getSettings(); // get current term config
      _currentTermId = settings.termId; // save the term ID for filtering

      // load all three metric groups at same time — concurrent is good
      await Future.wait([
        _loadAiAccuracy(),
        _loadStaffProductivity(),
        _loadDeptProgress(),
      ]);
    } catch (e) {
      // something crashed, log it and show whatever data we managed to load
      debugPrint('LiveMetrics error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false); // stop spinner no matter what
    }
  }

  // ── AI Processing Accuracy ─────────────────────────────────────
  // counts how many scan records fall into each validation bucket
  // auto = AI handled it, manual = needed review, corrected = was fixed after the fact
  Future<void> _loadAiAccuracy() async {
    try {
      var query = _supabase.from('raw_GoogleSheet_data_result').select('id, validation_status');
      if (_currentTermId != null) query = query.eq('term_id', _currentTermId!); // filter by current term
      final rows = await query;

      // tally up each status type — simple loop, nothing fancy
      int auto = 0, manual = 0, corrected = 0;
      for (final r in (rows as List)) {
        final status = r['validation_status'] ?? 'auto'; // default to 'auto' if null
        if (status == 'corrected') {
          corrected++;
        } else if (status == 'manual_review') {
          manual++;
        } else {
          auto++; // anything else counts as auto-processed
        }
      }
      // update state with the tallied counts — only if widget is still alive
      if (mounted) setState(() { _autoCount = auto; _manualCount = manual; _correctedCount = corrected; });
    } catch (e) {
      debugPrint('loadAiAccuracy error: $e'); // log and continue — dili ta mag-crash for one metric
    }
  }

  // ── Data Gatherer Productivity ─────────────────────────────────
  // groups scan records by staff member and counts how many they uploaded today vs total
  // also tracks when they last uploaded — useful for knowing who's actually working
  Future<void> _loadStaffProductivity() async {
    try {
      final today = DateTime.now();
      // start of today in UTC ISO string — used to filter "today's" records
      final startOfDay = DateTime(today.year, today.month, today.day).toUtc().toIso8601String();

      // raw_GoogleSheet_data_result has sao_staff_id referencing user_info
      // join user_info to get readable names instead of UUIDs — dili ta readable ang UUID
      var query = _supabase
          .from('raw_GoogleSheet_data_result')
          .select('sao_staff_id, created_at, user_info!sao_staff_id(first_name, last_name)');
      if (_currentTermId != null) query = query.eq('term_id', _currentTermId!); // term filter
      final rows = await query;

      // Group by sao_staff_id — build a map of staff stats keyed by their user ID
      final Map<String, Map<String, dynamic>> grouped = {};
      for (final r in (rows as List)) {
        final uid = r['sao_staff_id']?.toString() ?? 'unknown'; // fallback key if null
        if (!grouped.containsKey(uid)) {
          // first time seeing this staff — initialize their entry
          final ui = r['user_info'];
          grouped[uid] = {
            'name': ui != null ? '${ui['first_name']} ${ui['last_name']}' : 'Unknown Staff',
            'total': 0, // lifetime record count this term
            'today': 0, // count for today only
            'lastUpload': '', // ISO timestamp of their most recent upload
          };
        }
        grouped[uid]!['total'] = (grouped[uid]!['total'] as int) + 1; // increment total
        final createdAt = r['created_at'] as String? ?? '';
        if (createdAt.compareTo(startOfDay) >= 0) {
          // this record was created today — count it
          grouped[uid]!['today'] = (grouped[uid]!['today'] as int) + 1;
        }
        if (createdAt.compareTo(grouped[uid]!['lastUpload'] as String) > 0) {
          // this record is newer than the previous newest — update lastUpload
          grouped[uid]!['lastUpload'] = createdAt;
        }
      }

      // convert map values to list and update UI
      if (mounted) setState(() => _staffProductivity = grouped.values.toList());
    } catch (e) {
      debugPrint('loadStaffProductivity error: $e');
    }
  }

  // ── Campus Evaluation Progress per Department ──────────────────
  // tallies total survey responses grouped by department
  // requires a 3-level join because data is deeply normalized — wala choice
  Future<void> _loadDeptProgress() async {
    try {
      // overall_total_survey has no department_id — join via instructor_id -> department_table
      // yes this is a deep join, yes it hurts, but that's how the schema is
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

      // Group by dept name — tally total responses per department
      final Map<String, Map<String, dynamic>> grouped = {};
      for (final r in (rows as List)) {
        final ui = r['user_info'];
        if (ui == null) continue; // no instructor info — skip this one
        final deptTables = ui['department_table'];
        if (deptTables == null) continue; // no dept info — also skip
        final deptList = deptTables is List ? deptTables : [deptTables]; // normalize to list
        if (deptList.isEmpty || deptList[0] == null) continue; // empty — move on
        final deptNameObj = deptList[0]['department_name'];
        // handle both Map and List responses from the join — supabase is unpredictable
        final deptName = deptNameObj is Map
            ? (deptNameObj['d_name'] ?? 'Unknown')
            : (deptNameObj is List && deptNameObj.isNotEmpty ? deptNameObj[0]['d_name'] : 'Unknown');
        if (!grouped.containsKey(deptName)) {
          grouped[deptName] = {'name': deptName, 'total': 0}; // init new dept entry
        }
        // add this instructor's responses to dept total
        grouped[deptName]!['total'] =
            (grouped[deptName]!['total'] as int) + (r['total_responses'] as int? ?? 0);
      }

      final list = grouped.values.toList();
      // find the highest response count to use as denominator for progress bars
      final maxVal = list.isEmpty ? 1 : list.map((d) => d['total'] as int).reduce((a, b) => a > b ? a : b);
      for (final d in list) {
        // calculate relative progress — 1.0 means this dept has the most responses
        d['progress'] = maxVal == 0 ? 0.0 : (d['total'] as int) / maxVal;
      }
      list.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int)); // sort highest to lowest

      if (mounted) setState(() => _deptProgress = list);
    } catch (e) {
      debugPrint('loadDeptProgress error: $e');
      // primary query failed — fallback to just fetching department names with zero count
      await _loadDeptProgressFallback();
    }
  }

  // fallback when the big join query fails — just show dept names with zero responses
  // better than crashing, murag saying "at least we tried"
  Future<void> _loadDeptProgressFallback() async {
    try {
      final rows = await _supabase
          .from('department_name')
          .select('id, d_name');

      if (mounted) {
        setState(() {
          // create entries for each department with zeroed-out data
          _deptProgress = (rows as List).map((d) => {
            'name': d['d_name'] ?? 'Unknown',
            'total': 0,     // no data available
            'progress': 0.0, // zero progress bar
          }).toList();
        });
      }
    } catch (_) {} // if even the fallback fails, just silently do nothing — bahala na
  }

  // ── Helpers ───────────────────────────────────────────────────
  // converts an ISO timestamp to a human-readable "X ago" string
  // e.g. "5m ago", "2h ago", "3d ago" — much nicer than raw timestamps
  String _formatLastUpload(String iso) {
    if (iso.isEmpty) return 'No uploads yet'; // empty string means never uploaded
    try {
      final dt = DateTime.parse(iso).toLocal(); // parse and convert to local time
      final now = DateTime.now();
      final diff = now.difference(dt); // how long ago was this
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago'; // less than an hour
      if (diff.inHours < 24) return '${diff.inHours}h ago';     // less than a day
      return '${diff.inDays}d ago';                             // days ago
    } catch (_) {
      return 'Unknown'; // parse failed — weird timestamp, just say unknown
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
          // refresh button — for when you want fresh data RIGHT NOW
          IconButton(icon: const Icon(Icons.refresh, color: AppColors.primary), onPressed: _loadAllMetrics),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator()) // spinning — data is on its way
          : RefreshIndicator(
              onRefresh: _loadAllMetrics, // pull down to refresh — same as the button
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(), // allow scroll even with short content
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // subtitle explaining what this screen is about
                    Text(
                      'Real-time tracking for AI processing, staff productivity, and evaluation progress.',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 24),

                    // ── AI Processing Accuracy ─────────────────────
                    // shows how many records the AI got right vs wrong
                    _buildSectionTitle('AI Processing Accuracy'),
                    const SizedBox(height: 12),
                    _buildAiAccuracyCard(),
                    const SizedBox(height: 32),

                    // ── Staff Productivity ─────────────────────────
                    // shows how many records each data gatherer uploaded
                    _buildSectionTitle('Data Gatherer Productivity'),
                    const SizedBox(height: 12),
                    _buildProductivitySection(),
                    const SizedBox(height: 32),

                    // ── Campus Evaluation Progress ─────────────────
                    // shows which departments have the most survey responses
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

  // simple bold section title widget — reused three times in the build method
  Widget _buildSectionTitle(String title) =>
      Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold));

  // the AI accuracy card showing three stat columns and a progress bar
  // higher auto rate = AI is doing good, lower = AI needs help (and maybe therapy)
  Widget _buildAiAccuracyCard() {
    final total = _autoCount + _manualCount + _correctedCount; // total records processed
    final autoRate = total == 0 ? 0.0 : _autoCount / total; // percentage the AI got right
    final manualRate = total == 0 ? 0.0 : (_manualCount + _correctedCount) / total; // % that needed help

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
              // three stat columns separated by thin vertical dividers
              Expanded(child: _aiStat('Auto-Processed', _autoCount, AppColors.success, Icons.check_circle_outline)),
              Container(width: 1, height: 70, color: AppColors.borderHairline), // divider line
              Expanded(child: _aiStat('Manual Review', _manualCount, AppColors.warning, Icons.warning_amber_outlined)),
              Container(width: 1, height: 70, color: AppColors.borderHairline), // divider line
              Expanded(child: _aiStat('Corrected', _correctedCount, AppColors.primary, Icons.edit_note)),
            ],
          ),
          const SizedBox(height: 16),
          if (total == 0)
            // no data yet — politely inform instead of showing a 0% bar
            Text('No scan data yet for this term.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('AI Accuracy', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                // the actual percentage the AI got right — importente kaayo ni number
                Text('${(autoRate * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success)),
              ],
            ),
            const SizedBox(height: 8),
            // two-segment progress bar: green = auto-processed, yellow = manual/corrected
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Expanded(flex: (_autoCount * 100 ~/ (total == 0 ? 1 : total)).clamp(1, 99),
                      child: Container(height: 12, color: AppColors.success)), // green segment
                  Expanded(
                      flex: (((manualRate) * 100).round()).clamp(1, 99),
                      child: Container(height: 12, color: AppColors.warning)), // yellow segment
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

  // single stat column widget used in the AI accuracy card
  // shows an icon, a big number, and a small label — compact but readable
  Widget _aiStat(String label, int count, Color color, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 20), // colored icon for visual context
        const SizedBox(height: 6),
        Text('$count', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary)), // big number
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center), // label below
      ],
    );
  }

  // builds a list of staff productivity cards — one per data gatherer
  // shows name, total records, today's records, and last upload time
  Widget _buildProductivitySection() {
    if (_staffProductivity.isEmpty) {
      return _emptyCard('No staff scan data for this term.'); // nothing to show
    }
    return Column(
      children: _staffProductivity.map((staff) {
        final total = staff['total'] as int;
        final today = staff['today'] as int;
        final lastUpload = _formatLastUpload(staff['lastUpload'] as String); // human-readable time
        final name = staff['name'] as String;
        // generate initials from name — take first letter of each word, max 2 letters
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
                    // circle avatar with initials — no photos, we are professional
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
                          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                          // shows "X ago" for last upload — useful to see if someone is slacking
                          Text('Last upload: $lastUpload',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11), overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    // right side shows total and today's count
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

  // builds the department evaluation progress card with horizontal progress bars
  // the dept with the most responses gets progress=1.0, others are relative to that
  Widget _buildDeptProgressCard() {
    if (_deptProgress.isEmpty) {
      return _emptyCard('No evaluation data for this term.'); // nothing yet
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
          final progress = (dept['progress'] as double).clamp(0.0, 1.0); // clamp to valid range
          final total = dept['total'] as int;
          final isTop = progress == 1.0; // this dept has the most responses — crown them

          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // department name on the left — truncated if too long
                    Expanded(
                        child: Text(dept['name'], style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    // response count on the right — green if top dept, blue otherwise
                    Text('$total responses',
                        style: TextStyle(fontWeight: FontWeight.bold, color: isTop ? AppColors.success : AppColors.primary)),
                  ],
                ),
                const SizedBox(height: 8),
                // the actual progress bar — full width for top dept, proportional for others
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress, // 0.0 to 1.0
                    backgroundColor: AppColors.background,
                    color: isTop ? AppColors.success : AppColors.primary, // green for top, blue for rest
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

  // generic empty card widget — shows a centered message when there's no data
  // used in multiple places so we dont repeat the same Container+Text combo
  Widget _emptyCard(String msg) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
      child: Center(child: Text(msg, style: const TextStyle(color: AppColors.textSecondary))),
    );
  }
}