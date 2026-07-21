// lib/instructor/instructor_dashboard.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../login_screen.dart';
import '../theme/app_colors.dart';
import '../core/services/auth_service.dart';
import '../core/services/system_settings_service.dart';
import 'instructor_settings_screen.dart';
import 'models/subject.dart';
import 'my_subjects_screen.dart';
import 'past_semesters_screen.dart';
import 'providers/subjects_provider.dart';
import 'student_feedback_screen.dart';
import 'detailed_report_screen.dart';
import 'subject_detail_screen.dart';

class InstructorDashboardScreen extends StatefulWidget {
  final String userId;
  const InstructorDashboardScreen({super.key, required this.userId});

  @override
  State<InstructorDashboardScreen> createState() => _InstructorDashboardScreenState();
}

class _InstructorDashboardScreenState extends State<InstructorDashboardScreen> {
  final _authService = AuthService();
  final _settingsService = SystemSettingsService();
  final _supabase = Supabase.instance.client;
  
  String _currentTermId = '';
  String _currentSemester = '...';
  String _currentYear = '...';
  String _instructorName = '...';
  String _instructorTitle = '...';
  String _instructorDept = '...';
  bool _isSyncing = false;
  List<String> _recentFeedback = [];

  StreamSubscription<SystemSettings>? _settingsSubscription;

  // Live intervention reports from dept head (read-only for instructor)
  List<Map<String, dynamic>> _interventionReports = [];
  bool _interventionChannelActive = false;
  RealtimeChannel? _interventionChannel;

  @override
  void initState() {
    super.initState();
    _subscribeToSettings();
    _subscribeToInterventions();
    // Trigger a full sync automatically on login/init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshDashboardData(isInitial: true);
    });
    debugPrint('[INSTRUCTOR] 📥 Received User ID: ${widget.userId}');
  }

  void _subscribeToSettings() {
    _settingsSubscription = _settingsService.streamSettings().listen((settings) {
      if (mounted) {
        final newTermId = settings.termId ?? '';
        final shouldReload = _currentTermId != newTermId;
        
        setState(() {
          _currentTermId = newTermId;
          _currentSemester = settings.semester;
          _currentYear = settings.academicYear;
        });

        if (shouldReload) {
          _refreshDashboardData(isInitial: true);
        }
      }
    });
  }

  Future<void> _refreshDashboardData({bool isInitial = false}) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    
    try {
      // Ensure we have a Term ID before fetching analytics/subjects
      if (_currentTermId.isEmpty) {
        final settings = await _settingsService.getSettings();
        if (mounted) {
          setState(() {
            _currentTermId = settings.termId ?? '';
            _currentSemester = settings.semester;
            _currentYear = settings.academicYear;
          });
        }
      }

      await Future.wait([
        _fetchInstructorProfile(),
        context.read<SubjectsProvider>().load(termId: _currentTermId),
        if (!isInitial) Future.delayed(const Duration(milliseconds: 500)),
      ]);
      
      if (mounted && !isInitial) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dashboard and local results synced successfully'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('Sync failed: $e');
      if (mounted && !isInitial) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _fetchInstructorProfile() async {
    try {
      // 1. Fetch Identity Info (Always load this regardless of term)
      final user = await _supabase.from('user_info').select('first_name, last_name').eq('id', widget.userId).maybeSingle();
      
      final deptData = await _supabase
          .from('department_table')
          .select('department_name:Department_name_ID(d_name), roles:roles(Roles)')
          .eq('user_id', widget.userId)
          .maybeSingle();

      // 2. Ensure we have a Term ID to fetch analytics
      if (_currentTermId.isEmpty) {
        final settings = await _settingsService.getSettings();
        _currentTermId = settings.termId ?? '';
      }

      // Prepare analytics variables (resetting to 0 to prevent ghosting)
      double overallScore = 0.0;
      double managementScore = 0.0;
      double performanceScore = 0.0;
      int totalEvaluations = 0;
      List<String> feedback = [];

      // 3. Fetch Analytics for SPECIFIC TERM (Only if term ID exists)
      if (_currentTermId.isNotEmpty) {
        // NEW LOGIC: Find all subjects assigned to this instructor for this term first
        final subjectsResponse = await _supabase
            .from('subjects')
            .select('id')
            .eq('instructor_id', widget.userId)
            .eq('term_id', _currentTermId);
        
        final subjectIds = (subjectsResponse as List).map((s) => s['id'].toString()).toList();
        debugPrint('[InstructorDashboard] Found Subject IDs for term $_currentTermId: $subjectIds');

        final analytics = await _supabase
            .from('overall_total_survey')
            .select()
            .eq('instructor_id', widget.userId)
            .eq('term_id', _currentTermId)
            .maybeSingle();

        if (analytics != null) {
          debugPrint('[InstructorDashboard] Found data in overall_total_survey');
          overallScore = (analytics['overall_mean'] as num?)?.toDouble() ?? 0.0;
          managementScore = (analytics['management_mean'] as num?)?.toDouble() ?? 0.0;
          performanceScore = (analytics['performance_mean'] as num?)?.toDouble() ?? 0.0;
          totalEvaluations = analytics['total_responses'] ?? 0;
        } else {
          // FALLBACK 1: Aggregate from individual subject results (Matches SubjectDetailScreen logic)
          debugPrint('[InstructorDashboard] overall_total_survey empty or null. Checking subject results fallback...');
          
          var mgmtQuery = _supabase.from('management_results').select('overall_management_mean, total_responses').eq('term_id', _currentTermId);
          var perfQuery = _supabase.from('performance_results').select('overall_performance_mean, total_responses').eq('term_id', _currentTermId);

          if (subjectIds.isNotEmpty) {
            mgmtQuery = mgmtQuery.filter('subject_id', 'in', subjectIds);
            perfQuery = perfQuery.filter('subject_id', 'in', subjectIds);
          } else {
            mgmtQuery = mgmtQuery.eq('instructor_id', widget.userId);
            perfQuery = perfQuery.eq('instructor_id', widget.userId);
          }

          final results = await Future.wait([mgmtQuery, perfQuery]);
          final mList = results[0] as List;
          final pList = results[1] as List;

          if (mList.isNotEmpty || pList.isNotEmpty) {
            double mSum = 0, pSum = 0;
            int mCount = 0, pCount = 0;
            int mTotal = 0, pTotal = 0;

            for (var row in mList) {
              mSum += (row['overall_management_mean'] as num?)?.toDouble() ?? 0.0;
              mTotal += (row['total_responses'] as int?) ?? 0;
              mCount++;
            }
            for (var row in pList) {
              pSum += (row['overall_performance_mean'] as num?)?.toDouble() ?? 0.0;
              pTotal += (row['total_responses'] as int?) ?? 0;
              pCount++;
            }

            managementScore = mCount > 0 ? mSum / mCount : 0.0;
            performanceScore = pCount > 0 ? pSum / pCount : 0.0;
            overallScore = (managementScore + performanceScore) / 2;
            // Use the higher response count as the base
            totalEvaluations = mTotal > pTotal ? mTotal : pTotal;
            
            debugPrint('[InstructorDashboard] Aggregated: mgmt=$managementScore, perf=$performanceScore, evals=$totalEvaluations');
          } 
          
          // FALLBACK 2: Raw data
          if (totalEvaluations == 0) {
            debugPrint('[InstructorDashboard] Subject results empty. Checking raw data...');
            var rawQuery = _supabase.from('raw_GoogleSheet_data_result').select().eq('term_id', _currentTermId);
            
            if (subjectIds.isNotEmpty) {
              rawQuery = rawQuery.filter('subject_id', 'in', subjectIds);
            } else {
              rawQuery = rawQuery.eq('instructor_ID', widget.userId);
            }

            final rawData = await rawQuery;
            if (rawData.isNotEmpty) {
              int count = rawData.length;
              double mSum = 0, pSum = 0;
              for (var row in rawData) {
                for (int i = 1; i <= 10; i++) {
                  mSum += (row['m$i'] as num?)?.toDouble() ?? 0.0;
                  pSum += (row['p$i'] as num?)?.toDouble() ?? 0.0;
                }
              }
              managementScore = mSum / (count * 10);
              performanceScore = pSum / (count * 10);
              overallScore = (managementScore + performanceScore) / 2;
              totalEvaluations = count;
            }
          }
        }

        // 4. Fetch Recent Feedback (Use subject IDs for better coverage)
        var feedbackQuery = _supabase.from('student_remarks').select('remark').eq('term_id', _currentTermId);
        
        if (subjectIds.isNotEmpty) {
          feedbackQuery = feedbackQuery.filter('subject_id', 'in', subjectIds);
        } else {
          feedbackQuery = feedbackQuery.eq('instructor_id', widget.userId);
        }

        final feedbackData = await feedbackQuery.order('created_at', ascending: false).limit(5);
        
        feedback = (feedbackData as List).map((f) => f['remark'] as String).toList();
      }

      // 5. Fetch Historical Performance (All terms)
      final historyData = await _supabase
          .from('overall_total_survey')
          .select('overall_mean, academic_terms(semester, academic_year)')
          .eq('instructor_id', widget.userId)
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          if (user != null) {
            _instructorName = '${user['first_name']} ${user['last_name']}';
          }
          
          if (deptData != null) {
            final dept = deptData['department_name'];
            _instructorDept = dept is Map ? dept['d_name'] ?? 'General' : 'General';
            
            final role = deptData['roles'];
            _instructorTitle = role is Map ? role['Roles'] ?? 'Instructor' : 'Instructor';
          }

          // Apply term-specific scores
          _myPerformance['overallScore'] = overallScore;
          _myPerformance['managementScore'] = managementScore;
          _myPerformance['performanceScore'] = performanceScore;
          _myPerformance['totalEvaluations'] = totalEvaluations;

          debugPrint('[InstructorDashboard] Applied Stats: '
                'overall=$overallScore, '
                'mgmt=$managementScore, '
                'perf=$performanceScore, '
                'evals=$totalEvaluations');

          _recentFeedback = feedback;

          if ((historyData as List).isNotEmpty) {
            _myHistory.clear();
            final recentHistory = (historyData as List).reversed.take(4).toList().reversed;
            for (var item in recentHistory) {
              final term = item['academic_terms'];
              String label = 'Sem';
              if (term != null) {
                String year = term['academic_year'].toString();
                if (year.length >= 4) year = year.substring(2);
                label = '${term['semester'].toString().substring(0, 3)} $year';
              }
              _myHistory.add({
                'sem': label,
                'score': (item['overall_mean'] as num?)?.toDouble() ?? 0.0,
              });
            }
          }

        });
      }
    } catch (e) {
      debugPrint('Error fetching instructor profile: $e');
      if (mounted) setState(() {});
    }
  }

  Future<void> _handleManualSync() async {
    await _refreshDashboardData(isInitial: false);
  }

  @override
  void dispose() {
    _settingsSubscription?.cancel();
    _interventionChannel?.unsubscribe();
    super.dispose();
  }

  /// Subscribes to real-time changes on intervention_reports for this instructor.
  void _subscribeToInterventions() {
    if (_interventionChannelActive) return;
    _interventionChannelActive = true;

    _interventionChannel = _supabase
        .channel('instructor_interventions_${widget.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'intervention_reports',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'instructor_id',
            value: widget.userId,
          ),
          callback: (payload) {
            if (mounted) _fetchInterventionReports();
          },
        )
        .subscribe();

    _fetchInterventionReports();
  }

  Future<void> _fetchInterventionReports() async {
    try {
      final data = await _supabase
          .from('intervention_reports')
          .select('id, action_type, notes, status, created_at, dean_id, user_info!dean_id(first_name, last_name)')
          .eq('instructor_id', widget.userId)
          .neq('status', 'Resolved')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _interventionReports = (data as List).cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      debugPrint('Error fetching intervention reports: $e');
    }
  }
  
  final Map<String, dynamic> _myPerformance = {
    'overallScore': 0.0,
    'managementScore': 0.0,
    'performanceScore': 0.0,
    'totalEvaluations': 0,
    'trend': 'neutral',
  };

  final List<Map<String, dynamic>> _myHistory = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.surface),
        title: const Text('My Dashboard', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Manual Sync',
            icon: _isSyncing 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface))
              : const Icon(Icons.sync_rounded, color: AppColors.surface),
            onPressed: _isSyncing ? null : _handleManualSync,
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications, color: AppColors.surface),
                onPressed: _interventionReports.isEmpty ? null : () {
                  // Scroll to top where banners are shown
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('You have ${_interventionReports.length} active notice(s) from your department head.'),
                      backgroundColor: AppColors.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              if (_interventionReports.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '${_interventionReports.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),

      drawer: Drawer(
        backgroundColor: AppColors.surface,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: AppColors.textPrimary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.3),
                    child: Text(_instructorName.isNotEmpty ? _instructorName[0] : '?', style: const TextStyle(color: AppColors.surface, fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  Text(_instructorName, style: const TextStyle(color: AppColors.surface, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('$_instructorTitle • $_instructorDept', style: const TextStyle(color: AppColors.textInvertedDim, fontSize: 12)),
                ],
              ),
            ),
            _buildDrawerItem(context, Icons.dashboard, 'Dashboard', true, onTap: () {
              Navigator.pop(context);
            }),
            _buildDrawerItem(context, Icons.history, 'Past Semesters', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => PastSemestersScreen(userId: widget.userId)));
            }),
            _buildDrawerItem(context, Icons.menu_book_rounded, 'My Subjects', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => MySubjectsScreen(userId: widget.userId)));
            }),
            _buildDrawerItem(context, Icons.forum, 'Student Feedback', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => StudentFeedbackScreen(userId: widget.userId, termId: _currentTermId)));
            }),
            _buildDrawerItem(context, Icons.settings, 'Account Settings', false, onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const InstructorSettingsScreen()));
            }),
            const Divider(),
            _buildDrawerItem(context, Icons.logout, 'Log Out', false, isLogout: true, onTap: () async {
              final navigator = Navigator.of(context);
              await _authService.signOut();
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            }),
          ],
        ),
      ),

      body: RefreshIndicator(
        onRefresh: _handleManualSync,
        color: AppColors.primary,
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- INTERVENTION NOTICES (read-only, from dept head) ---
              if (_interventionReports.isNotEmpty) ...[
                ..._interventionReports.map((report) {
                  final deanInfo = report['user_info'];
                  final deanName = deanInfo is Map
                      ? '${deanInfo['first_name'] ?? ''} ${deanInfo['last_name'] ?? ''}'.trim()
                      : 'Your Department Head';
                  final date = report['created_at'] != null
                      ? DateTime.tryParse(report['created_at'])?.toLocal()
                      : null;
                  final dateStr = date != null
                      ? '${date.month}/${date.day}/${date.year}'
                      : 'Recently';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.5), width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 22),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Official Notice — Action Required',
                                style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ),
                            // Read-only lock icon — instructor cannot dismiss
                            Tooltip(
                              message: 'Only your department head can remove this notice',
                              child: Icon(Icons.lock_outline, color: AppColors.error.withValues(alpha: 0.6), size: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildNoticeRow('From', deanName),
                        const SizedBox(height: 4),
                        _buildNoticeRow('Action', report['action_type'] ?? 'N/A'),
                        if ((report['notes'] as String?)?.isNotEmpty == true) ...[
                          const SizedBox(height: 4),
                          _buildNoticeRow('Notes', report['notes']),
                        ],
                        const SizedBox(height: 8),
                        Text(dateStr, style: const TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 12),
              ],

              // --- WELCOME CARD ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: AppColors.heroGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 8))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Welcome back, ${_instructorName.split(' ')[0]}!', style: const TextStyle(color: AppColors.textInvertedDim, fontSize: 16)),
                    const SizedBox(height: 8),
                    const Text('Your Performance Overview', style: TextStyle(color: AppColors.surface, fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Active Term: $_currentSemester, $_currentYear', style: const TextStyle(color: AppColors.textInvertedDim, fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 20),

                    // ── Overall Mean Hero Score ──────────────────────────
                    Builder(builder: (context) {
                      final overall = (_myPerformance['overallScore'] as num?)?.toDouble() ?? 0.0;
                      final hasData = overall > 0;
                      final vd = Subject.getVerbalDescription(overall);
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hasData ? overall.toStringAsFixed(2) : 'N/A',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 52,
                                    fontWeight: FontWeight.bold,
                                    height: 1.0,
                                    letterSpacing: -1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Overall Weighted Mean',
                                  style: TextStyle(color: AppColors.textInvertedDim, fontSize: 11, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                          if (hasData)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                vd,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                        ],
                      );
                    }),

                    const SizedBox(height: 16),
                    Divider(color: Colors.white.withValues(alpha: 0.15), thickness: 1, height: 1),
                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildStat('Management', _myPerformance['managementScore'].toStringAsFixed(1)),
                        Container(width: 1, height: 40, color: AppColors.textInvertedFaint),
                        _buildStat('Performance', _myPerformance['performanceScore'].toStringAsFixed(1)),
                        Container(width: 1, height: 40, color: AppColors.textInvertedFaint),
                        _buildStat('Evaluations', _myPerformance['totalEvaluations'].toString()),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DetailedReportScreen(
                              userId: widget.userId,
                              instructorName: _instructorName,
                              department: _instructorDept,
                              termId: _currentTermId,
                              term: _currentSemester,
                              academicYear: _currentYear,
                              managementScore: (_myPerformance['managementScore'] as num).toDouble(),
                              performanceScore: (_myPerformance['performanceScore'] as num).toDouble(),
                              overallScore: (_myPerformance['overallScore'] as num).toDouble(),
                              totalEvaluations: _myPerformance['totalEvaluations'],
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.description_outlined, size: 18),
                        label: const Text('View Official SAST Report'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.15),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // --- SUBJECT BREAKDOWN ---
              const Text('Current Classes', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Consumer<SubjectsProvider>(
                builder: (context, provider, _) {
                  final subjects = provider.subjects;
                  if (subjects.isEmpty) {
                    return _buildEmptySubjectsCard(context);
                  }
                  return Column(
                    children: subjects.map((subject) => _buildSubjectCard(subject)).toList(),
                  );
                },
              ),
              const SizedBox(height: 32),

              // --- TWO-COLUMN LAYOUT: HISTORY & FEEDBACK ---
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Growth', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Container(
                          height: 180,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: _myHistory.map<Widget>((data) {
                              double barHeight = (data['score'] / 5.0) * 100;
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text('${data['score']}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Container(
                                    width: 24,
                                    height: barHeight,
                                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(4)),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(data['sem'].split(' ')[0], style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Recent Feedback', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Container(
                          height: 180,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                          child: _recentFeedback.isEmpty 
                            ? const Center(child: Text('No feedback yet', style: TextStyle(color: AppColors.textTertiary, fontSize: 12)))
                            : ListView.separated(
                            itemCount: _recentFeedback.length,
                            separatorBuilder: (context, index) => const Divider(height: 16),
                            itemBuilder: (context, index) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.format_quote, color: AppColors.primary, size: 16),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _recentFeedback[index],
                                      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontStyle: FontStyle.italic),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildNoticeRow(String label, String? value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text('$label:', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Text(value ?? 'N/A', style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, height: 1.4)),
        ),
      ],
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textInvertedDim, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildEmptySubjectsCard(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MySubjectsScreen(userId: widget.userId)),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderHairline, width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.menu_book_rounded, color: AppColors.primary),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No subjects assigned',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Your assigned subjects will appear here.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectCard(Subject subject) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SubjectDetailScreen(
            subject: subject, 
            userId: widget.userId,
            termId: _currentTermId,
          ),
        ),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Card(
        color: AppColors.surface,
        elevation: 1,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.class_, color: AppColors.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          subject.code,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                            fontSize: 12,
                          ),
                        ),
                        if (subject.section != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              subject.section!,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      subject.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        fontSize: 15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerItem(BuildContext context, IconData icon, String title, bool isSelected, {bool isLogout = false, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: isLogout ? AppColors.error : (isSelected ? AppColors.primary : AppColors.textPrimary)),
      title: Text(
        title,
        style: TextStyle(
          color: isLogout ? AppColors.error : (isSelected ? AppColors.primary : AppColors.textPrimary),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onTap: onTap ?? () {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$title coming soon!")));
      },
    );
  }
}
