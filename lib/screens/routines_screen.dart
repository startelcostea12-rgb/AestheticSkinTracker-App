import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/app_prefs.dart';
import 'product_lookup_screen.dart';
import 'routine_editor_screen.dart';
import '../widgets/from_your_logs.dart';
import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';

class RoutinesScreen extends StatefulWidget {
  const RoutinesScreen({super.key});

  @override
  State<RoutinesScreen> createState() => _RoutinesScreenState();
}

class _RoutinesScreenState extends State<RoutinesScreen> {
  Map<String, dynamic>? _routine;
  Map<String, dynamic> _completion = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRoutineState();
  }

  Future<void> _loadRoutineState() async {
    final routine = await AppPrefs.getActiveAiRoutine();
    final completion = await AppPrefs.getActiveAiRoutineCompletion();
    if (!mounted) return;
    setState(() {
      _routine = routine;
      _completion = completion;
      _loading = false;
    });
  }

  String get _todayKey {
    final now = DateTime.now();
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    return '${now.year}-$mm-$dd';
  }

  bool _isChecked(String period, int index) {
    final dayMap = _completion[_todayKey];
    if (dayMap is! Map) return false;
    final periodMap = dayMap[period];
    if (periodMap is! Map) return false;
    return periodMap[index.toString()] == true;
  }

  Future<void> _toggleCheck(String period, int index, bool value) async {
    final updated = Map<String, dynamic>.from(_completion);
    final dayMap = Map<String, dynamic>.from(
      (updated[_todayKey] as Map?)?.cast<String, dynamic>() ?? {},
    );
    final periodMap = Map<String, dynamic>.from(
      (dayMap[period] as Map?)?.cast<String, dynamic>() ?? {},
    );
    periodMap[index.toString()] = value;
    dayMap[period] = periodMap;
    updated[_todayKey] = dayMap;
    await AppPrefs.saveActiveAiRoutineCompletion(updated);
    if (!mounted) return;
    setState(() => _completion = updated);
  }

  Future<void> _editRoutine() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RoutineEditorScreen(initialRoutine: _routine),
      ),
    );
    await _loadRoutineState();
  }

  Future<void> _openProductLookup() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProductLookupScreen()),
    );
    // A product may have been added to the routine.
    await _loadRoutineState();
  }

  Future<void> _openSkinScan() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SkinAiAnalysisScreen()),
    );
    await _loadRoutineState();
  }

  List<String> _stepsFor(String key) {
    final list = _routine?[key];
    if (list is! List) return const [];
    return list
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final morningSteps = _stepsFor('morningSteps');
    final eveningSteps = _stepsFor('eveningSteps');

    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      appBar: AppBar(
        backgroundColor: AppColors.warmAlabaster,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Routines',
          style: TextStyle(
            color: AppColors.refinedSlate,
            fontWeight: FontWeight.w900,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.refinedSlate),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadRoutineState,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _buildActionCard(),
                  const SizedBox(height: 14),
                  if (morningSteps.isEmpty && eveningSteps.isEmpty)
                    _buildEmptyState()
                  else ...[
                    FromYourLogsSection(
                      key: ValueKey(_routine?['generatedAt']),
                      relevantTo: [
                        ...morningSteps,
                        ...eveningSteps,
                        ..._stepsFor('detectedProducts'),
                      ],
                      margin: const EdgeInsets.only(bottom: 12),
                    ),
                    _RoutineChecklistCard(
                      title: 'Morning Routine',
                      icon: Icons.wb_sunny_outlined,
                      steps: morningSteps,
                      isChecked: (idx) => _isChecked('morning', idx),
                      onChanged: (idx, value) =>
                          _toggleCheck('morning', idx, value),
                    ),
                    const SizedBox(height: 12),
                    _RoutineChecklistCard(
                      title: 'Evening Routine',
                      icon: Icons.nights_stay_outlined,
                      steps: eveningSteps,
                      isChecked: (idx) => _isChecked('evening', idx),
                      onChanged: (idx, value) =>
                          _toggleCheck('evening', idx, value),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildActionCard() {
    final generatedAt = _routine?['generatedAt']?.toString();
    final generatedText = generatedAt == null || generatedAt.isEmpty
        ? 'No AI-generated routine saved yet.'
      : 'Updated from Skin Scan on ${generatedAt.split('T').first}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF7A8B7B).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Active AI Routine',
            style: TextStyle(
              color: AppColors.refinedSlate,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            generatedText,
            style: TextStyle(
              color: AppColors.refinedSlate.withValues(alpha: 0.72),
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('routines_edit_button'),
            onPressed: _editRoutine,
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('Edit routine'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('routines_product_lookup_button'),
            onPressed: _openProductLookup,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Scan or search a product'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _openSkinScan,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Refresh from Skin Scan'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF7A8B7B),
              side: const BorderSide(color: Color(0xFF7A8B7B), width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borders),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No active routine yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.refinedSlate,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Generate a morning and evening routine from Skin Scan, then return here to track completion.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: AppColors.refinedSlate.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _openSkinScan,
            icon: const Icon(Icons.psychology_alt_rounded),
            label: const Text('Open Skin Scan'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7A8B7B),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutineChecklistCard extends StatelessWidget {
  const _RoutineChecklistCard({
    required this.title,
    required this.icon,
    required this.steps,
    required this.isChecked,
    required this.onChanged,
  });

  final String title;
  final IconData icon;
  final List<String> steps;
  final bool Function(int index) isChecked;
  final Future<void> Function(int index, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borders),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF7A8B7B)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.refinedSlate,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < steps.length; i++)
            CheckboxListTile(
              dense: true,
              value: isChecked(i),
              onChanged: (value) {
                if (value == null) return;
                onChanged(i, value);
              },
              activeColor: const Color(0xFF7A8B7B),
              checkColor: Colors.white,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                steps[i],
                style: const TextStyle(
                  fontSize: 12.8,
                  fontWeight: FontWeight.w600,
                  color: AppColors.refinedSlate,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
