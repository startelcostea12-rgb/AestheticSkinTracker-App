import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';
import '../models/procedure.dart';
import '../utils/app_prefs.dart';
import 'glow_up_challenge_screen.dart';
import 'year_end_challenge_screen.dart';

class ChallengesScreen extends StatefulWidget {
  const ChallengesScreen({super.key});

  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends State<ChallengesScreen> {
  static const String _glowUpProcIdKey = 'challenge_glow_up_proc_id';
  static const String _yearEndProcIdKey = 'challenge_yearend_proc_id';

  List<Procedure> _procedures = const [];
  Procedure? _glowUpProcedure;
  Procedure? _yearEndProcedure;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raw = await AppPrefs.getProcedureEntries();
    final procs =
        raw
            .map((e) => Procedure.fromJson(Map<String, dynamic>.from(e)))
            .toList()
          ..sort((a, b) => b.startDate.compareTo(a.startDate));
    final prefs = await SharedPreferences.getInstance();
    final glowId = prefs.getString(_glowUpProcIdKey);
    final yearId = prefs.getString(_yearEndProcIdKey);
    if (!mounted) return;
    setState(() {
      _procedures = procs;
      _glowUpProcedure =
          procs.where((p) => p.id == glowId).firstOrNull ??
          (procs.isNotEmpty ? procs.first : null);
      _yearEndProcedure =
          procs.where((p) => p.id == yearId).firstOrNull ??
          (procs.isNotEmpty ? procs.first : null);
      _loading = false;
    });
  }

  Future<void> _pickProcedure({required bool isGlowUp}) async {
    if (_procedures.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Create a procedure first to link it to a challenge.'),
        ),
      );
      return;
    }
    final current = isGlowUp ? _glowUpProcedure : _yearEndProcedure;
    if (!mounted) return;
    final selected = await showModalBottomSheet<Procedure>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: MyApp.champagne,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: MyApp.textBrown.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Link a Procedure', style: MyApp.cardTitleStyle()),
            const SizedBox(height: 4),
            Text(
              'Progress photos and AI reminders will be tied to this procedure.',
              style: TextStyle(
                fontSize: 12,
                color: MyApp.textBrown.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
            ..._procedures.map((proc) {
              final isSelected = proc.id == current?.id;
              final daysSince =
                  DateTime.now().difference(proc.startDate).inDays + 1;
              return GestureDetector(
                onTap: () => Navigator.of(ctx).pop(proc),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: isSelected
                        ? MyApp.roseGold.withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.7),
                    border: Border.all(
                      color: isSelected
                          ? MyApp.roseGold
                          : MyApp.roseGold.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              proc.type,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: MyApp.textBrown,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Day $daysSince · ${proc.isCompleted ? "Completed" : "Active"}',
                              style: TextStyle(
                                fontSize: 12,
                                color: MyApp.textBrown.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(
                          Icons.check_circle,
                          color: MyApp.roseGold,
                          size: 20,
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
    if (selected == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (isGlowUp) {
      await prefs.setString(_glowUpProcIdKey, selected.id);
      if (!mounted) return;
      setState(() => _glowUpProcedure = selected);
    } else {
      await prefs.setString(_yearEndProcIdKey, selected.id);
      if (!mounted) return;
      setState(() => _yearEndProcedure = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final textColor = MyApp.textBrown;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: MyApp.champagne,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('Premium Challenges', style: MyApp.pageTitleStyle()),
          centerTitle: true,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(120),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.06)
                    .copyWith(
                      boxShadow: [
                        BoxShadow(
                          color: MyApp.roseGold.withValues(alpha: 0.08),
                          blurRadius: 18,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Challenges are linked to your procedures — personalised AI milestones, baseline photos, and clinical photo reminders.',
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.74),
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.86),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: MyApp.roseGold.withValues(alpha: 0.16),
                        ),
                      ),
                      child: TabBar(
                        dividerColor: Colors.transparent,
                        tabs: const [
                          Tab(text: '30-Day Glow Up'),
                          Tab(text: 'Year-End Transformation'),
                        ],
                        indicator: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [MyApp.roseGold, MyApp.goldShimmer],
                          ),
                          borderRadius: const BorderRadius.all(
                            Radius.circular(14),
                          ),
                        ),
                        labelColor: Colors.white,
                        unselectedLabelColor: textColor.withValues(alpha: 0.68),
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                MyApp.champagne,
                MyApp.roseGold.withValues(alpha: 0.08),
                Colors.white.withValues(alpha: 0.95),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: TabBarView(
            children: [
              GlowUpChallengeScreen(
                key: ValueKey('glow_${_glowUpProcedure?.id}'),
                procedure: _glowUpProcedure,
                procedures: _procedures,
                onChangeProcedure: () => _pickProcedure(isGlowUp: true),
              ),
              YearEndChallengeScreen(
                key: ValueKey('yearend_${_yearEndProcedure?.id}'),
                procedure: _yearEndProcedure,
                procedures: _procedures,
                onChangeProcedure: () => _pickProcedure(isGlowUp: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
