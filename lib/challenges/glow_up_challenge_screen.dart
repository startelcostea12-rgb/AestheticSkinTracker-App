import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';
import '../models/procedure.dart';
import '../utils/app_prefs.dart';
import '../utils/procedure_intelligence.dart';
import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import '../screens/ai_recovery_coach_screen.dart';
import '../screens/progress_report_screen.dart';

// Top-level widgets and helpers for GlowUpChallengeScreen
class ProgressRing extends StatelessWidget {
  final double percent;
  final int day;
  final int totalDays;
  const ProgressRing({
    required this.percent,
    required this.day,
    required this.totalDays,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              colors: [Color(0xFFB76E79), Color(0xFFE8A8B5), Color(0xFFE0C070)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(rect),
            child: CircularProgressIndicator(
              value: percent,
              strokeWidth: 8,
              backgroundColor: const Color(0xFFF8E1E7),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Day',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              Text(
                '$day',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFB76E79),
                ),
              ),
              Text(
                '/$totalDays',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class StreakFireCounter extends StatelessWidget {
  final int streak;
  const StreakFireCounter({required this.streak, super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 1.0, end: 1.0 + streak * 0.05),
          duration: const Duration(milliseconds: 600),
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: const Icon(
            Icons.local_fire_department,
            color: Color(0xFFB76E79),
            size: 32,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$streak',
          style: const TextStyle(
            fontSize: 18,
            color: Color(0xFFB76E79),
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class BadgeRow extends StatelessWidget {
  final List<String> badges;
  const BadgeRow({required this.badges, super.key});

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) {
      return const Text(
        'No badges yet. Keep going! 🌱',
        style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
      );
    }
    return Row(
      children: badges
          .map(
            (badge) => AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              curve: Curves.elasticOut,
              margin: const EdgeInsets.only(right: 8),
              child: Chip(
                label: Text(
                  badge,
                  style: const TextStyle(
                    color: Color(0xFFB76E79),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor: const Color(0xFFF8E1E7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class AchievementRow extends StatelessWidget {
  final List<String> achievements;
  const AchievementRow({required this.achievements, super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: achievements
          .map(
            (ach) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Chip(
                label: Text(
                  ach,
                  style: const TextStyle(
                    color: Color(0xFFB76E79),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor: const Color(0xFFE0C070),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class ChecklistRow extends StatelessWidget {
  final int day;
  final Map<String, bool> checklist;
  final VoidCallback onScan;
  final VoidCallback onSkincare;
  final VoidCallback onJournal;
  final VoidCallback onAICoach;
  const ChecklistRow({
    required this.day,
    required this.checklist,
    required this.onScan,
    required this.onSkincare,
    required this.onJournal,
    required this.onAICoach,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Checkbox(value: checklist['Scan'], onChanged: (_) => onScan()),
            const Text('Scan'),
            const SizedBox(width: 12),
            Checkbox(
              value: checklist['Skincare Log'],
              onChanged: (_) => onSkincare(),
            ),
            const Text('Skincare Log'),
          ],
        ),
        Row(
          children: [
            Checkbox(
              value: checklist['Journal'],
              onChanged: (_) => onJournal(),
            ),
            const Text('Journal'),
            const SizedBox(width: 12),
            Checkbox(
              value: checklist['AI Coach'],
              onChanged: (_) => onAICoach(),
            ),
            const Text('AI Coach'),
          ],
        ),
      ],
    );
  }
}

class ProgressDashboard extends StatelessWidget {
  final int completed;
  final int total;
  const ProgressDashboard({
    required this.completed,
    required this.total,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFF8E1E7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Completed: $completed/$total',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFFB76E79),
              ),
            ),
            LinearProgressIndicator(
              value: completed / total,
              backgroundColor: Colors.white,
              color: const Color(0xFFB76E79),
              minHeight: 8,
            ),
          ],
        ),
      ),
    );
  }
}

// ...existing code...

class ConfettiPainter extends CustomPainter {
  final double progress;
  ConfettiPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      const Color(0xFFB76E79),
      const Color(0xFFE8A8B5),
      const Color(0xFFFCE8EF),
      const Color(0xFFE0C070),
    ];
    for (int i = 0; i < 32; i++) {
      final angle = 2 * math.pi * i / 32 + progress * 2 * math.pi;
      final radius = 80 + 60 * progress;
      final x = size.width / 2 + radius * math.cos(angle);
      final y = size.height / 2 + radius * math.sin(angle);
      final paint = Paint()
        ..color = colors[i % colors.length].withValues(
          alpha: 1 - progress * 0.5,
        );
      canvas.drawCircle(Offset(x, y), 6 - 3 * progress, paint);
    }
  }

  @override
  bool shouldRepaint(ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class GlowUpChallengeScreen extends StatefulWidget {
  const GlowUpChallengeScreen({
    super.key,
    this.procedure,
    this.procedures = const [],
    required this.onChangeProcedure,
  });

  final Procedure? procedure;
  final List<Procedure> procedures;
  final VoidCallback onChangeProcedure;

  @override
  State<GlowUpChallengeScreen> createState() => _GlowUpChallengeScreenState();
}

class _GlowUpChallengeScreenState extends State<GlowUpChallengeScreen>
    with SingleTickerProviderStateMixin {
  final int totalDays = 30;
  int currentDay = 1;
  int streak = 0;
  List<bool> completedDays = List.generate(30, (_) => false);
  List<String> badges = [];
  List<String> achievements = [];
  String aiTip = 'Stay hydrated and smile today!';
  bool _stateLoaded = false;
  Uint8List? _baselinePhotoBytes;
  List<Map<String, bool>> dailyChecklist = List.generate(
    30,
    (_) => {
      'Scan': false,
      'Skincare Log': false,
      'Journal': false,
      'AI Coach': false,
      'Hydration': false,
    },
  );
  late AnimationController _celebrationController;
  late Animation<double> _celebrationAnim;

  // ── persistence keys (scoped per procedure) ────────────────────────────────
  String get _keyPrefix => 'glow_${widget.procedure?.id ?? "global"}';
  String get _completedDaysKey => '${_keyPrefix}_completed_days';
  String get _streakKey => '${_keyPrefix}_streak';
  String get _currentDayKey => '${_keyPrefix}_current_day';
  String get _badgesKey => '${_keyPrefix}_badges';
  String get _achievementsKey => '${_keyPrefix}_achievements';
  String get _checklistKey => '${_keyPrefix}_checklist';

  @override
  void initState() {
    super.initState();
    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _celebrationAnim = CurvedAnimation(
      parent: _celebrationController,
      curve: Curves.easeOutBack,
    );
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadPersistedState(), _loadBaselinePhoto()]);
    if (mounted) setState(() => _stateLoaded = true);
  }

  Future<void> _loadPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    final completedJson = prefs.getString(_completedDaysKey);
    final badgesJson = prefs.getString(_badgesKey);
    final achievementsJson = prefs.getString(_achievementsKey);
    final checklistJson = prefs.getString(_checklistKey);
    if (!mounted) return;
    setState(() {
      if (completedJson != null) {
        final list = (jsonDecode(completedJson) as List).cast<bool>();
        completedDays = list.length == 30
            ? list
            : List.generate(30, (i) => i < list.length ? list[i] : false);
      }
      streak = prefs.getInt(_streakKey) ?? 0;
      currentDay = prefs.getInt(_currentDayKey) ?? 1;
      if (badgesJson != null) {
        badges = (jsonDecode(badgesJson) as List).cast<String>();
      }
      if (achievementsJson != null) {
        achievements = (jsonDecode(achievementsJson) as List).cast<String>();
      }
      if (checklistJson != null) {
        final raw = (jsonDecode(checklistJson) as List);
        dailyChecklist = List.generate(30, (i) {
          if (i < raw.length && raw[i] is Map) {
            return Map<String, bool>.from(
              (raw[i] as Map).map((k, v) => MapEntry(k as String, v as bool)),
            );
          }
          return {
            'Scan': false,
            'Skincare Log': false,
            'Journal': false,
            'AI Coach': false,
            'Hydration': false,
          };
        });
      }
    });
  }

  Future<void> _savePersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_completedDaysKey, jsonEncode(completedDays));
    await prefs.setInt(_streakKey, streak);
    await prefs.setInt(_currentDayKey, currentDay);
    await prefs.setString(_badgesKey, jsonEncode(badges));
    await prefs.setString(_achievementsKey, jsonEncode(achievements));
    await prefs.setString(_checklistKey, jsonEncode(dailyChecklist));
  }

  Future<void> _loadBaselinePhoto() async {
    final proc = widget.procedure;
    if (proc == null) return;
    try {
      final comparison = await AppPrefs.getProcedurePhotoComparison(proc.id);
      final path = comparison['baselineImagePath'];
      if (path != null && path.startsWith('data:image')) {
        final parts = path.split(',');
        if (parts.length > 1 && mounted) {
          setState(() => _baselinePhotoBytes = base64Decode(parts[1]));
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _celebrationController.dispose();
    super.dispose();
  }

  void completeChecklistItem(int day, String item) {
    setState(() {
      dailyChecklist[day][item] = true;
      if (dailyChecklist[day].values.every((v) => v)) {
        completedDays[day] = true;
        streak = _calculateStreak();
        currentDay = day + 2;
        _checkBadges();
        _showCelebration(
          'Day ${day + 1} Complete! You\'re glowing brighter every day.',
        );
      }
    });
    _savePersistedState();
  }

  void _checkBadges() {
    if (streak == 3 && !badges.contains('3-Day Glow')) {
      badges.add('3-Day Glow');
      _showCelebration('3-Day Glow! You\'re on a roll!');
    }
    if (streak == 7 && !badges.contains('7-Day Streak')) {
      badges.add('7-Day Streak');
      _showCelebration('7-Day Streak! Consistency Queen!');
    }
    if (streak == 14 && !badges.contains('14-Day Streak')) {
      badges.add('14-Day Streak');
      _showCelebration('14-Day Streak! You\'re unstoppable!');
    }
    if (streak == 21 && !badges.contains('21-Day Habit')) {
      badges.add('21-Day Habit');
      _showCelebration('21-Day Habit! You\'ve built a beautiful routine!');
    }
    if (streak == 30 && !badges.contains('30-Day Glow Up')) {
      badges.add('30-Day Glow Up');
      achievements.add('Glow Up Champion');
      _showCelebration('30-Day Glow Up Complete! You did it! 🏆');
    }
    final done = completedDays.where((d) => d).length;
    if (done == 15 && !achievements.contains('Halfway Hero')) {
      achievements.add('Halfway Hero');
      _showCelebration('Achievement Unlocked: Halfway Hero!');
    }
    if (done == 30 && !achievements.contains('Challenge Finisher')) {
      achievements.add('Challenge Finisher');
      _showCelebration('Achievement Unlocked: Challenge Finisher!');
    }
  }

  void _showCelebration(String message) {
    _celebrationController.forward(from: 0);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) =>
          CelebrationDialog(message: message, animation: _celebrationAnim),
    );
  }

  int _calculateStreak() {
    int s = 0;
    for (int i = 0; i < completedDays.length; i++) {
      if (completedDays[i]) {
        s++;
      } else {
        s = 0;
      }
    }
    return s;
  }

  void _openCamera(BuildContext context, int day) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CameraScreen(isSkincareScan: true),
      ),
    );
    completeChecklistItem(day, 'Scan');
    _updateAITip(day);
  }

  void _openAICoach(BuildContext context, int day) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AIRecoveryCoachScreen()));
    completeChecklistItem(day, 'AI Coach');
    _updateAITip(day);
  }

  void _updateAITip(int day) {
    final tips = [
      "✨ Take a mindful moment—breathe and smile at yourself in the mirror.",
      "🌹 Hydrate with a glass of water before your skincare routine.",
      "💎 Write one thing you love about your skin today.",
      "🌟 Try a gentle facial massage for 2 minutes.",
      "👑 Celebrate a small win—share it in your journal.",
      "🌸 Take a progress selfie and notice your glow!",
      "🦋 Reflect on how you feel after today’s routine.",
      "🔥 Encourage a friend to join your glow up journey.",
      "🚀 Set a mini-goal for tomorrow’s self-care.",
      "💖 Treat yourself to a calming playlist tonight.",
    ];
    setState(() {
      aiTip = tips[day % tips.length];
    });
  }

  void _openReport(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ProgressReportScreen()));
  }

  @override
  Widget build(BuildContext context) {
    if (!_stateLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final completedCount = completedDays.where((done) => done).length;
    final progress = totalDays == 0 ? 0.0 : completedCount / totalDays;
    final safeCurrentDay = currentDay.clamp(1, totalDays);
    final todaysChecklist = dailyChecklist[safeCurrentDay - 1];

    return Scaffold(
      backgroundColor: MyApp.champagne,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      MyApp.champagne,
                      MyApp.roseGold.withValues(alpha: 0.08),
                      Colors.white.withValues(alpha: 0.96),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -120,
              right: -70,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MyApp.goldShimmer.withValues(alpha: 0.08),
                ),
              ),
            ),
            ListView(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
              children: [
                _buildProcedureHeader(),
                _buildAiReminderCard(safeCurrentDay),
                Container(
                  decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.08)
                      .copyWith(
                        border: Border.all(
                          color: MyApp.goldShimmer.withValues(alpha: 0.24),
                        ),
                      ),
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _infoPill(
                            Icons.workspace_premium_outlined,
                            'Luxury habit reset',
                          ),
                          _infoPill(
                            Icons.auto_graph_outlined,
                            '$completedCount of $totalDays days complete',
                          ),
                          _infoPill(
                            Icons.self_improvement_outlined,
                            'Calm consistency focus',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Your glow-up routine is designed to feel refined, calm, and measurable.',
                        style: MyApp.sectionTitleStyle().copyWith(
                          fontSize: 24,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Track daily rituals, monitor streak momentum, and keep your recovery habits intentional instead of overwhelming.',
                        style: TextStyle(
                          color: MyApp.textBrown.withValues(alpha: 0.72),
                          fontSize: 14,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.06),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          ProgressRing(
                            percent: progress,
                            day: safeCurrentDay,
                            totalDays: totalDays,
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Daily Momentum',
                                  style: MyApp.cardTitleStyle(),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  completedCount == 0
                                      ? 'Start today\'s ritual to begin building visible momentum.'
                                      : 'You have completed $completedCount days and built a ${streak == 0 ? 'new' : '$streak-day'} streak.',
                                  style: TextStyle(
                                    color: MyApp.textBrown.withValues(
                                      alpha: 0.72,
                                    ),
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          StreakFireCounter(streak: streak),
                        ],
                      ),
                      const SizedBox(height: 14),
                      LinearProgressIndicator(
                        value: progress,
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(999),
                        backgroundColor: MyApp.roseGold.withValues(alpha: 0.14),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          MyApp.goldShimmer,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.05),
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ritual Concierge', style: MyApp.cardTitleStyle()),
                      const SizedBox(height: 10),
                      Text(
                        _phaseGuidance(safeCurrentDay),
                        style: TextStyle(
                          color: MyApp.textBrown.withValues(alpha: 0.74),
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (badges.isNotEmpty || achievements.isNotEmpty) ...[
                  Container(
                    decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.05),
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Recognition', style: MyApp.cardTitleStyle()),
                        const SizedBox(height: 12),
                        if (badges.isNotEmpty) _BadgeRow(badges: badges),
                        if (badges.isNotEmpty && achievements.isNotEmpty)
                          const SizedBox(height: 10),
                        if (achievements.isNotEmpty)
                          _AchievementRow(achievements: achievements),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                Text('Today\'s Checklist', style: MyApp.sectionTitleStyle()),
                const SizedBox(height: 10),
                _luxuryChecklistCard(
                  label: 'Scan',
                  detail: widget.procedure != null
                      ? 'Capture a photo for your ${widget.procedure!.type} tracking — saved automatically to your procedure.'
                      : 'Capture a current skin snapshot for objective tracking.',
                  completed: todaysChecklist['Scan'] ?? false,
                  icon: Icons.camera_alt_outlined,
                  onTap: () => _openCamera(context, safeCurrentDay - 1),
                ),
                _luxuryChecklistCard(
                  label: 'Skincare Log',
                  detail: 'Confirm the regimen you completed today.',
                  completed: todaysChecklist['Skincare Log'] ?? false,
                  icon: Icons.spa_outlined,
                  onTap: () =>
                      completeChecklistItem(safeCurrentDay - 1, 'Skincare Log'),
                ),
                _luxuryChecklistCard(
                  label: 'Journal',
                  detail: 'Record how your skin and energy felt today.',
                  completed: todaysChecklist['Journal'] ?? false,
                  icon: Icons.edit_note_outlined,
                  onTap: () =>
                      completeChecklistItem(safeCurrentDay - 1, 'Journal'),
                ),
                _luxuryChecklistCard(
                  label: 'AI Coach Check-in',
                  detail: widget.procedure != null
                      ? 'Get ${widget.procedure!.type}-specific guidance from your AI recovery coach.'
                      : 'Ask for a calm recommendation or reassurance.',
                  completed: todaysChecklist['AI Coach'] ?? false,
                  icon: Icons.psychology_alt_outlined,
                  onTap: () => _openAICoach(context, safeCurrentDay - 1),
                ),
                _luxuryChecklistCard(
                  label: 'Hydration',
                  detail: 'Support skin recovery with a hydration check.',
                  completed: todaysChecklist['Hydration'] ?? false,
                  icon: Icons.water_drop_outlined,
                  onTap: () =>
                      completeChecklistItem(safeCurrentDay - 1, 'Hydration'),
                ),
                const SizedBox(height: 18),
                Container(
                  decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.10)
                      .copyWith(
                        border: Border.all(
                          color: MyApp.goldShimmer.withValues(alpha: 0.22),
                        ),
                      ),
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            colors: [
                              MyApp.roseGold.withValues(alpha: 0.95),
                              MyApp.goldShimmer.withValues(alpha: 0.85),
                            ],
                          ),
                        ),
                        child: const Icon(
                          Icons.lightbulb_outline,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AI Recovery Tip',
                              style: MyApp.cardTitleStyle(),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              aiTip,
                              style: TextStyle(
                                color: MyApp.textBrown.withValues(alpha: 0.74),
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: () => _openReport(context),
                  icon: const Icon(Icons.summarize_outlined),
                  label: const Text('Open Progress Report'),
                  style: MyApp.primaryGoldButton,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Luxury checklist card widget
  Widget _buildProcedureHeader() {
    final proc = widget.procedure;
    final daysSince = proc != null
        ? (DateTime.now().difference(proc.startDate).inDays + 1).clamp(1, 9999)
        : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.08).copyWith(
        border: Border.all(
          color: MyApp.roseGold.withValues(alpha: 0.28),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: MyApp.roseGold.withValues(alpha: 0.12),
            ),
            clipBehavior: Clip.antiAlias,
            child: _baselinePhotoBytes != null
                ? Image.memory(_baselinePhotoBytes!, fit: BoxFit.cover)
                : Icon(Icons.person_outline, color: MyApp.roseGold, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  proc != null
                      ? '30-Day Glow Up \u2013 ${proc.type}'
                      : '30-Day Glow Up',
                  style: MyApp.cardTitleStyle(),
                ),
                const SizedBox(height: 2),
                Text(
                  proc != null
                      ? 'Day $daysSince of recovery \u00b7 ${_baselinePhotoBytes != null ? "Baseline set" : "No baseline yet"}'
                      : 'No procedure linked',
                  style: TextStyle(
                    fontSize: 12,
                    color: MyApp.textBrown.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: widget.onChangeProcedure,
            icon: Icon(
              Icons.swap_horiz_outlined,
              size: 16,
              color: MyApp.roseGold,
            ),
            label: Text(
              proc != null ? 'Change' : 'Link',
              style: TextStyle(
                fontSize: 12,
                color: MyApp.roseGold,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiReminderCard(int safeCurrentDay) {
    final proc = widget.procedure;
    if (proc == null) return const SizedBox.shrink();
    final profile = ProcedureIntelligence.forType(proc.type);
    final daysSince = DateTime.now().difference(proc.startDate).inDays + 1;
    final upcoming = profile.milestoneTemplates
        .where((m) => m.offsetDays >= daysSince - 3)
        .toList();
    if (upcoming.isEmpty) return const SizedBox.shrink();
    final next = upcoming.first;
    final daysUntil = next.offsetDays - daysSince;
    final bool isDue = daysUntil <= 0;
    final bool isSoon = daysUntil > 0 && daysUntil <= 5;
    final Color accentColor = isDue
        ? const Color(0xFF2E7D32)
        : isSoon
        ? const Color(0xFFF57F17)
        : MyApp.roseGold;
    final String urgencyLabel = isDue
        ? 'Photo checkpoint: Upload now'
        : isSoon
        ? 'Photo checkpoint in $daysUntil day${daysUntil == 1 ? "" : "s"}'
        : 'Next photo checkpoint in $daysUntil days';
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.notifications_active_outlined,
                size: 16,
                color: accentColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  urgencyLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: accentColor,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  next.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            next.description,
            style: TextStyle(
              fontSize: 12,
              color: MyApp.textBrown.withValues(alpha: 0.75),
              height: 1.4,
            ),
          ),
          if (isDue || isSoon) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openCamera(context, safeCurrentDay - 1),
                icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                label: Text(
                  isDue ? 'Upload Progress Photo Now' : 'Upload Progress Photo',
                  style: const TextStyle(fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _phaseGuidance(int day) {
    final proc = widget.procedure;
    if (proc != null) {
      final profile = ProcedureIntelligence.forType(proc.type);
      final daysSince = DateTime.now().difference(proc.startDate).inDays + 1;
      final current = profile.milestoneTemplates.lastWhere(
        (m) => m.offsetDays <= daysSince,
        orElse: () => profile.milestoneTemplates.first,
      );
      return '${current.label} — ${current.description}';
    }
    if (day <= 10) {
      return 'Early phase: focus on consistency over perfection. Capture the baseline, hydrate, and keep the routine light.';
    } else if (day <= 20) {
      return 'Middle phase: review progress patterns, tighten your journaling, and use the AI coach when motivation dips.';
    }
    return 'Finish strong: protect your streak, compare your glow-up changes, and prepare your progress report.';
  }

  Widget _infoPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.22)),
        color: Colors.white.withValues(alpha: 0.82),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: MyApp.roseGold),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: MyApp.textBrown.withValues(alpha: 0.82),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _luxuryChecklistCard({
    required String label,
    required String detail,
    required bool completed,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7),
      decoration:
          MyApp.surfaceCardDecoration(
            tintOpacity: completed ? 0.10 : 0.05,
          ).copyWith(
            border: Border.all(
              color: (completed ? MyApp.goldShimmer : MyApp.roseGold)
                  .withValues(alpha: 0.24),
            ),
          ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: completed
                ? MyApp.goldShimmer.withValues(alpha: 0.18)
                : MyApp.roseGold.withValues(alpha: 0.12),
          ),
          child: Icon(
            icon,
            color: completed ? MyApp.goldShimmer : MyApp.roseGold,
          ),
        ),
        title: Text(label, style: MyApp.cardTitleStyle()),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            detail,
            style: TextStyle(
              color: MyApp.textBrown.withValues(alpha: 0.70),
              height: 1.35,
            ),
          ),
        ),
        trailing: completed
            ? Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: MyApp.goldShimmer.withValues(alpha: 0.18),
                ),
                child: Text(
                  'Done',
                  style: TextStyle(
                    color: MyApp.textBrown,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            : ElevatedButton(
                onPressed: onTap,
                style: MyApp.secondaryOutlineButton(accent: MyApp.roseGold)
                    .copyWith(
                      minimumSize: WidgetStateProperty.all(const Size(112, 46)),
                      padding: WidgetStateProperty.all(
                        const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                child: const Text('Complete'),
              ),
        isThreeLine: true,
        onTap: completed ? null : onTap,
      ),
    );
  }
}

// Top-level widgets and helpers (BadgeRow, AchievementRow, ChecklistRow, ProgressRing, StreakFireCounter, ProgressDashboard, CelebrationDialog, ConfettiPainter)
// ...existing code for these widgets, moved to top-level...
// Celebration dialog with rose-gold confetti
class CelebrationDialog extends StatelessWidget {
  final String message;
  final Animation<double> animation;
  const CelebrationDialog({
    super.key,
    required this.message,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ScaleTransition(
        scale: animation,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size(220, 220),
              painter: _ConfettiPainter(animation.value),
            ),
            Container(
              width: 180,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB76E79).withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border.all(color: const Color(0xFFB76E79), width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.emoji_events,
                    color: Color(0xFFB76E79),
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFB76E79),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Keep going—you’re amazing!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final double progress;
  _ConfettiPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      const Color(0xFFB76E79),
      const Color(0xFFE8A8B5),
      const Color(0xFFFCE8EF),
      const Color(0xFFE0C070),
    ];
    for (int i = 0; i < 32; i++) {
      final angle = 2 * math.pi * i / 32 + progress * 2 * math.pi;
      final radius = 80 + 60 * progress;
      final x = size.width / 2 + radius * math.cos(angle);
      final y = size.height / 2 + radius * math.sin(angle);
      final paint = Paint()
        ..color = colors[i % colors.length].withValues(
          alpha: 1 - progress * 0.5,
        );
      canvas.drawCircle(Offset(x, y), 6 - 3 * progress, paint);
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}


class _BadgeRow extends StatelessWidget {
  final List<String> badges;
  const _BadgeRow({required this.badges});

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) {
      return const Text(
        'No badges yet. Keep going! 🌱',
        style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
      );
    }
    return Row(
      children: badges
          .map(
            (badge) => AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              curve: Curves.elasticOut,
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFE8A8B5),
                    Color(0xFFB76E79),
                    Color(0xFFE0C070),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB76E79).withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events, color: Colors.white, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    badge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}


class _AchievementRow extends StatelessWidget {
  final List<String> achievements;
  const _AchievementRow({required this.achievements});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: achievements
          .map(
            (ach) => AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.elasticOut,
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE0C070), Color(0xFFB76E79)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB76E79).withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.stars, color: Colors.white, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    ach,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

