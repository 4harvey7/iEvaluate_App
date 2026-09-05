// lib/dept_head/department_dashboard_screen.dart
// This is the BIG BOSS screen. The dept head open this and feel very important.
// Shows scores, alerts, word clouds — basically everything the dean need to not panic.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../core/services/system_settings_service.dart';
import '../core/services/evaluation_service.dart';
import '../core/navigation/main_scaffold.dart';
import 'subject_analytics_screen.dart';
import 'intervention_reports_screen.dart';
import '../widgets/apple_ui.dart';

// The main widget for the department dashboard. Very importente kaayo.
// It is stateful because data changes and we need to rebuild the UI — dili pwede static.
class DepartmentDashboardScreen extends StatefulWidget {
  final String userId;
  const DepartmentDashboardScreen({super.key, required this.userId});

  @override
  State<DepartmentDashboardScreen> createState() => _DepartmentDashboardScreenState();
}

class _DepartmentDashboardScreenState extends State<DepartmentDashboardScreen> {
  // Services — the workers behind the scene. pray lang they don't throw exception.
  final _settingsService = SystemSettingsService();
  final _evaluationService = EvaluationService();
  final _supabase = Supabase.instance.client;


  // These start with '...' because we don't have data yet. Patience, friend.
  String _currentSemester = '...';
  String _currentYear = '...';
  String _deanName = '...';

  // Stream subscription for settings — listens for changes like a worried parent
  StreamSubscription<SystemSettings>? _settingsSubscription;

  // --- DYNAMIC DATA ---
  // All the important numbers the boss want to see. wala choice, we fetch them all.
  Map<String, dynamic> _deptInfo = {
    'college': '',
    'dean': '',
    'overallScore': 0.0,
    'totalEvals': '0',
    'completionRate': 0.0,
    'facultyCount': 0,
    'deactivatedWithResults': 0,
    'evaluatedCount': 0,
  };

  /// One line saying what the department average is actually based on.
  ///
  /// Null when the number speaks for itself -- every faculty member on the
  /// roster has results this term. Otherwise the average describes fewer
  /// people than the card implies. A department average computed from 2 of 20
  /// scanned instructors is not the department's score, and without this line
  /// it reads exactly as though it were.
  String? get _coverageNote {
    final evaluated = _deptInfo['evaluatedCount'] as int? ?? 0;
    final faculty = _deptInfo['facultyCount'] as int? ?? 0;
    if (evaluated == 0) return 'No evaluations yet this term';
    if (faculty > evaluated) return 'Based on $evaluated of $faculty faculty';
    return null;
  }

  /// One line under the Active Faculty number, when it isn't purely a count of
  /// currently-active accounts.
  ///
  /// The Faculty tab keeps a deactivated instructor listed for as long as they
  /// still hold a result this term -- their score is real and it is still
  /// inside the department average, so hiding them from the roster while
  /// counting them in the numbers was its own inconsistency. This card's
  /// headcount agrees with that roster on purpose, which means "Active
  /// Faculty" can include someone who is not, strictly, active any more. This
  /// line is the difference showing its work, so the number is never read as
  /// "5 people currently teaching" when it means "5 people on the roster."
  /// Gone on its own once the term rolls past that person's last result, the
  /// same moment the roster stops listing them and the count drops to match.
  String? get _facultyNote {
    final deactivated = _deptInfo['deactivatedWithResults'] as int? ?? 0;
    if (deactivated <= 0) return null;
    return deactivated == 1
        ? '1 deactivated, results still counted'
        : '$deactivated deactivated, results still counted';
  }

  // Alerts are the problems we hope to never see but always plan for — bahala na
  List<ActionAlert> _dynamicAlerts = [];
  // Word cloud — the AI version of "what students actually think"
  List<Map<String, dynamic>> _wordCloudData = [];
  // Department performance history across terms
  List<Map<String, dynamic>> _deptHistory = [];
  // The current term ID — basin naa pa previous term, we make sure its the right one
  String _currentTermId = '';
  // Key to scroll down to alerts
  final GlobalKey _alertsKey = GlobalKey();

  Future<void> _loadCachedDashboard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('dept_dashboard_${widget.userId}');
      if (cached != null) {
        final data = jsonDecode(cached);
        if (mounted) {
          setState(() {
            _currentSemester = data['semester'] ?? _currentSemester;
            _currentYear = data['year'] ?? _currentYear;
            _currentTermId = data['termId'] ?? _currentTermId;
            // Merged OVER the defaults rather than replacing them. A cache
            // written by an older build is missing whichever keys that build
            // did not have, and interpolating a missing one prints "null" on
            // the card until the fresh fetch lands.
            _deptInfo = {
              ..._deptInfo,
              ...?(data['deptInfo'] as Map?)?.cast<String, dynamic>(),
            };
            
            if (data['wordCloud'] != null) {
              _wordCloudData = List<Map<String, dynamic>>.from(data['wordCloud'].map((x) => Map<String, dynamic>.from(x)));
            }
            if (data['history'] != null) {
              _deptHistory = List<Map<String, dynamic>>.from(data['history'].map((x) => Map<String, dynamic>.from(x)));
            }
            if (data['alerts'] != null) {
              _dynamicAlerts = (data['alerts'] as List).map((a) => ActionAlert(
                type: a['type'],
                title: a['title'],
                desc: a['desc'],
                instructorId: a['instructorId'],
                instructorName: a['instructorName'],
                subjectCode: a['subjectCode'],
                dateFlagged: DateTime.parse(a['dateFlagged']),
              )).toList();
            }
          });
          debugPrint('[DEPT HEAD] ⚡ Loaded cached dashboard instantly.');
        }
      }
    } catch (e) {
      debugPrint('[DEPT HEAD] Failed to load cache: $e');
    }
  }

  // Called once when the screen is born into this world
  @override
  void initState() {
    super.initState();
    _loadCachedDashboard(); // Load stale data instantly!
    _subscribeToSettings(); // Start listening for semester changes
    _loadInitialData(); // Fetch all the data — go go go
  }

  // Called when screen is destroyed — cancel subscription or memory will leak like old pipe
  @override
  void dispose() {
    _settingsSubscription?.cancel(); // Stop listening, we leaving
    super.dispose();
  }

  // Subscribe to live settings stream — so if admin changes the term, this screen knows immediately
  // No need to refresh manually. importente kaayo this part.
  void _subscribeToSettings() {
    _settingsSubscription = _settingsService.streamSettings().listen((settings) {
      if (mounted) {
        final newTermId = settings.termId ?? '';
        // Only reload data if the term actually changed — dili ta waste API calls
        final termChanged = newTermId.isNotEmpty && newTermId != _currentTermId;
        setState(() {
          _currentSemester = settings.semester;
          _currentYear = settings.academicYear;
          if (termChanged) _currentTermId = newTermId;
        });
        if (termChanged) _loadInitialData(); // New term detected — fetch fresh data
      }
    });
  }

  // The big data loader — fetches everything the dashboard need in one go.
  // If something fail, it catch the error and show empty state. dili ta crash.
  Future<void> _loadInitialData() async {
    try {
      // Get the dept summary — overall score, completion rate, etc.
      final summary = await _evaluationService.getDepartmentSummary(widget.userId);
      // Use dept average as threshold: show instructors below the dept mean
      // If no average yet, default to 3.0 so alerts still work — smart move
      final deptAvg = summary.averageScore > 0 ? summary.averageScore : 3.0;
      final alerts = await _evaluationService.getDepartmentAlerts(widget.userId, threshold: deptAvg);
      final wordCloud = await _evaluationService.getDeptWordCloud(widget.userId);
      // Fetch the historical performance of the whole department
      final history = await _evaluationService.getDepartmentHistory(widget.userId);
      
      // Fetch User Info — we need the dean name so the drawer don't say "..."
      final user = await _supabase
          .from('user_info')
          .select('first_name, last_name')
          .eq('id', widget.userId)
          .maybeSingle();

      // Fetch Department Info — which college this dean belong to
      final deptData = await _supabase
          .from('department_table')
          .select('department_name!Department_name_ID(d_name)')
          .eq('user_id', widget.userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          // Combine first and last name — simple but we need to do it
          if (user != null) {
            _deanName = '${user['first_name']} ${user['last_name']}';
          }
          
          // Default to 'Department' if no dept data found — better than showing null
          String deptName = 'Department';
          if (deptData != null && deptData['department_name'] != null) {
            deptName = deptData['department_name']['d_name'];
          }

          // Fill the deptInfo map with all the numbers — this feeds the UI cards
          _deptInfo = {
            'college': deptName,
            'dean': _deanName,
            // Show dash if score is zero — no data is better than showing fake 0
            'overallScore': summary.averageScore > 0
                ? summary.averageScore.toStringAsFixed(2)
                : '—',
            'totalEvals': summary.totalEvaluations.toString(),
            'completionRate': summary.completionRate,
            'facultyCount': summary.facultyCount,
            'deactivatedWithResults': summary.deactivatedWithResults,
            'evaluatedCount': summary.evaluatedCount,
          };
          _dynamicAlerts = alerts; // Store alerts for the dashboard and notification bell
          _wordCloudData = wordCloud; // Store word cloud data for the AI section
          _deptHistory = history; // Store the history chart data
        });

        // Save to cache so the user doesn't wait next time they open the app
        try {
          final prefs = await SharedPreferences.getInstance();
          final cacheData = {
            'semester': _currentSemester,
            'year': _currentYear,
            'termId': _currentTermId,
            'deptInfo': _deptInfo,
            'wordCloud': _wordCloudData,
            'history': _deptHistory,
            'alerts': _dynamicAlerts.map((a) => {
              'type': a.type,
              'title': a.title,
              'desc': a.desc,
              'instructorId': a.instructorId,
              'instructorName': a.instructorName,
              'subjectCode': a.subjectCode,
              'dateFlagged': a.dateFlagged.toIso8601String(),
            }).toList(),
          };
          await prefs.setString('dept_dashboard_${widget.userId}', jsonEncode(cacheData));
        } catch (e) {
          debugPrint('Failed to save dept cache: $e');
        }
      }
    } catch (e) {
      // If anything fails, just print it and show empty state — wala choice
      debugPrint('Error loading initial data: $e');
      if (mounted) setState(() {});
    }
  }

  // --- UI Icons and Colors for Alerts ---
  // Decide which icon to show base on alert type — critical get the scary warning icon
  IconData _getAlertIcon(String type) {
    if (type == 'critical') return Icons.warning_amber_rounded; // This one look serious
    return Icons.analytics; // Default — less scary but still notable
  }

  // Decide the color for alerts — red for critical, orange for just "pay attenshun"
  Color _getAlertColor(String type) {
    if (type == 'critical') return AppColors.error; // RED ALERT. not good.
    return AppColors.warning; // Yellow — proceed with caution
  }

  // Growth-chart colours — one per school year, so 1st and 2nd sem of the same
  // year always look the same and the eye can group them without reading labels.
  static const List<Color> _yearColors = [
    AppColors.primary,   // blue
    AppColors.teal,      // teal
    AppColors.indigo,    // indigo
    AppColors.purple,    // purple
    AppColors.rose,      // rose
  ];

  /// School year of a history entry. Prefers the real `academic_year` field;
  /// falls back to the "1st\n24-25" label suffix so a cached payload written
  /// before that field existed still groups correctly.
  String _historyYear(Map<String, dynamic> data) {
    final year = data['year']?.toString() ?? '';
    if (year.isNotEmpty) return year;
    final label = data['sem']?.toString() ?? '';
    return label.contains('\n') ? label.split('\n').last : label;
  }

  /// Colour for [year], picked by its chronological position in the chart so
  /// neighbouring years never collide and the assignment stays stable across
  /// rebuilds. Wraps around once there are more than five years on screen.
  Color _yearColor(String year) {
    final years = <String>[];
    for (final entry in _deptHistory) {
      final y = _historyYear(entry);
      if (!years.contains(y)) years.add(y); // _deptHistory is already sorted oldest → newest
    }
    final index = years.indexOf(year);
    if (index < 0) return AppColors.primary;
    return _yearColors[index % _yearColors.length];
  }

  // Word cloud colours — cycle through these based on word index
  // We have 5 colors, repeat if more than 5 words. bahala na, looks nice anyway.
  static const List<Color> _cloudColors = [
    AppColors.primary,           // Vibrant Orange
    Color(0xFF4ADE80),           // Bright Neon Green
    Colors.lightBlueAccent,      // Bright Blue
    Color(0xFFFACC15),           // Bright Yellow
    Color(0xFFF87171),           // Bright Coral/Red
  ];

  // The main build method — builds the entire screen UI.
  // Its long but thats because there is a LOT of info to show. dili ta complain.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        // Hamburger opens the outer MainScaffold drawer (not the inner Scaffold).
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
          tooltip: 'Open menu',
          onPressed: () => MainScaffold.drawerKey.currentState?.openDrawer(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Department Overview', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            // Shows current semester and year — so dean know which term they looking at
            Text('$_currentSemester, $_currentYear', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          // Notification Pill — much more premium than a boring icon
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  if (_dynamicAlerts.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ All clear! No active alerts.'),
                        backgroundColor: AppColors.success,
                        behavior: SnackBarBehavior.floating,
                      )
                    );
                  } else {
                    // Smoothly scroll down to the alerts section!
                    if (_alertsKey.currentContext != null) {
                      Scrollable.ensureVisible(
                        _alertsKey.currentContext!,
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOutQuart,
                        alignment: 0.1, // Leave a little padding at the top
                      );
                    }
                  }
                },
                child: _dynamicAlerts.isNotEmpty
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.notifications_active, color: AppColors.error, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '${_dynamicAlerts.length} Alerts',
                              style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.notifications_none, color: AppColors.textSecondary, size: 20),
                      ),
              ),
            ),
          ),
        ],
      ),


      // drawer removed — MainScaffold now owns the side drawer for all roles

      // ==========================================
      // MAIN CONTENT
      // The scrollable body — everything below the appbar
      // ==========================================
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadInitialData, // Pull down to reload — the classic trick
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(), // Always scrollable so refresh work even if content is short
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Big title — "Executive Dashboard" sounds fancy, dean will like
                ApplePageHeader(
                  eyebrow: 'Department Leadership',
                  title: 'Executive Overview',
                  subtitle: _deptInfo['college'] ?? 'Department',
                ),
                const SizedBox(height: 24),

                // --- TOP SUMMARY CARD ---
                // The hero card — shows overall score, faculty count, and completion rate
                // Looks nice with gradient background. importente kaayo first impression.
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: AppColors.heroGradient),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 8))],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Department Average', style: TextStyle(color: Colors.white70, fontSize: 14)),
                                const SizedBox(height: 4),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                    // The big number — the overall dept score. Hopefully not low.
                    // White, not AppColors.primary: primary IS heroGradient's
                    // end stop, so the headline figure was being painted in the
                    // colour of the card behind it.
                    Text(
                      '${_deptInfo['overallScore']}',
                      style: const TextStyle(color: AppColors.textInverted, fontSize: 40, fontWeight: FontWeight.bold),
                    ),
                                    const Text('/5.0', style: TextStyle(color: Colors.white70, fontSize: 16)),
                                  ],
                                ),
                                if (_coverageNote != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    _coverageNote!,
                                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // Thin divider between score and faculty count — visual separator
                          Container(width: 1, height: 60, color: Colors.white24),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Active Faculty', style: TextStyle(color: Colors.white70, fontSize: 14)),
                                const SizedBox(height: 4),
                                // Total count of instructors in the dept — just a number, but importente
                                Text('${_deptInfo['facultyCount']}', style: const TextStyle(color: AppColors.surface, fontSize: 32, fontWeight: FontWeight.bold)),
                                if (_facultyNote != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    _facultyNote!,
                                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                // --- DEPARTMENT HISTORY (GROWTH CHART) ---
                const AppleSectionHeader(
                  title: 'Department Growth',
                  subtitle: 'Weighted mean across recent academic terms.',
                ),
                const SizedBox(height: 12),
                RepaintBoundary(
                  child: Container(
                    height: 200, // Slightly shorter for a tighter look
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderHairline, width: 1), // Use hairline border to blend with app
                    ),
                    child: _deptHistory.isEmpty
                        ? const Center(child: Text('No historical data available yet', style: TextStyle(color: AppColors.textTertiary, fontSize: 13)))
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            bool isScrollable = _deptHistory.length > 5;
                            
                            Widget content = Row(
                              mainAxisAlignment: isScrollable ? MainAxisAlignment.start : MainAxisAlignment.spaceAround,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: _deptHistory.map<Widget>((data) {
                                final score = (data['score'] as num?)?.toDouble() ?? 0.0;
                                // Scale height, max height ~100px out of 5.0
                                double barHeight = (score / 5.0) * 100;
                                
                                // Colour by school year — every semester of the
                                // same year shares one colour.
                                final Color barColor = _yearColor(_historyYear(data));

                                return Padding(
                                  padding: EdgeInsets.only(right: isScrollable ? 20 : 0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      // Clean bold text instead of heavy badge
                                      Text(
                                        score.toStringAsFixed(2),
                                        style: TextStyle(fontWeight: FontWeight.w800, color: barColor, fontSize: 13),
                                      ),
                                      const SizedBox(height: 8),
                                      // Animated Bar with subtle bottom fade
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 800),
                                        curve: Curves.easeOutQuart,
                                        width: 34,
                                        height: barHeight,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              barColor.withValues(alpha: 0.15),
                                              barColor,
                                            ],
                                            begin: Alignment.bottomCenter,
                                            end: Alignment.topCenter,
                                          ),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      // Semester Label
                                      SizedBox(
                                        width: 50,
                                        child: Text(
                                          data['sem'].toString(),
                                          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w600, height: 1.2),
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.visible,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            );

                            if (isScrollable) {
                              return SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: content,
                              );
                            }
                            
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: content,
                            );
                          },
                        ),
                  ),
                ),
                const SizedBox(height: 32),

                // --- ACTION REQUIRED ALERTS ---
                // This section shows which instructors need attention — basin naa problema below
                AppleSectionHeader(
                  key: _alertsKey,
                  title: 'Action Required',
                  subtitle: 'Faculty and curriculum signals that need review.',
                ),
                const SizedBox(height: 12),
                // If no alerts — show green "all good" message. Rare but nice.
                if (_dynamicAlerts.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle, color: AppColors.success),
                        SizedBox(width: 12),
                        Text('No critical issues detected.', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                else
                  // Got alerts — show them all as tappable cards
                  Column(
                    children: _dynamicAlerts.map((alert) {
                      final color = _getAlertColor(alert.type); // Red or orange base on severity
                      return Card(
                        color: AppColors.surface,
                        elevation: 1,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: color.withValues(alpha: 0.3), width: 1), // Colored border hint
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          leading: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                            child: Icon(_getAlertIcon(alert.type), color: color),
                          ),
                          title: Text(alert.title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(alert.desc, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4), overflow: TextOverflow.ellipsis),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textSecondary),
                          onTap: () {
                            // Navigate base on what kind of alert it is
                            if (alert.instructorId != null) {
                              // Instructor problem — go to intervention reports
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => InterventionReportsScreen(userId: widget.userId),
                              ));
                            } else if (alert.subjectCode != null) {
                              // Subject problem — go to subject analytics
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => SubjectAnalyticsScreen(userId: widget.userId),
                              ));
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 24),

                // --- DEPARTMENT AI WORD CLOUD ---
                // Shows common words from student feedback — AI-processed, looks fancy
                // murag a real word cloud but we just use Wrap widget. smart shortcut.
                const Text('Department Voice (AI Analysis)', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Aggregated themes from all student comments across the college.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 16),
                RepaintBoundary(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.textPrimary, Color(0xFF0F172A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: AppColors.textPrimary.withValues(alpha: 0.2), blurRadius: 14, offset: const Offset(0, 6))
                    ],
                  ),
                  child: _wordCloudData.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'No feedback data yet for this term.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                        ),
                      ),
                    )
                  : Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12.0,
                    runSpacing: 12.0,
                    children: List.generate(_wordCloudData.length, (i) {
                      final wordData = _wordCloudData[i];
                      final count = (wordData['total_count'] as num?)?.toInt() ?? 1;
                      
                      // Use relative scaling: most frequent word is 1.0, least is near 0.0
                      final maxCount = (_wordCloudData.first['total_count'] as num?)?.toInt() ?? 1;
                      final double ratio = maxCount > 0 ? (count / maxCount) : 1.0;
                      
                      // Scale between 12px and 32px based on frequency
                      final double fontSize = 12.0 + (ratio * 20.0);
                      
                      final String word = wordData['word'] ?? '';
                      final color = _cloudColors[i % _cloudColors.length];
                      
                      final Widget wordText = Text(
                        word,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: ratio > 0.5 ? FontWeight.w800 : FontWeight.w600,
                          color: color,
                          height: 1.1,
                          letterSpacing: -0.2,
                          shadows: [
                            Shadow(color: Colors.black.withValues(alpha: 0.3), offset: const Offset(0, 1), blurRadius: 2),
                          ],
                        ),
                      );

                      // Rotate roughly every 4th word for a dynamic look
                      if (i % 4 == 0 && i != 0) {
                        return RotatedBox(
                          quarterTurns: 3,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: wordText,
                          ),
                        );
                      }
                      return wordText;
                    }),
                  ),
                ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // _buildDrawerItem() removed — drawer is now managed by MainScaffold.
}
