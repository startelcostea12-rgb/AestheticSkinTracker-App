import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';
import '../models/procedure.dart';
import '../utils/app_prefs.dart';
import '../utils/procedure_intelligence.dart';
import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import '../screens/ai_recovery_coach_screen.dart';
import '../screens/procedure_camera_guide_screen.dart';

class YearEndChallengeScreen extends StatefulWidget {
  const YearEndChallengeScreen({
    super.key,
    this.procedure,
    this.procedures = const [],
    required this.onChangeProcedure,
  });

  final Procedure? procedure;
  final List<Procedure> procedures;
  final VoidCallback onChangeProcedure;

  @override
  State<YearEndChallengeScreen> createState() => _YearEndChallengeScreenState();
}

class _Milestone {
  final String title;
  final String description;
  final String prompt;
  const _Milestone({
    required this.title,
    required this.description,
    required this.prompt,
  });
}

class _YearEndChallengeScreenState extends State<YearEndChallengeScreen> {
  int _currentMilestone = 0;
  List<_Milestone> _milestones = [];
  List<String?> _photos = [];
  List<String?> _reflections = [];
  bool _completed = false;
  bool _loading = true;
  Uint8List? _baselinePhotoBytes;

  // ── persistence keys scoped per procedure ───────────────────────────────────
  String get _keyPrefix => 'yearend_${widget.procedure?.id ?? "global"}';

  // ── build milestones from ProcedureIntelligence or defaults ─────────────────────
  List<_Milestone> _buildMilestones() {
    final proc = widget.procedure;
    if (proc != null) {
      final templates = ProcedureIntelligence.forType(
        proc.type,
      ).milestoneTemplates;
      if (templates.isNotEmpty) {
        // Pick up to 5 key checkpoints spread across the timeline
        final count = templates.length;
        final indices = {0};
        if (count > 4) {
          indices.add((count * 0.25).round().clamp(0, count - 1));
          indices.add((count * 0.50).round().clamp(0, count - 1));
          indices.add((count * 0.75).round().clamp(0, count - 1));
        } else if (count > 2) {
          indices.add((count ~/ 2).clamp(0, count - 1));
        }
        indices.add(count - 1);
        final sorted = indices.toList()..sort();
        return sorted
            .map(
              (i) => _Milestone(
                title: templates[i].label,
                description:
                    '${proc.type} day ${templates[i].offsetDays} checkpoint',
                prompt: templates[i].description,
              ),
            )
            .toList();
      }
    }
    return [
      const _Milestone(
        title: 'Baseline Photo',
        description: 'Document your starting point with a clear before photo.',
        prompt: 'What are your transformation goals for this year?',
      ),
      const _Milestone(
        title: 'Midpoint Check-In',
        description: 'Reflect on progress and upload a comparison photo.',
        prompt: 'What visible or felt changes have you noticed so far?',
      ),
      const _Milestone(
        title: 'Final Reveal',
        description:
            'Celebrate your transformation with a polished after photo.',
        prompt: 'How do you feel about your complete journey?',
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _milestones = _buildMilestones();
    _photos = List.filled(_milestones.length, null);
    _reflections = List.filled(_milestones.length, null);
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadProgress(), _loadBaselinePhoto()]);
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
          setState(() {
            _baselinePhotoBytes = base64Decode(parts[1]);
            // Pre-fill first milestone photo with baseline
            if (_photos.isNotEmpty && _photos[0] == null) {
              _photos[0] = path;
            }
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final n = _milestones.length;
      final photosRaw = prefs.getStringList('${_keyPrefix}_photos');
      final reflsRaw = prefs.getStringList('${_keyPrefix}_reflections');
      if (!mounted) return;
      setState(() {
        if (photosRaw != null) {
          _photos = List.generate(n, (i) {
            final v = i < photosRaw.length ? photosRaw[i] : '';
            return v.isEmpty ? null : v;
          });
        }
        if (reflsRaw != null) {
          _reflections = List.generate(n, (i) {
            final v = i < reflsRaw.length ? reflsRaw[i] : '';
            return v.isEmpty ? null : v;
          });
        }
        _completed = prefs.getBool('${_keyPrefix}_completed') ?? false;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      '${_keyPrefix}_photos',
      _photos.map((e) => e ?? '').toList(),
    );
    await prefs.setStringList(
      '${_keyPrefix}_reflections',
      _reflections.map((e) => e ?? '').toList(),
    );
    await prefs.setBool('${_keyPrefix}_completed', _completed);
  }

  void _uploadPhoto(int idx) async {
    final proc = widget.procedure;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => proc != null
            ? (kIsWeb
                  ? CameraScreen(
                      procedure: proc,
                      capturePurpose: CameraCapturePurpose.trackProcedure,
                    )
                  : ProcedureCameraGuideScreen(procedure: proc))
            : const CameraScreen(
                isSkincareScan: false,
                capturePurpose: CameraCapturePurpose.challenge,
              ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _photos[idx] = 'photo_captured_$idx';
    });
    _saveProgress();
  }

  void _saveReflection(int idx, String value) {
    setState(() {
      _reflections[idx] = value;
    });
    _saveProgress();
  }

  void _completeMilestone(int idx) {
    if (_photos[idx] != null &&
        _reflections[idx] != null &&
        _reflections[idx]!.isNotEmpty) {
      setState(() {
        if (idx < 2) {
          _currentMilestone = idx + 1;
        } else {
          _completed = true;
        }
      });
      _saveProgress();
      _showCelebration(
        idx == 2 ? 'Transformation Complete! 🎉' : 'Milestone Complete!',
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload a photo and write a reflection.'),
        ),
      );
    }
  }

  void _showCelebration(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Congratulations!'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _shareSummary() {
    // Implement share logic or integrate with your share card system
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Shareable summary coming soon!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final completedMilestones =
        List<int>.generate(_milestones.length, (index) => index)
            .where(
              (index) =>
                  _photos[index] != null &&
                  (_reflections[index]?.isNotEmpty ?? false),
            )
            .length;

    return Scaffold(
      backgroundColor: MyApp.champagne,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.procedure != null
              ? 'Year-End – ${widget.procedure!.type}'
              : 'Year-End Transformation',
          style: MyApp.pageTitleStyle(),
        ),
        centerTitle: true,
      ),
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
                      MyApp.goldShimmer.withValues(alpha: 0.06),
                      Colors.white.withValues(alpha: 0.97),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -110,
              left: -80,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MyApp.roseGold.withValues(alpha: 0.07),
                ),
              ),
            ),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              ListView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
                children: [
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
                            _statusPill(
                              Icons.verified_outlined,
                              'Transformation archive',
                            ),
                            _statusPill(
                              Icons.photo_library_outlined,
                              '$completedMilestones of ${_milestones.length} milestones documented',
                            ),
                            _statusPill(
                              Icons.lock_outline,
                              'Private reflection flow',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Reflect, document, and close the year with a polished record of progress.',
                          style: MyApp.sectionTitleStyle().copyWith(
                            fontSize: 24,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'This guided review turns your before-and-after journey into a structured transformation story you can revisit or share.',
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
                  // ── Procedure header + baseline ─────────────────────────────────────────
                  _buildProcedureHeader(),
                  Container(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Milestone Timeline',
                                style: MyApp.cardTitleStyle(),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _completed
                                    ? 'Your transformation story is complete and ready for review.'
                                    : 'You are currently focused on ${_milestones[_currentMilestone].title.toLowerCase()}.',
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
                        SizedBox(
                          width: 86,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 72,
                                height: 72,
                                child: CircularProgressIndicator(
                                  value:
                                      completedMilestones / _milestones.length,
                                  strokeWidth: 8,
                                  backgroundColor: MyApp.roseGold.withValues(
                                    alpha: 0.14,
                                  ),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    MyApp.goldShimmer,
                                  ),
                                ),
                              ),
                              Text(
                                '$completedMilestones/${_milestones.length}',
                                style: TextStyle(
                                  color: MyApp.textBrown,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.06)
                        .copyWith(
                          border: Border.all(
                            color: MyApp.roseGold.withValues(alpha: 0.18),
                          ),
                        ),
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Transformation Brief',
                          style: MyApp.cardTitleStyle(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _completed
                              ? 'Your archive is complete. Review your photos, refine your reflection language, and share a polished summary when ready.'
                              : 'Keep each milestone concise and honest. Strong before-and-after documentation depends on one clear photo and one meaningful reflection per stage.',
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
                  for (var index = 0; index < _milestones.length; index++) ...[
                    _luxuryMilestoneCard(index),
                    if (index != _milestones.length - 1)
                      const SizedBox(height: 16),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _shareSummary,
                    icon: const Icon(Icons.summarize_outlined),
                    label: Text(
                      _completed
                          ? 'Share Transformation Summary'
                          : 'Preview Summary',
                    ),
                    style: MyApp.primaryGoldButton,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            AIRecoveryCoachScreen(procedure: widget.procedure),
                      ),
                    ),
                    icon: const Icon(Icons.psychology_alt_outlined),
                    label: const Text('Open AI Recovery Coach'),
                    style: MyApp.secondaryOutlineButton(accent: MyApp.roseGold),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // Luxury milestone card widget
  Widget _buildProcedureHeader() {
    final proc = widget.procedure;
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
                : Icon(
                    Icons.photo_camera_outlined,
                    color: MyApp.roseGold,
                    size: 26,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  proc != null ? proc.type : 'No procedure linked',
                  style: MyApp.cardTitleStyle(),
                ),
                const SizedBox(height: 2),
                Text(
                  _baselinePhotoBytes != null
                      ? 'Baseline auto-filled from procedure photos'
                      : proc != null
                      ? 'Link procedure to auto-fill baseline photo'
                      : 'Link a procedure for personalised milestones',
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

  Widget _statusPill(IconData icon, String label) {
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

  Widget _luxuryMilestoneCard(int index) {
    final milestone = _milestones[index];
    final hasPhoto = _photos[index] != null;
    final hasReflection = (_reflections[index]?.isNotEmpty ?? false);
    final isDone = hasPhoto && hasReflection;
    final isActive = !_completed && index == _currentMilestone;

    return Container(
      decoration:
          MyApp.surfaceCardDecoration(
            tintOpacity: isActive ? 0.10 : 0.05,
          ).copyWith(
            border: Border.all(
              color: (isDone ? MyApp.goldShimmer : MyApp.roseGold).withValues(
                alpha: isActive ? 0.34 : 0.22,
              ),
              width: isActive ? 1.3 : 1,
            ),
          ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: LinearGradient(
                    colors: [
                      MyApp.roseGold.withValues(alpha: 0.95),
                      MyApp.goldShimmer.withValues(alpha: 0.85),
                    ],
                  ),
                ),
                child: Icon(
                  index == 1 ? Icons.edit_outlined : Icons.camera_alt_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(milestone.title, style: MyApp.cardTitleStyle()),
                    const SizedBox(height: 4),
                    Text(
                      milestone.description,
                      style: TextStyle(
                        color: MyApp.textBrown.withValues(alpha: 0.72),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: (isDone ? MyApp.goldShimmer : MyApp.roseGold)
                      .withValues(alpha: 0.14),
                ),
                child: Text(
                  isDone
                      ? 'Complete'
                      : isActive
                      ? 'Active'
                      : 'Upcoming',
                  style: TextStyle(
                    color: MyApp.textBrown,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withValues(alpha: 0.72),
              border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.16)),
            ),
            child: Text(
              milestone.prompt,
              style: TextStyle(
                color: MyApp.textBrown.withValues(alpha: 0.74),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _milestoneStatusTile(
                  label: 'Photo',
                  value: hasPhoto ? 'Uploaded' : 'Needed',
                  completed: hasPhoto,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _milestoneStatusTile(
                  label: 'Reflection',
                  value: hasReflection ? 'Saved' : 'Needed',
                  completed: hasReflection,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextFormField(
            initialValue: _reflections[index] ?? '',
            onChanged: (value) => _saveReflection(index, value),
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Write your reflection...',
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.85),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: MyApp.roseGold.withValues(alpha: 0.18),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: MyApp.roseGold.withValues(alpha: 0.18),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _uploadPhoto(index),
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(hasPhoto ? 'Replace Photo' : 'Upload Photo'),
                  style: MyApp.secondaryOutlineButton(accent: MyApp.roseGold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _completeMilestone(index),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(isDone ? 'Review' : 'Complete'),
                  style: MyApp.primaryRoseButton,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _milestoneStatusTile({
    required String label,
    required String value,
    required bool completed,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: completed
            ? MyApp.goldShimmer.withValues(alpha: 0.14)
            : MyApp.roseGold.withValues(alpha: 0.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: MyApp.textBrown.withValues(alpha: 0.65),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: MyApp.textBrown,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
