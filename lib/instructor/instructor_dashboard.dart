// lib/instructor/instructor_dashboard.dart
// The BIG screen. This is the main thing every instructor see after login.
// If this break, everybody panic. So pray lang that the Supabase is up.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';
import '../core/services/system_settings_service.dart';
import '../core/navigation/main_scaffold.dart';
import 'models/subject.dart';
import 'my_subjects_screen.dart';
import 'providers/subjects_provider.dart';
import 'detailed_report_screen.dart';
import 'subject_detail_screen.dart';
import '../widgets/motion.dart';
import '../widgets/pressable.dart';

// The main dashboard widget. StatefulWidget because life is stateful, dili siya const.
class InstructorDashboardScreen extends StatefulWidget {
  final String userId;
  const InstructorDashboardScreen({super.key, required this.userId});

  @override
  State<InstructorDashboardScreen> createState() =>
      _InstructorDashboardScreenState();
}

class _InstructorDashboardScreenState extends State<InstructorDashboardScreen> {
  // Services — the helpers that do the heavy lifting so we dont have to
  final _settingsService = SystemSettingsService();
  final _supabase = Supabase.instance.client;

  // Term and instructor info — all start as "..." because we dont know yet
  String _currentTermId = '';
  String _currentSemester = '...';
  String _currentYear = '...';
  String _instructorName = '...';
  String _instructorDept = '...';

  // System Services
  bool _isSyncing = false;
  bool _isInitialLoading = true;
  // Recent feedback from students — could be nice, could be brutal, bahala na
  List<String> _recentFeedback = [];

  // Subscription to settings stream — listens for changes from the admin side
  StreamSubscription<SystemSettings>? _settingsSubscription;

  // Live intervention reports from dept head (read-only for instructor, ayaw remove)
  List<Map<String, dynamic>> _interventionReports = [];
  bool _interventionChannelActive = false; // make sure we dont subscribe twice
  RealtimeChannel? _interventionChannel;

  Future<void> _loadCachedProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('instructor_profile_${widget.userId}');
      if (cached != null) {
        final data = jsonDecode(cached);
        if (mounted) {
          setState(() {
            _currentTermId = data['termId'] ?? _currentTermId;
            _currentSemester = data['semester'] ?? _currentSemester;
            _currentYear = data['academicYear'] ?? _currentYear;
            _instructorName = data['name'] ?? _instructorName;
            _instructorDept = data['dept'] ?? _instructorDept;
            _myPerformance['overallScore'] = data['overallScore'] ?? 0.0;
            _myPerformance['managementScore'] = data['managementScore'] ?? 0.0;
            _myPerformance['performanceScore'] =
                data['performanceScore'] ?? 0.0;
            _myPerformance['totalEvaluations'] = data['totalEvaluations'] ?? 0;
            _recentFeedback = List<String>.from(data['feedback'] ?? []);
            if (data['history'] != null) {
              _myHistory.clear();
              _myHistory.addAll(
                List<Map<String, dynamic>>.from(
                  data['history'].map((x) => Map<String, dynamic>.from(x)),
                ),
              );
            }
          });
          debugPrint('[INSTRUCTOR] ⚡ Loaded cached profile data instantly.');
        }
      }
    } catch (e) {
      debugPrint('[INSTRUCTOR] Failed to load cache: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCachedProfile(); // Load stale data instantly!
    _subscribeToSettings(); // start listening to system settings changes
    _subscribeToInterventions(); // also listen if the dept head is mad at you
    // Wait for first frame, then sync everything so the UI is ready first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshDashboardData(isInitial: true);
    });
    debugPrint('[INSTRUCTOR] 📥 Received User ID: ${widget.userId}');
  }

  // Listen to system settings in real time — so if the admin change the semester,
  // this screen also update without needing to manually refresh. importente kaayo.
  void _subscribeToSettings() {
    _settingsSubscription = _settingsService.streamSettings().listen((
      settings,
    ) {
      if (mounted) {
        final newTermId = settings.termId ?? '';
        // Only reload data if the term actually changed — no need drama if same term
        final shouldReload = _currentTermId != newTermId;

        setState(() {
          _currentTermId = newTermId;
          _currentSemester = settings.semester;
          _currentYear = settings.academicYear;
        });

        if (shouldReload) {
          // Term changed! Reload everything. Wala choice.
          _refreshDashboardData(isInitial: true);
        }
      }
    });
  }

  // Big refresh function — calls everything at once and shows snackbar when done.
  // isInitial = true means quiet mode (no snackbar on load, dili spam).
  Future<void> _refreshDashboardData({bool isInitial = false}) async {
    if (_isSyncing) return; // already syncing, ayaw double trigger
    final messenger = ScaffoldMessenger.of(context);
    final subjectsProvider = context
        .read<SubjectsProvider>(); // capture before any await
    setState(() => _isSyncing = true);

    try {
      // Make sure we have a Term ID before we try to fetch anything useful
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

      // Run profile fetch and subject load at the same time — faster, murag paralel universe
      await Future.wait([
        _fetchInstructorProfile(),
        subjectsProvider.load(
          termId: _currentTermId,
        ), // use captured reference, not context.read
        if (!isInitial)
          Future.delayed(
            const Duration(milliseconds: 500),
          ), // small wait for non-initial
      ]);

      // Show success snackbar only on manual sync, not on initial load
      if (mounted && !isInitial) {
        messenger.showSnackBar(
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
        // Tell the user something went wrong. At least be honest.
        messenger.showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      // Always turn off the loading spinner, even if things go bad
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _isInitialLoading = false;
        });
      }
    }
  }

  // Fetch the instructor's profile data AND analytics for the current term.
  // This does a LOT of things. Take a deep breath before reading.
  Future<void> _fetchInstructorProfile() async {
    try {
      // 1. Fetch Identity Info (Always load this regardless of term)
      // Get name from user_info — the basic "who are you" query
      final user = await _supabase
          .from('user_info')
          .select('first_name, last_name')
          .eq('id', widget.userId)
          .maybeSingle();

      // Get department and role — title like "Instructor" or "Professor" and which dept
      final deptData = await _supabase
          .from('department_table')
          .select(
            'department_name:Department_name_ID(d_name), roles:roles(Roles)',
          )
          .eq('user_id', widget.userId)
          .maybeSingle();

      // 2. Ensure we have a Term ID to fetch analytics — wala term ID, wala data
      if (_currentTermId.isEmpty) {
        final settings = await _settingsService.getSettings();
        _currentTermId = settings.termId ?? '';
      }

      // Reset all analytics to 0 first, to prevent old data from ghosting into new term
      double overallScore = 0.0;
      double managementScore = 0.0;
      double performanceScore = 0.0;
      int totalEvaluations = 0;
      List<String> feedback = [];

      // 3. Fetch Analytics for SPECIFIC TERM (Only if term ID exists)
      if (_currentTermId.isNotEmpty) {
        // Find all subjects assigned to this instructor for this term via junction table
        final subjectsResponse = await _supabase
            .from('instructor_subjects')
            .select('subject_id')
            .eq('instructor_id', widget.userId)
            .eq('term_id', _currentTermId);

        // Convert the list of rows into a simple list of subject ID strings
        final subjectIds = (subjectsResponse as List)
            .map((s) => s['subject_id'].toString())
            .toList();
        debugPrint(
          '[InstructorDashboard] Found Subject IDs for term $_currentTermId: $subjectIds',
        );

        // Try the pre-computed summary table first — fastest path, best case scenario
        final analytics = await _supabase
            .from('overall_total_survey')
            .select()
            .eq('instructor_id', widget.userId)
            .eq('term_id', _currentTermId)
            .maybeSingle();

        if (analytics != null) {
          debugPrint(
            '[InstructorDashboard] Found data in overall_total_survey',
          );
          overallScore =
              (analytics['combined_score_mean'] as num?)?.toDouble() ??
              (analytics['overall_mean'] as num?)?.toDouble() ??
              0.0;
          managementScore =
              (analytics['management_mean'] as num?)?.toDouble() ?? 0.0;
          performanceScore =
              (analytics['performance_mean'] as num?)?.toDouble() ?? 0.0;
          totalEvaluations = analytics['total_responses'] ?? 0;
        } else {
          // FALLBACK 1: Aggregate from individual subject results (Matches SubjectDetailScreen logic)
          // The pre-computed table is empty, so we compute it manually. A bit extra, but wala choice.
          debugPrint(
            '[InstructorDashboard] overall_total_survey empty or null. Checking subject results fallback...',
          );

          var mgmtQuery = _supabase
              .from('management_results')
              .select('overall_management_mean, total_responses')
              .eq('term_id', _currentTermId);
          var perfQuery = _supabase
              .from('performance_results')
              .select('overall_performance_mean, total_responses')
              .eq('term_id', _currentTermId);

          // Filter by subject IDs if we have them, else fall back to instructor ID filter
          if (subjectIds.isNotEmpty) {
            mgmtQuery = mgmtQuery.filter('subject_id', 'in', subjectIds);
            perfQuery = perfQuery.filter('subject_id', 'in', subjectIds);
          } else {
            mgmtQuery = mgmtQuery.eq('instructor_id', widget.userId);
            perfQuery = perfQuery.eq('instructor_id', widget.userId);
          }

          // Run both queries at the same time para mas bilis
          final results = await Future.wait([mgmtQuery, perfQuery]);
          final mList = results[0] as List;
          final pList = results[1] as List;

          if (mList.isNotEmpty || pList.isNotEmpty) {
            double mSum = 0, pSum = 0;
            int mCount = 0, pCount = 0;
            int mTotal = 0, pTotal = 0;

            // Sum up all management subject scores
            for (var row in mList) {
              mSum +=
                  (row['overall_management_mean'] as num?)?.toDouble() ?? 0.0;
              mTotal += (row['total_responses'] as int?) ?? 0;
              mCount++;
            }
            // Sum up all performance subject scores
            for (var row in pList) {
              pSum +=
                  (row['overall_performance_mean'] as num?)?.toDouble() ?? 0.0;
              pTotal += (row['total_responses'] as int?) ?? 0;
              pCount++;
            }

            // Calculate weighted averages — simple average across subjects
            managementScore = mCount > 0 ? mSum / mCount : 0.0;
            performanceScore = pCount > 0 ? pSum / pCount : 0.0;
            overallScore = (managementScore + performanceScore) / 2;
            // Use the higher response count as the base — more generous, murag
            totalEvaluations = mTotal > pTotal ? mTotal : pTotal;

            debugPrint(
              '[InstructorDashboard] Aggregated: mgmt=$managementScore, perf=$performanceScore, evals=$totalEvaluations',
            );
          }

          // FALLBACK 2: Raw data — if even subject results are empty, dig into the raw spreadsheet data
          if (totalEvaluations == 0) {
            debugPrint(
              '[InstructorDashboard] Subject results empty. Checking raw data...',
            );
            var rawQuery = _supabase
                .from('sast_all_raw_data_survey')
                .select()
                .eq('term_id', _currentTermId);

            if (subjectIds.isNotEmpty) {
              rawQuery = rawQuery.filter('subject_id', 'in', subjectIds);
            } else {
              rawQuery = rawQuery.eq('instructor_ID', widget.userId);
            }

            final rawData = await rawQuery;
            if (rawData.isNotEmpty) {
              int count = rawData.length;
              double mSum = 0, pSum = 0;
              // Loop through each row and sum up m1-m10 and p1-p10 columns
              for (var row in rawData) {
                for (int i = 1; i <= 10; i++) {
                  mSum += (row['m$i'] as num?)?.toDouble() ?? 0.0;
                  pSum += (row['p$i'] as num?)?.toDouble() ?? 0.0;
                }
              }
              // Divide by (count * 10) because 10 questions each — do the math
              managementScore = mSum / (count * 10);
              performanceScore = pSum / (count * 10);
              overallScore = (managementScore + performanceScore) / 2;
              totalEvaluations = count;
            }
          }
        }

        // 4. Fetch Recent Feedback — the actual words students wrote about you
        // We now filter directly by instructor_id and term_id to ensure we get remarks
        // even if the n8n AI pipeline missed mapping the subject_id.
        var feedbackQuery = _supabase
            .from('student_remarks')
            .select('remark')
            .eq('term_id', _currentTermId)
            .eq('instructor_id', widget.userId);

        // Only get 5 most recent — we dont need all of them, just the freshest ones
        final feedbackData = await feedbackQuery
            .order('created_at', ascending: false)
            .limit(5);

        feedback = (feedbackData as List)
            .map((f) => f['remark'] as String)
            .toList();
      }

      // 5. Fetch Historical Performance (All terms) — the "glow up" chart data
      final historyData = await _supabase
          .from('overall_total_survey')
          .select(
            'overall_mean, combined_score_mean, academic_terms(semester, academic_year)',
          )
          .eq('instructor_id', widget.userId)
          .order(
            'created_at',
            ascending: true,
          ); // oldest first, so chart goes left to right

      // Apply all fetched data to state if widget is still alive
      if (mounted) {
        setState(() {
          // Set the instructor's display name
          if (user != null) {
            _instructorName = '${user['first_name']} ${user['last_name']}';
          }

          // Set department name
          if (deptData != null) {
            final dept = deptData['department_name'];
            _instructorDept = dept is Map
                ? dept['d_name'] ?? 'General'
                : 'General';
            // _instructorTitle removed — was only used in the drawer header (now MainScaffold)
          }

          // Apply term-specific scores to the performance map
          _myPerformance['overallScore'] = overallScore;
          _myPerformance['managementScore'] = managementScore;
          _myPerformance['performanceScore'] = performanceScore;
          _myPerformance['totalEvaluations'] = totalEvaluations;

          debugPrint(
            '[InstructorDashboard] Applied Stats: '
            'overall=$overallScore, '
            'mgmt=$managementScore, '
            'perf=$performanceScore, '
            'evals=$totalEvaluations',
          );

          _recentFeedback = feedback; // update the recent feedback list

          // Build the history chart from the last 4 terms only — fit in the bar chart
          if ((historyData as List).isNotEmpty) {
            _myHistory.clear();
            // Sort semantically: oldest year first, then 1st → 2nd → Summer within year
            final semOrder = {'1st': 0, '2nd': 1, 'Summer': 2};
            final sorted = List.from(historyData)
              ..sort((a, b) {
                final aTerm = a['academic_terms'];
                final bTerm = b['academic_terms'];
                final aYear =
                    int.tryParse(
                      aTerm?['academic_year']?.toString().split('-').first ??
                          '0',
                    ) ??
                    0;
                final bYear =
                    int.tryParse(
                      bTerm?['academic_year']?.toString().split('-').first ??
                          '0',
                    ) ??
                    0;
                if (aYear != bYear) return aYear.compareTo(bYear);
                final aSem = aTerm?['semester']?.toString() ?? '';
                final bSem = bTerm?['semester']?.toString() ?? '';
                // Match first word to semOrder key
                final aSemKey = semOrder.keys.firstWhere(
                  (k) => aSem.startsWith(k),
                  orElse: () => '',
                );
                final bSemKey = semOrder.keys.firstWhere(
                  (k) => bSem.startsWith(k),
                  orElse: () => '',
                );
                return (semOrder[aSemKey] ?? 99).compareTo(
                  semOrder[bSemKey] ?? 99,
                );
              });
            // Take the 4 most recent terms (end of sorted list) in order
            final recentHistory = sorted.length > 4
                ? sorted.sublist(sorted.length - 4)
                : sorted;
            for (var item in recentHistory) {
              final term = item['academic_terms'];
              String label = 'Sem'; // default label if term data missing
              if (term != null) {
                // Build compact label: "1st\n25-26"
                final ay = term['academic_year'].toString(); // e.g. "2025-2026"
                final ayParts = ay.split('-');
                final yearShort = ayParts.length == 2
                    ? '${ayParts[0].length >= 2 ? ayParts[0].substring(ayParts[0].length - 2) : ayParts[0]}-'
                          '${ayParts[1].length >= 2 ? ayParts[1].substring(ayParts[1].length - 2) : ayParts[1]}'
                    : ay;
                label =
                    '${term['semester'].toString().substring(0, 3)}\n$yearShort';
              }
              _myHistory.add({
                'sem': label,
                'score':
                    (item['combined_score_mean'] as num?)?.toDouble() ??
                    (item['overall_mean'] as num?)?.toDouble() ??
                    0.0,
              });
            }
          }
        });

        // Save all this fresh data to cache so it loads instantly next time
        try {
          final prefs = await SharedPreferences.getInstance();
          final cacheData = {
            'termId': _currentTermId,
            'semester': _currentSemester,
            'academicYear': _currentYear,
            'name': _instructorName,
            'dept': _instructorDept,
            'overallScore': _myPerformance['overallScore'],
            'managementScore': _myPerformance['managementScore'],
            'performanceScore': _myPerformance['performanceScore'],
            'totalEvaluations': _myPerformance['totalEvaluations'],
            'feedback': _recentFeedback,
            'history': _myHistory,
          };
          await prefs.setString(
            'instructor_profile_${widget.userId}',
            jsonEncode(cacheData),
          );
        } catch (e) {
          debugPrint('[INSTRUCTOR] Failed to save cache: $e');
        }
      }
    } catch (e) {
      debugPrint('Error fetching instructor profile: $e');
      if (mounted)
        setState(() {}); // refresh even on error so UI dont get stuck
    }
  }

  // Manual sync handler — what happens when the instructor taps the sync button
  Future<void> _handleManualSync() async {
    await _refreshDashboardData(
      isInitial: false,
    ); // isInitial false = show the snackbar
  }

  @override
  void dispose() {
    // Clean up subscriptions or the memory will cry. Importente ni.
    _settingsSubscription?.cancel();
    // removeChannel() both unsubscribes AND removes the channel from the Supabase
    // client registry — prevents server-side resource leaks on repeated navigation.
    // Fire-and-forget is intentional: dispose() is synchronous in Flutter.
    if (_interventionChannel != null) {
      _supabase.removeChannel(_interventionChannel!);
    }
    super.dispose();
  }

  // Subscribes to real-time changes on intervention_reports for this instructor.
  // The dept head can send intervention notices — this listens and reacts in real time.
  void _subscribeToInterventions() {
    if (_interventionChannelActive)
      return; // already subscribed, ayaw double subscribe
    _interventionChannelActive = true;

    // Create a Supabase realtime channel scoped to this instructor's reports
    _interventionChannel = _supabase
        .channel('instructor_interventions_${widget.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all, // listen for INSERT, UPDATE, DELETE
          schema: 'public',
          table: 'intervention_reports',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'instructor_id',
            value: widget.userId, // only care about notices for THIS instructor
          ),
          callback: (payload) {
            // Whenever something changes, reload the intervention list
            if (mounted) _fetchInterventionReports();
          },
        )
        .subscribe();

    // Also do an immediate fetch — dont wait for a change event to know whats there
    _fetchInterventionReports();
  }

  // Fetches unresolved intervention reports from the dept head.
  // These are the "you are in trouble" notices the instructor can see but NOT dismiss.
  Future<void> _fetchInterventionReports() async {
    try {
      final data = await _supabase
          .from('intervention_reports')
          .select(
            'id, action_type, notes, status, created_at, dean_id, user_info!dean_id(first_name, last_name)',
          )
          .eq('instructor_id', widget.userId)
          .neq(
            'status',
            'Resolved',
          ) // only get active ones, not already resolved
          .order('created_at', ascending: false); // newest problem first

      if (mounted) {
        setState(() {
          _interventionReports = (data as List).cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      debugPrint('Error fetching intervention reports: $e');
    }
  }

  // Performance data map — starts all zero, gets filled after fetch
  final Map<String, dynamic> _myPerformance = {
    'overallScore': 0.0,
    'managementScore': 0.0,
    'performanceScore': 0.0,
    'totalEvaluations': 0,
    'trend': 'neutral', // reserved for future use — bahala na
  };

  // History list for the bar chart — max 4 items, older to newer
  final List<Map<String, dynamic>> _myHistory = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        foregroundColor: AppColors.textInverted,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2E1608), AppColors.textPrimary],
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textInverted),
        // Hamburger opens the outer MainScaffold drawer (not the inner Scaffold).
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AppColors.textInverted),
          tooltip: 'Open menu',
          onPressed: () => MainScaffold.drawerKey.currentState?.openDrawer(),
        ),
        title: const Text(
          'My Dashboard',
          style: TextStyle(
            color: AppColors.textInverted,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          // Sync button — shows spinner when syncing, shows icon when idle
          IconButton(
            tooltip: 'Manual Sync',
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textInverted,
                    ),
                  )
                : const Icon(Icons.sync_rounded, color: AppColors.textInverted),
            onPressed: _isSyncing
                ? null
                : _handleManualSync, // disabled while already syncing
          ),
          // Notification bell — shows badge count if there are active intervention notices
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.notifications_rounded,
                  color: AppColors.textInverted,
                ),
                tooltip: _interventionReports.isEmpty
                    ? 'No active notices'
                    : '${_interventionReports.length} active notice(s)',
                onPressed: () {
                  if (_interventionReports.isEmpty) {
                    // Good news — no trouble today
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          '✅ No active intervention notices from your department head.',
                        ),
                        backgroundColor: AppColors.success,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  } else {
                    // Uh oh — the dept head has words for you
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '⚠️ You have ${_interventionReports.length} active notice(s) from your department head.',
                        ),
                        backgroundColor: AppColors.error,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
              // Red badge bubble showing the count of active notices — hard to ignore
              if (_interventionReports.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '${_interventionReports.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),

      // drawer removed — MainScaffold now owns the side drawer for all roles

      // Main body — scrollable dashboard content, pull to refresh also works
      body: _isInitialLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : RefreshIndicator(
              onRefresh: _handleManualSync, // pull down to trigger manual sync
              color: AppColors.primary,
              child: SafeArea(
                child: SingleChildScrollView(
                  physics:
                      const AlwaysScrollableScrollPhysics(), // always scrollable for pull-to-refresh
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- INTERVENTION NOTICES (read-only, from dept head) ---
                      // Show these warning cards if there are active notices. Cannot dismiss.
                      if (_interventionReports.isNotEmpty) ...[
                        ..._interventionReports.map((report) {
                          final deanInfo = report['user_info'];
                          // Get the dept head's name, or use generic label if data missing
                          final deanName = deanInfo is Map
                              ? '${deanInfo['first_name'] ?? ''} ${deanInfo['last_name'] ?? ''}'
                                    .trim()
                              : 'Your Department Head';
                          final date = report['created_at'] != null
                              ? DateTime.tryParse(
                                  report['created_at'],
                                )?.toLocal()
                              : null;
                          final dateStr = date != null
                              ? '${date.month}/${date.day}/${date.year}'
                              : 'Recently';

                          // Render the intervention notice card — red and scary on purpose
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.error.withValues(
                                    alpha: 0.14,
                                  ),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.error.withValues(
                                          alpha: 0.10,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.warning_amber_rounded,
                                        color: AppColors.error,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Text(
                                        'Official Notice — Action Required',
                                        style: TextStyle(
                                          color: AppColors.error,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    // Read-only lock icon — instructor cannot dismiss this. Only dept head can.
                                    Tooltip(
                                      message:
                                          'Only your department head can remove this notice',
                                      child: Icon(
                                        Icons.lock_outline,
                                        color: AppColors.error.withValues(
                                          alpha: 0.6,
                                        ),
                                        size: 16,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                _buildNoticeRow('From', deanName),
                                const SizedBox(height: 4),
                                _buildNoticeRow(
                                  'Action',
                                  report['action_type'] ?? 'N/A',
                                ),
                                if ((report['notes'] as String?)?.isNotEmpty ==
                                    true) ...[
                                  const SizedBox(height: 4),
                                  _buildNoticeRow('Notes', report['notes']),
                                ],
                                const SizedBox(height: 8),
                                Text(
                                  dateStr,
                                  style: const TextStyle(
                                    color: AppColors.error,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 12),
                      ],

                      // --- WELCOME CARD ---
                      // The big gradient hero card at the top — shows overall score and greetings
                      Entrance(
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF2E1608),
                                AppColors.textPrimary,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.textPrimary.withValues(
                                  alpha: 0.3,
                                ),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Stack(
                              children: [
                                // soft orange glow, upper right — echoes the login hero
                                Positioned(
                                  top: -70,
                                  right: -50,
                                  child: Container(
                                    width: 220,
                                    height: 220,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          AppColors.primary.withValues(
                                            alpha: 0.35,
                                          ),
                                          AppColors.primary.withValues(
                                            alpha: 0.0,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Greeting with first name only — "Welcome back, Juan!" type energy
                                      Text(
                                        'Welcome back, ${_instructorName.split(' ')[0]}!',
                                        style: const TextStyle(
                                          color: AppColors.textInvertedDim,
                                          fontSize: 16,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Your Performance Overview',
                                        style: TextStyle(
                                          color: AppColors.textInverted,
                                          fontSize: 28,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.8,
                                          height: 1.1,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      // Show the current active semester and year
                                      Text(
                                        'Active Term: $_currentSemester, $_currentYear',
                                        style: const TextStyle(
                                          color: AppColors.textInvertedDim,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(height: 20),

                                      // The big score number — the main attraction of this whole card
                                      Builder(
                                        builder: (context) {
                                          final overall =
                                              (_myPerformance['overallScore']
                                                      as num?)
                                                  ?.toDouble() ??
                                              0.0;
                                          final hasData =
                                              overall >
                                              0; // no data = show N/A, not 0.00
                                          final vd =
                                              Subject.getVerbalDescription(
                                                overall,
                                              ); // e.g. "Outstanding"
                                          return Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      hasData
                                                          ? overall
                                                                .toStringAsFixed(
                                                                  2,
                                                                )
                                                          : 'N/A',
                                                      style: const TextStyle(
                                                        color:
                                                            AppColors.primary,
                                                        fontSize:
                                                            52, // big number = big ego boost
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        height: 1.0,
                                                        letterSpacing: -1,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    const Text(
                                                      'Overall Weighted Mean',
                                                      style: TextStyle(
                                                        color: AppColors
                                                            .textInvertedDim,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              // Verbal description badge — only show if there is actual data
                                              if (hasData)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 14,
                                                        vertical: 8,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primary
                                                        .withValues(
                                                          alpha: 0.25,
                                                        ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          100,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    vd,
                                                    style: const TextStyle(
                                                      color: AppColors
                                                          .textInverted,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          );
                                        },
                                      ),

                                      const SizedBox(height: 16),
                                      const Divider(
                                        color: AppColors.textInvertedFaint,
                                        thickness: 1,
                                        height: 1,
                                      ),
                                      const SizedBox(height: 16),

                                      // Three stats side by side: Management, Performance, Evaluations
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          _buildStat(
                                            'Management',
                                            _myPerformance['managementScore']
                                                .toStringAsFixed(2),
                                          ),
                                          Container(
                                            width: 1,
                                            height: 40,
                                            color: AppColors.textInvertedFaint,
                                          ), // divider line
                                          _buildStat(
                                            'Performance',
                                            _myPerformance['performanceScore']
                                                .toStringAsFixed(2),
                                          ),
                                          Container(
                                            width: 1,
                                            height: 40,
                                            color: AppColors.textInvertedFaint,
                                          ), // another divider
                                          _buildStat(
                                            'Evaluations',
                                            _myPerformance['totalEvaluations']
                                                .toString(),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 20),
                                      // Button to open the full official SAST report — the formal paperwork
                                      Pressable(
                                        child: Container(
                                          width: double.infinity,
                                          height: 52,
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [
                                                AppColors.primary,
                                                AppColors.primaryDeep,
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppColors.primary
                                                    .withValues(alpha: 0.4),
                                                blurRadius: 16,
                                                offset: const Offset(0, 6),
                                              ),
                                            ],
                                          ),
                                          child: ElevatedButton.icon(
                                            onPressed: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => DetailedReportScreen(
                                                  userId: widget.userId,
                                                  instructorName:
                                                      _instructorName,
                                                  department: _instructorDept,
                                                  termId: _currentTermId,
                                                  term: _currentSemester,
                                                  academicYear: _currentYear,
                                                  managementScore:
                                                      (_myPerformance['managementScore']
                                                              as num?)
                                                          ?.toDouble() ??
                                                      0.0,
                                                  performanceScore:
                                                      (_myPerformance['performanceScore']
                                                              as num?)
                                                          ?.toDouble() ??
                                                      0.0,
                                                  overallScore:
                                                      (_myPerformance['overallScore']
                                                              as num?)
                                                          ?.toDouble() ??
                                                      0.0,
                                                  totalEvaluations:
                                                      _myPerformance['totalEvaluations'],
                                                ),
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.description_outlined,
                                              size: 18,
                                            ),
                                            label: const Text(
                                              'View Official SAST Report',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.transparent,
                                              foregroundColor:
                                                  AppColors.textPrimary,
                                              shadowColor: Colors.transparent,
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // --- SUBJECT BREAKDOWN ---
                      // Shows list of current subjects — each tappable for detail
                      Text(
                        'Current Classes'.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Consumer<SubjectsProvider>(
                        builder: (context, provider, _) {
                          final subjects = provider.subjects;
                          if (subjects.isEmpty) {
                            // No subjects? Show a nice empty state card instead
                            return _buildEmptySubjectsCard(context);
                          }
                          // Map each subject into a card widget
                          return Column(
                            children: subjects
                                .map((subject) => _buildSubjectCard(subject))
                                .toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 32),

                      // --- TWO-COLUMN LAYOUT: HISTORY & FEEDBACK ---
                      // Growth chart on the left, recent feedback on the right
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left side — bar chart showing score trend across past terms
                          Expanded(
                            flex: 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Growth'.toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Entrance(
                                  index: 1,
                                  child: Container(
                                    height: 180,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.textPrimary
                                              .withValues(alpha: 0.08),
                                          blurRadius: 24,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: _myHistory.map<Widget>((data) {
                                        // Bar height is proportional to score out of 5.0
                                        double barHeight =
                                            (data['score'] / 5.0) * 100;
                                        // Flexible lets bars share the available width equally —
                                        // avoids overflow when there are 4+ history entries
                                        return Flexible(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              Text(
                                                '${data['score']}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.textPrimary,
                                                  fontSize: 11,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Container(
                                                width: 20,
                                                height: barHeight,
                                                decoration: BoxDecoration(
                                                  gradient:
                                                      const LinearGradient(
                                                        begin:
                                                            Alignment.topCenter,
                                                        end: Alignment
                                                            .bottomCenter,
                                                        colors: [
                                                          AppColors.primary,
                                                          AppColors.primaryDeep,
                                                        ],
                                                      ),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              // Label fits inside whatever width Flexible assigns
                                              Text(
                                                data['sem'].toString(),
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      AppColors.textSecondary,
                                                ),
                                                textAlign: TextAlign.center,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Right side — scrollable list of recent student remarks
                          Expanded(
                            flex: 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Recent Feedback'.toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Entrance(
                                  index: 2,
                                  child: Container(
                                    height: 180,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.textPrimary
                                              .withValues(alpha: 0.08),
                                          blurRadius: 24,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    // Show placeholder if no feedback, else show the scrollable list
                                    child: _recentFeedback.isEmpty
                                        ? const Center(
                                            child: Text(
                                              'No feedback yet',
                                              style: TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 12,
                                              ),
                                            ),
                                          )
                                        : ListView.separated(
                                            itemCount: _recentFeedback.length,
                                            separatorBuilder:
                                                (context, index) =>
                                                    const Divider(height: 16),
                                            itemBuilder: (context, index) {
                                              return Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const Icon(
                                                    Icons.format_quote,
                                                    color:
                                                        AppColors.primaryText,
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      _recentFeedback[index],
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: AppColors
                                                            .textPrimary,
                                                        fontStyle:
                                                            FontStyle.italic,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
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

  // Builds one row in the intervention notice card — label on left, value on right
  Widget _buildNoticeRow(String label, String? value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            '$label:',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value ?? 'N/A',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  // Builds a single stat label+value pair used in the hero card bottom row
  Widget _buildStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textInvertedDim,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  // Empty state card when no subjects are assigned yet — tap it to go to subjects screen
  Widget _buildEmptySubjectsCard(BuildContext context) {
    return Pressable(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          // ChangeNotifierProvider.value forwards the EXISTING instance into the new route.
          final subjectsProvider = context.read<SubjectsProvider>();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChangeNotifierProvider.value(
                value: subjectsProvider,
                child: MySubjectsScreen(userId: widget.userId),
              ),
            ),
          );
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.textPrimary.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: AppColors.primaryText,
                ),
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
      ),
    );
  }

  // Subject card shown in the dashboard's "Current Classes" section — tap to see details
  Widget _buildSubjectCard(Subject subject) {
    return Pressable(
      child: InkWell(
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
        borderRadius: BorderRadius.circular(20),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.textPrimary.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Row(
              children: [
                // Icon container on the left side
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.class_, color: AppColors.primaryText),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            // Subject code in small text, like "CS101"
                            child: Text(
                              subject.code,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryText,
                                fontSize: 12,
                                letterSpacing: 0.2,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      // Full subject name in bigger text
                      Text(
                        subject.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          letterSpacing: -0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Arrow icon on the right — signals it's tappable
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // _buildDrawerItem() removed — drawer is now managed by MainScaffold.
}
