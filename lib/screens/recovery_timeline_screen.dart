// lib/screens/recovery_timeline_screen.dart
//
// A focused, clean Recovery Timeline screen surfaced from the Premium
// Recovery Hub at /timeline. Replaces the older, cluttered progress report
// experience for this entry point with four primary sections only:
//
//   1. Header  – procedure name + current recovery day / stage
//   2. AI Recovery Guidance – procedure-aware milestones (primary content)
//   3. Your Notes / Journal – add / edit / delete personal recovery notes
//   4. Key Reminders – 3–5 actionable bullets
//   5. Export Report – generates the same PDF as the procedure detail page
//
// All AI content is procedure-aware via `ProcedureIntelligence` and the
// default milestone library in `RecoveryTimelineCard`.

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../widgets/clinical_section_header.dart';
import '../models/journal_entry.dart';
import '../models/premium_recovery_models.dart' show ProgressPhotoInsight;
import '../models/procedure.dart';
import '../models/scan_history.dart';
import '../utils/app_prefs.dart';
import '../utils/premium_recovery_service.dart';
import '../utils/procedure_intelligence.dart';
import '../utils/procedure_metric_set.dart';
import '../utils/report_service.dart';
import '../widgets/report_disclaimer_notice.dart';
import '../widgets/recovery_timeline_card.dart' show RecoveryTimelineCard;
import '../widgets/report_share_helper.dart' as report_share;
import 'ai_recovery_coach_screen.dart';

class RecoveryTimelineScreen extends StatefulWidget {
  const RecoveryTimelineScreen({super.key, this.procedureId});

  /// Optional pre-selected procedure id (passed via route arguments from the
  /// Recovery Hub). When null, falls back to the currently-selected
  /// procedure in [AppPrefs].
  final String? procedureId;

  @override
  State<RecoveryTimelineScreen> createState() => _RecoveryTimelineScreenState();
}

class _RecoveryTimelineScreenState extends State<RecoveryTimelineScreen> {
  bool _loading = true;
  bool _busy = false;
  Procedure? _procedure;
  List<ScanHistoryEntry> _scans = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Loading ────────────────────────────────────────────────────────────
  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final entries = await AppPrefs.getProcedureEntries();
    Procedure? resolved;

    String? targetId = widget.procedureId?.trim();
    if (targetId != null && targetId.isEmpty) targetId = null;
    targetId ??= (await AppPrefs.getSelectedProcedureIdOrNull())?.trim();
    if (targetId != null && targetId.isEmpty) targetId = null;

    if (entries.isNotEmpty) {
      if (targetId != null) {
        for (final raw in entries) {
          final id = (raw['id'] ?? raw['procedureId'] ?? '').toString().trim();
          if (id == targetId) {
            resolved = Procedure.fromJson(Map<String, dynamic>.from(raw));
            break;
          }
        }
      }
      resolved ??= Procedure.fromJson(Map<String, dynamic>.from(entries.first));
    }

    // Load scans tied to the resolved procedure (chronological) so we can
    // surface metric-aware insights against the current recovery phase.
    List<ScanHistoryEntry> scans = const [];
    final all = await AppPrefs.getScanEntries();
    if (resolved != null) {
      scans = all.where((s) {
        final procedureMatches = (s.procedureId ?? '').trim() == resolved!.id;
        return procedureMatches || _isSkinAiScan(s);
      }).toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    } else {
      scans = all.where(_isSkinAiScan).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    if (!mounted) return;
    setState(() {
      _procedure = resolved;
      _scans = scans;
      _loading = false;
    });
  }

  // ── Persistence ────────────────────────────────────────────────────────
  Future<void> _persistProcedure(Procedure updated) async {
    final all = await AppPrefs.getProcedureEntries();
    final list = all
        .map((raw) => Procedure.fromJson(Map<String, dynamic>.from(raw)))
        .toList();
    final idx = list.indexWhere((p) => p.id == updated.id);
    if (idx >= 0) {
      list[idx] = updated;
    } else {
      list.insert(0, updated);
    }
    await AppPrefs.saveProcedureHistory(list.map((p) => p.toJson()).toList());
    if (!mounted) return;
    setState(() => _procedure = updated);
  }

  // ── Journal CRUD ───────────────────────────────────────────────────────
  Future<void> _addJournalEntry() async {
    final proc = _procedure;
    if (proc == null) return;
    final result = await _openJournalEditor();
    if (result == null) return;
    final updated = proc.copyWith(
      journalEntries: [result, ...proc.journalEntries],
    );
    await _persistProcedure(updated);
  }

  Future<void> _editJournalEntry(int index) async {
    final proc = _procedure;
    if (proc == null) return;
    if (index < 0 || index >= proc.journalEntries.length) return;
    final existing = proc.journalEntries[index];
    final result = await _openJournalEditor(existing: existing);
    if (result == null) return;
    final list = List<JournalEntry>.from(proc.journalEntries);
    list[index] = result;
    await _persistProcedure(proc.copyWith(journalEntries: list));
  }

  Future<void> _deleteJournalEntry(int index) async {
    final proc = _procedure;
    if (proc == null) return;
    if (index < 0 || index >= proc.journalEntries.length) return;
    final entry = proc.journalEntries[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: Text(
          'Are you sure you want to delete "${entry.title.trim().isEmpty ? 'this note' : entry.title.trim()}"? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.softTerracotta,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final list = List<JournalEntry>.from(proc.journalEntries)..removeAt(index);
    await _persistProcedure(proc.copyWith(journalEntries: list));
  }

  Future<JournalEntry?> _openJournalEditor({JournalEntry? existing}) {
    return showModalBottomSheet<JournalEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _JournalEditorSheet(existing: existing),
    );
  }

  // ── Export ─────────────────────────────────────────────────────────────
  Future<void> _exportReport() async {
    final proc = _procedure;
    if (proc == null) return;
    final acceptedDisclaimer = await confirmReportShareDisclaimer(context);
    if (!mounted || !acceptedDisclaimer) return;
    setState(() => _busy = true);
    try {
      final allScans = await AppPrefs.getScanEntries();
      final scans =
          allScans
              .where((s) => (s.procedureId ?? '').trim() == proc.id)
              .toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final insightsRaw = await PremiumRecoveryService.loadProgressInsights();
      final insights =
          insightsRaw
              .whereType<ProgressPhotoInsight>()
              .where(
                (i) =>
                    (i.procedureType ?? '').toLowerCase() ==
                    proc.type.toLowerCase(),
              )
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final patientName = await AppPrefs.getUserName();

      final input = ReportInput(
        procedure: proc,
        scans: scans,
        insights: insights,
        surgeonNotes: proc.notes.trim().isEmpty ? null : proc.notes.trim(),
        patientName: patientName,
        customPlanMilestones: proc.timelineMilestones,
      );

      final result = await ReportService.generateAndSave(input);
      await report_share.shareProfessionalReportPdf(
        result.pdfBytes,
        fileName: result.record.pdfFileName ?? 'recovery_report.pdf',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recovery report exported.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to generate report: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── AI Coach ───────────────────────────────────────────────────────────
  Future<void> _openAiCoach() async {
    final proc = _procedure;
    // Pass the loaded procedure directly so the coach has full context
    // (procedureId, type, journal, etc.). If null, the coach will
    // auto-resolve the active procedure from prefs.
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AIRecoveryCoachScreen(procedure: proc)),
    );
  }

  // ── Derived data ───────────────────────────────────────────────────────
  int _recoveryDay(Procedure proc) {
    final start = DateTime(
      proc.startDate.year,
      proc.startDate.month,
      proc.startDate.day,
    );
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    return todayDate.difference(start).inDays + 1;
  }

  String _recoveryStageLabel(int day) {
    if (day <= 3) return 'Initial Healing';
    if (day <= 7) return 'Early Recovery';
    if (day <= 21) return 'Mid Recovery';
    if (day <= 60) return 'Refinement';
    if (day <= 180) return 'Long-Term Healing';
    return 'Maturation';
  }

  List<String> _defaultReminders(Procedure proc) {
    final profile = ProcedureIntelligence.forType(proc.type);
    final category = ProcedureIntelligence.categoryFor(proc.type);
    switch (category) {
      case ProcedureCategory.hairTransplant:
        return const [
          'Do not touch, scratch, or pick at the recipient area.',
          'Sleep elevated for the first 5–7 nights.',
          'Avoid direct sun, swimming, and saunas for 4 weeks.',
          'Use only provider-approved gentle shampoo on washing days.',
          'Expect shock-loss between weeks 2–6 — this is normal.',
        ];
      case ProcedureCategory.injectables:
        return const [
          'Avoid touching or massaging the treated area for 24 hours.',
          'Skip strenuous exercise, alcohol, and saunas for 24–48 hours.',
          'Stay upright for 4 hours after treatment.',
          'Use cold compresses gently if bruising appears.',
          'Re-evaluate results around the 2-week mark.',
        ];
      case ProcedureCategory.bodyContouring:
        return const [
          'Wear your compression garment as directed.',
          'Walk gently several times a day to support circulation.',
          'Stay well-hydrated and prioritize protein intake.',
          'Avoid pressure on the treated area as instructed.',
          'Attend lymphatic drainage sessions when approved.',
        ];
      case ProcedureCategory.laserPeel:
        return const [
          'Avoid sun exposure and apply SPF 50+ daily.',
          'Do not pick at peeling or micro-crusts — let them shed.',
          'Use a gentle, fragrance-free cleanser and moisturizer.',
          'Skip retinoids, acids, and exfoliants for 5–7 days.',
          'Hydrate well to support collagen remodeling.',
        ];
      case ProcedureCategory.surgicalFace:
        return const [
          'Follow your surgeon’s wound-care and dressing schedule.',
          'Sleep elevated to help reduce swelling.',
          'Avoid strenuous activity until cleared.',
          'Protect incisions from sun for at least 6 months.',
          'Attend all scheduled follow-up appointments.',
        ];
      case ProcedureCategory.bodyComposition:
        return const [
          'Take medication exactly as prescribed.',
          'Prioritize protein at every meal to protect lean mass.',
          'Stay hydrated and watch for GI side effects.',
          'Maintain consistent strength training when cleared.',
          'Track weight and measurements weekly, not daily.',
        ];
      case ProcedureCategory.generalSkincare:
        // Fall back to the procedure profile's first 4 concerns.
        final concerns = profile.recoveryConcerns.take(4).toList();
        if (concerns.isNotEmpty) {
          return [
            for (final c in concerns) 'Monitor and care for: $c.',
            'Follow your provider’s aftercare instructions first.',
          ];
        }
        return const [
          'Follow your provider’s aftercare instructions first.',
          'Stay well-hydrated and prioritize rest.',
          'Protect the treated area from direct sun.',
          'Log notes daily to track how recovery is progressing.',
        ];
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.refinedSlate,
        centerTitle: true,
        title: const ClinicalAppBarTitle(
          title: 'Recovery Timeline',
          eyebrow: 'Post-procedure care',
          color: AppColors.refinedSlate,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _procedure == null
          ? (_hasSkinAiTimelineScans
                ? _buildSkinAiOnlyContent()
                : _buildEmptyState())
          : _buildContent(_procedure!),
      floatingActionButton: (_loading || _procedure == null)
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _openAiCoach,
              backgroundColor: AppColors.champagneGold,
              foregroundColor: AppColors.refinedSlate,
              elevation: 3,
              icon: const Icon(Icons.auto_awesome, size: 20),
              label: const Text(
                'Ask AI Coach',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
    );
  }

  bool get _hasSkinAiTimelineScans => _scans.any(_isSkinAiScan);

  /// A scan belongs to the AI Skin Analysis feed when it carries the
  /// legacy `sourceSkinAiAnalysis` metric flag or the dedicated
  /// `ai_skin_analysis` procedure id written by skin_ai_analysis_screen.
  static bool _isSkinAiScan(ScanHistoryEntry s) =>
      (s.metrics['sourceSkinAiAnalysis'] ?? 0) > 0 ||
      (s.procedureId ?? '').trim() == 'ai_skin_analysis';

  Widget _buildSkinAiOnlyContent() {
    final skinAiScans = _scans.where(_isSkinAiScan).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.champagneGold,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        children: [
          ClinicalSectionHeader(
            icon: Icons.auto_awesome_rounded,
            title: 'AI Skin Analysis Scans',
            eyebrow: 'Recovery timeline',
            trailing: _scanCountPill(skinAiScans.length),
          ),
          const SizedBox(height: 12),
          _buildSkinAiScanSection(skinAiScans),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    const features = <(IconData, String)>[
      (Icons.timeline_rounded, 'Phase-by-phase recovery milestones'),
      (Icons.insights_rounded, 'Metric-aware recovery insights'),
      (Icons.edit_note_rounded, 'Daily recovery journal'),
      (Icons.picture_as_pdf_outlined, 'Printable progress report'),
    ];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.champagneGold.withValues(alpha: 0.20),
                    AppColors.mutedSage.withValues(alpha: 0.14),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.champagneGold.withValues(alpha: 0.38),
                  width: 1.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.champagneGold.withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.timeline_rounded,
                size: 42,
                color: AppColors.champagneGold,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'RECOVERY ROADMAP',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.8,
                color: AppColors.champagneGold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your Recovery Timeline awaits',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.refinedSlate,
                letterSpacing: -0.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Track a procedure to unlock a personalized recovery roadmap built for your skin and healing phase.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.refinedSlate,
                fontSize: 13.5,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.champagneGold.withValues(alpha: 0.22),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.refinedSlate.withValues(alpha: 0.04),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'WHAT YOU GET',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                      color: AppColors.refinedSlate,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (var i = 0; i < features.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: i == features.length - 1 ? 0 : 9,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.mutedSage.withValues(alpha: 0.20),
                                  AppColors.mutedSage.withValues(alpha: 0.08),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.mutedSage.withValues(
                                  alpha: 0.26,
                                ),
                                width: 0.7,
                              ),
                            ),
                            child: Icon(
                              features[i].$1,
                              size: 14,
                              color: AppColors.mutedSage,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(
                              features[i].$2,
                              style: TextStyle(
                                color: AppColors.refinedSlate.withValues(
                                  alpha: 0.92,
                                ),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(context).pushNamed('/create-procedure');
                  if (!mounted) return;
                  await _load();
                },
                icon: const Icon(Icons.medical_services_rounded, size: 18),
                label: const Text(
                  'Track a Procedure',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.champagneGold,
                  foregroundColor: AppColors.refinedSlate,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(Procedure proc) {
    final day = _recoveryDay(proc);
    final stage = _recoveryStageLabel(day);
    final reminders = proc.customReminders.isNotEmpty
        ? proc.customReminders.take(5).toList()
        : _defaultReminders(proc).take(5).toList();

    final milestones = RecoveryTimelineCard.defaultTimelineMilestonesFor(
      proc.type,
      proc.startDate,
    );
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final completedCount = milestones
        .where((m) => _milestoneState(m, todayDate) == _MStone.passed)
        .length;

    final pulseInsights = _metricPulseInsights(proc, day);
    final skinAiScans = _scans.where(_isSkinAiScan).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final category = ProcedureIntelligence.categoryFor(proc.type);
    final todaysGuidance = _phaseGuidance(category, day);

    // Resolve the index of the current milestone (if any) so the phase
    // ribbon can highlight the corresponding pill.
    int currentIdx = milestones.indexWhere(
      (m) => _milestoneState(m, todayDate) == _MStone.current,
    );
    if (currentIdx < 0) {
      // No exact "current" — pick the next upcoming, otherwise the last passed.
      final upcoming = milestones.indexWhere(
        (m) => _milestoneState(m, todayDate) == _MStone.upcoming,
      );
      currentIdx = upcoming >= 0 ? upcoming : milestones.length - 1;
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.champagneGold,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildHeaderCard(
            proc,
            day,
            stage,
            completedCount,
            milestones.length,
            _nextUpcomingMilestone(milestones, todayDate),
          ),
          if (todaysGuidance != null) ...[
            const SizedBox(height: 14),
            _buildTodaysFocusCard(day, stage, todaysGuidance),
          ],
          if (pulseInsights.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildMetricPulseBanner(pulseInsights),
          ],
          if (skinAiScans.isNotEmpty) ...[
            const SizedBox(height: 26),
            ClinicalSectionHeader(
              icon: Icons.auto_awesome_rounded,
              title: 'AI Skin Analysis Scans',
              eyebrow: 'Timeline entries',
              trailing: _scanCountPill(skinAiScans.length),
            ),
            const SizedBox(height: 12),
            _buildSkinAiScanSection(skinAiScans),
          ],
          const SizedBox(height: 26),
          ClinicalSectionHeader(
            icon: Icons.timeline_rounded,
            title: 'Recovery Phases',
            eyebrow: 'Clinical roadmap',
            trailing: _phaseProgressPill(completedCount, milestones.length),
          ),
          const SizedBox(height: 12),
          if (milestones.isNotEmpty)
            _PhaseRibbon(
              milestones: milestones,
              startDate: proc.startDate,
              today: todayDate,
              currentIndex: currentIdx,
              stateOf: (m) => _milestoneState(m, todayDate),
            ),
          if (milestones.isNotEmpty) const SizedBox(height: 14),
          _buildAiGuidanceSection(proc, milestones, todayDate),
          const SizedBox(height: 26),
          ClinicalSectionHeader(
            icon: Icons.edit_note_outlined,
            title: 'Recovery Notes',
            eyebrow: 'Daily reflections',
            trailing: _journalAddTrailing(proc),
          ),
          const SizedBox(height: 12),
          _buildJournalSection(proc),
          const SizedBox(height: 26),
          ClinicalSectionHeader(
            icon: Icons.verified_outlined,
            title: 'Key Reminders',
            eyebrow: 'Aftercare protocol',
            trailing: _remindersCountPill(reminders.length),
          ),
          const SizedBox(height: 12),
          _buildRemindersSection(reminders),
          const SizedBox(height: 28),
          _buildExportButton(),
        ],
      ),
    );
  }

  // Compact "Add Note" pill used as ClinicalSectionHeader trailing.
  Widget _journalAddTrailing(Procedure proc) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: _busy ? null : _addJournalEntry,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.champagneGold, AppColors.champagneGold],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: AppColors.champagneGold.withValues(alpha: 0.24),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 14, color: Colors.white),
              SizedBox(width: 4),
              Text(
                'Add Note',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Reminders count pill displayed in the section header trailing slot.
  Widget _remindersCountPill(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.mutedSage.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.mutedSage.withValues(alpha: 0.32),
          width: 0.7,
        ),
      ),
      child: Text(
        '$count essentials',
        style: const TextStyle(
          color: AppColors.mutedSage,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  // Find the next milestone occurring at or after today (within 90 days)
  // so the hero can surface a "Next phase in X days" cue.
  ({String label, int daysAway})? _nextUpcomingMilestone(
    List<ProcedureTimelineMilestone> milestones,
    DateTime today,
  ) {
    for (final m in milestones) {
      final expected = DateTime(
        m.expectedDate.year,
        m.expectedDate.month,
        m.expectedDate.day,
      );
      final diff = expected.difference(today).inDays;
      if (diff >= 0 && diff <= 90) {
        return (label: m.label, daysAway: diff);
      }
    }
    return null;
  }

  // ── Today's Focus ──────────────────────────────────────────────────────
  // A focused, premium clinical callout tied to today's recovery day and
  // procedure category. Highlights *what* the patient should expect to
  // experience today and *where* their attention should land.
  Widget _buildTodaysFocusCard(int day, String stage, _PhaseGuidance g) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.champagneGold.withValues(alpha: 0.10),
            AppColors.champagneGold.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.32),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.champagneGold.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.champagneGold, AppColors.champagneGold],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.champagneGold.withValues(alpha: 0.32),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.today_rounded,
                  color: Colors.white,
                  size: 17,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TODAY · DAY $day · ${stage.toUpperCase()}',
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: AppColors.champagneGold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      "Today's Focus",
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.refinedSlate,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _GuidanceRow(
            icon: Icons.visibility_outlined,
            accent: AppColors.mutedSage,
            label: 'EXPECTED',
            text: g.symptoms,
          ),
          const SizedBox(height: 9),
          _GuidanceRow(
            icon: Icons.flag_rounded,
            accent: AppColors.champagneGold,
            label: 'FOCUS',
            text: g.focus,
          ),
        ],
      ),
    );
  }

  // Phase progress pill rendered as trailing inside the section header.
  Widget _phaseProgressPill(int completed, int total) {
    if (total == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.mutedSage.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.mutedSage.withValues(alpha: 0.32),
          width: 0.7,
        ),
      ),
      child: Text(
        '$completed of $total complete',
        style: const TextStyle(
          color: AppColors.mutedSage,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────
  Widget _buildHeaderCard(
    Procedure proc,
    int day,
    String stage,
    int completed,
    int total,
    ({String label, int daysAway})? nextMilestone,
  ) {
    final weekNum = ((day - 1) ~/ 7 + 1).clamp(1, 60);
    final procType = proc.type.trim().isEmpty ? 'Your procedure' : proc.type;
    final progress = total == 0
        ? 0.0
        : (completed / total).clamp(0.0, 1.0).toDouble();
    final progressPct = (progress * 100).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borders, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: AppColors.refinedSlate.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Eyebrow + procedure title ─────────────────────────────────
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.champagneGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.champagneGold.withValues(alpha: 0.28),
                  ),
                ),
                child: const Icon(
                  Icons.timeline_rounded,
                  color: AppColors.champagneGold,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'RECOVERY ROADMAP',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                        color: AppColors.champagneGold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      procType,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.refinedSlate,
                        height: 1.2,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ── Day / Week / Stage pills ──────────────────────────────────
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _headerPill('Day $day', Icons.calendar_today_outlined),
              _headerPill('Week $weekNum', Icons.view_week_outlined),
              _headerPillAccent(stage, Icons.auto_awesome),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 18),
            // ── Phase progress bar ─────────────────────────────────────
            Row(
              children: [
                Text(
                  'PHASE PROGRESS',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: AppColors.refinedSlate.withValues(alpha: 0.72),
                  ),
                ),
                const Spacer(),
                Text(
                  '$progressPct%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.champagneGold,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Stack(
                children: [
                  Container(
                    height: 8,
                    color: AppColors.refinedSlate.withValues(alpha: 0.10),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress == 0 ? 0.02 : progress,
                    child: Container(
                      height: 8,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.champagneGold,
                            AppColors.champagneGold,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$completed of $total phases complete',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.refinedSlate.withValues(alpha: 0.68),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (nextMilestone != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: AppColors.cardBackground.withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.champagneGold.withValues(alpha: 0.42),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.champagneGold.withValues(alpha: 0.95),
                          AppColors.champagneGold.withValues(alpha: 0.85),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.flag_rounded,
                      color: AppColors.refinedSlate,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nextMilestone.daysAway == 0
                              ? 'NEXT MILESTONE · TODAY'
                              : nextMilestone.daysAway == 1
                              ? 'NEXT MILESTONE · TOMORROW'
                              : 'NEXT MILESTONE · IN ${nextMilestone.daysAway} DAYS',
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                            color: AppColors.champagneGold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          nextMilestone.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.refinedSlate,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _headerPill(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.champagneGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.26),
          width: 0.7,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.champagneGold),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.refinedSlate,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerPillAccent(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.champagneGold.withValues(alpha: 0.92),
            AppColors.champagneGold.withValues(alpha: 0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.auto_awesome,
            size: 12,
            color: AppColors.refinedSlate,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppColors.refinedSlate,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  // ── Metric Pulse Banner ────────────────────────────────────────────────
  // Surfaces 1–3 phase-aware metric insights derived from the latest scan
  // (compared against the patient's earliest baseline scan when available).
  List<_PulseInsight> _metricPulseInsights(Procedure proc, int day) {
    if (_scans.isEmpty) return const [];
    final latest = _scans.last;
    final baseline = _scans.first;
    final insights = <_PulseInsight>[];

    double? metric(ScanHistoryEntry s, List<String> keys) {
      for (final k in keys) {
        final v = s.metrics[k];
        if (v != null) return v;
      }
      return null;
    }

    final lRed = metric(latest, const ['redness', 'erythema']);
    final bRed = metric(baseline, const ['redness', 'erythema']);
    if (lRed != null) {
      if (bRed != null && lRed < bRed - 0.5) {
        insights.add(
          _PulseInsight(
            'Erythema improving well',
            'Redness down ${(bRed - lRed).toStringAsFixed(1)} pts from baseline',
            Icons.trending_down_rounded,
            AppColors.mutedSage,
            true,
          ),
        );
      } else if (lRed >= 6.0 && day <= 21) {
        insights.add(
          const _PulseInsight(
            'Erythema still elevated',
            'Add 5-min LED red-light sessions 3–4×/week to accelerate resolution',
            Icons.local_fire_department_outlined,
            AppColors.softTerracotta,
            false,
          ),
        );
      }
    }

    final lTex = metric(latest, const ['texture', 'roughness']);
    final bTex = metric(baseline, const ['texture', 'roughness']);
    if (lTex != null) {
      if (bTex != null && lTex < bTex - 0.5) {
        insights.add(
          _PulseInsight(
            'Texture smoothing',
            'Smoothness improved ${(bTex - lTex).toStringAsFixed(1)} pts — collagen response is on track',
            Icons.spa_outlined,
            AppColors.mutedSage,
            true,
          ),
        );
      } else if (lTex >= 6.0 && day >= 7) {
        insights.add(
          const _PulseInsight(
            'Texture still rough',
            'Focus on hydration — HA serum AM & PM + ceramide moisturizer',
            Icons.water_drop_outlined,
            AppColors.softTerracotta,
            false,
          ),
        );
      }
    }

    final lSpot = metric(latest, const [
      'darkSpots',
      'pigmentation',
      'hyperpigmentation',
    ]);
    if (lSpot != null && lSpot >= 5.5 && day >= 5) {
      insights.add(
        const _PulseInsight(
          'Pigment activity elevated',
          'Layer azelaic 10% or tranexamic 3% PM + strict SPF 50+',
          Icons.shield_moon_outlined,
          AppColors.softTerracotta,
          false,
        ),
      );
    }

    final lHyd = metric(latest, const ['hydration', 'moisture']);
    if (lHyd != null && lHyd <= 4.0) {
      insights.add(
        const _PulseInsight(
          'Hydration trending low',
          'Apply HA serum on damp skin AM & PM — barrier needs reinforcement',
          Icons.opacity_outlined,
          Color(0xFFB7895A),
          false,
        ),
      );
    }

    return insights.take(3).toList();
  }

  Widget _buildMetricPulseBanner(List<_PulseInsight> insights) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.mutedSage.withValues(alpha: 0.08),
            AppColors.cardBackground,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.mutedSage.withValues(alpha: 0.28),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.mutedSage.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.mutedSage.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.insights_rounded,
                  size: 15,
                  color: AppColors.mutedSage,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'METRIC PULSE · LATEST SCAN',
                      style: TextStyle(
                        color: AppColors.mutedSage.withValues(alpha: 0.9),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Recovery signals tied to your current phase',
                      style: TextStyle(
                        color: AppColors.refinedSlate,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...List.generate(insights.length, (i) {
            final ins = insights[i];
            final isLast = i == insights.length - 1;
            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: ins.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(ins.icon, size: 13, color: ins.color),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ins.title,
                          style: const TextStyle(
                            color: AppColors.refinedSlate,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          ins.detail,
                          style: const TextStyle(
                            color: AppColors.refinedSlate,
                            fontSize: 11.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSkinAiScanSection(List<ScanHistoryEntry> scans) {
    return Column(
      children: [
        for (var index = 0; index < scans.length; index++) ...[
          // Scans are newest-first, so the "previous" scan for trend
          // comparison is the next (older) entry in the list.
          _buildSkinAiScanCard(
            scans[index],
            previous: index + 1 < scans.length ? scans[index + 1] : null,
          ),
          if (index != scans.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildSkinAiScanCard(
    ScanHistoryEntry scan, {
    ScanHistoryEntry? previous,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showSkinAiScanDetails(scan),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.champagneGold.withValues(alpha: 0.24),
              width: 0.9,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.champagneGold.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppColors.champagneGold.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      size: 16,
                      color: AppColors.champagneGold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Skin AI Analysis',
                          style: TextStyle(
                            color: AppColors.refinedSlate,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatScanDate(scan.timestamp),
                          style: const TextStyle(
                            color: AppColors.refinedSlate,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.refinedSlate.withValues(alpha: 0.75),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildSkinAiMetricsLayout(
                scan,
                previous,
                procedureType: _procedureTypeForScan(scan),
              ),
              if (previous != null) ...[
                const SizedBox(height: 10),
                _strongestImprovementSummary(
                  scan,
                  previous,
                  procedureType: _procedureTypeForScan(scan),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Map<String, double> _skinAiTimelineMetrics(ScanHistoryEntry scan) {
    double score(List<String> keys) {
      for (final key in keys) {
        final value = scan.metrics[key];
        if (value != null) return value.clamp(0, 10).toDouble();
      }
      return 0;
    }

    return {
      'Pigment': score(const ['pigment', 'pigmentation', 'darkSpots']),
      'Redness': score(const ['redness', 'erythema']),
      'Texture': score(const ['texture', 'roughness', 'smoothness']),
      'Wrinkle': score(const ['wrinkle', 'wrinkles', 'rhytids']),
      'Acne Severity': score(const ['acne_severity', 'acneSeverity']),
      'Rosacea': score(const [
        'rosacea_intensity',
        'rosaceaIntensity',
        'rosaceaSeverity',
      ]),
    };
  }

  String? _procedureTypeForScan(ScanHistoryEntry scan) {
    final proc = _procedure;
    if (proc != null) {
      final scanProcedureId = (scan.procedureId ?? '').trim();
      if (scanProcedureId == proc.id || _isSkinAiScan(scan)) return proc.type;
    }
    final savedProcedure = scan.procedure?.trim();
    return savedProcedure?.isNotEmpty == true ? savedProcedure : null;
  }

  // ── Skin AI metrics: grouped grid with trend indicators ───────────

  /// Maps a display label to the candidate metric keys (handles aliases
  /// across the 0–1 service scans and 0–10 timeline scans).
  static const List<(String, List<String>)> _generalMetricSpecs = [
    ('Pigment', ['pigment', 'pigmentation', 'darkSpots']),
    ('Redness', ['redness', 'erythema']),
    ('Texture', ['texture', 'roughness', 'smoothness']),
    ('Wrinkle', ['wrinkle', 'wrinkles', 'rhytids']),
  ];
  static const List<(String, List<String>)> _inflammatoryMetricSpecs = [
    ('Acne Severity', ['acne_severity', 'acneSeverity']),
    ('Rosacea', ['rosacea_intensity', 'rosaceaIntensity', 'rosaceaSeverity']),
  ];

  /// Reads the first present candidate key from a scan, on the 0–10
  /// scale. Returns null when none of the keys exist on this scan.
  double? _extractMetric(ScanHistoryEntry scan, List<String> keys) {
    for (final key in keys) {
      final v = scan.metrics[key];
      if (v != null) return v.clamp(0, 10).toDouble();
    }
    return null;
  }

  /// Builds the two accented metric groups for a scan card. Both groups
  /// always show their metrics (defaulting to 0) so every scan renders a
  /// consistent six-metric breakdown.
  Widget _buildSkinAiMetricsLayout(
    ScanHistoryEntry scan,
    ScanHistoryEntry? previous, {
    String? procedureType,
  }) {
    final metricSet = getMetricsForProcedure(procedureType);
    if (metricSet.category == ProcedureMetricCategory.bodyContouring) {
      final latestSkin = scan.toSkinMetrics();
      final previousSkin = previous?.toSkinMetrics();
      final bodyTiles =
          <
            ({String label, double value, double? previous, bool lowerIsBetter})
          >[];
      for (final metric in metricSet.additional) {
        bodyTiles.add((
          label: metric.label,
          value: metric.valueFor(latestSkin, rawMetrics: scan.metrics),
          previous: previous == null || previousSkin == null
              ? null
              : metric.valueFor(previousSkin, rawMetrics: previous.metrics),
          lowerIsBetter: metric.lowerIsBetter,
        ));
      }
      return _buildMetricGroup(
        icon: Icons.monitor_heart_rounded,
        title: 'Body Recovery Metrics',
        accent: AppColors.mutedSage,
        tiles: bodyTiles,
      );
    }

    // (label, value, previousValue?)
    final general =
        <
          ({String label, double value, double? previous, bool lowerIsBetter})
        >[];
    for (final spec in _generalMetricSpecs) {
      final value = _extractMetric(scan, spec.$2) ?? 0;
      final prev = previous == null ? null : _extractMetric(previous, spec.$2);
      general.add((
        label: spec.$1,
        value: value,
        previous: prev,
        lowerIsBetter: true,
      ));
    }

    final inflammatory =
        <
          ({String label, double value, double? previous, bool lowerIsBetter})
        >[];
    for (final spec in _inflammatoryMetricSpecs) {
      final value = _extractMetric(scan, spec.$2) ?? 0;
      final prev = previous == null ? null : _extractMetric(previous, spec.$2);
      inflammatory.add((
        label: spec.$1,
        value: value,
        previous: prev,
        lowerIsBetter: true,
      ));
    }

    return Column(
      children: [
        _buildMetricGroup(
          icon: Icons.spa_rounded,
          title: 'General Skin Quality',
          accent: AppColors.mutedSage,
          tiles: general,
        ),
        const SizedBox(height: 10),
        _buildMetricGroup(
          icon: Icons.local_fire_department_rounded,
          title: 'Inflammatory Conditions',
          accent: const Color(0xFFD06B6B),
          tiles: inflammatory,
        ),
      ],
    );
  }

  Widget _strongestImprovementSummary(
    ScanHistoryEntry scan,
    ScanHistoryEntry previous, {
    String? procedureType,
  }) {
    String? bestLabel;
    double bestDelta = 0;
    final metricSet = getMetricsForProcedure(procedureType);
    if (metricSet.category == ProcedureMetricCategory.bodyContouring) {
      final latestSkin = scan.toSkinMetrics();
      final previousSkin = previous.toSkinMetrics();
      for (final metric in metricSet.additional) {
        final current = metric.valueFor(latestSkin, rawMetrics: scan.metrics);
        final prev = metric.valueFor(
          previousSkin,
          rawMetrics: previous.metrics,
        );
        final improvement = metric.lowerIsBetter
            ? prev - current
            : current - prev;
        if (improvement > bestDelta) {
          bestDelta = improvement;
          bestLabel = metric.label;
        }
      }
    } else {
      for (final spec in [
        ..._generalMetricSpecs,
        ..._inflammatoryMetricSpecs,
      ]) {
        final current = _extractMetric(scan, spec.$2);
        final prev = _extractMetric(previous, spec.$2);
        if (spec.$1 == 'Wrinkle' || spec.$1 == 'Rosacea') continue;
        if (current == null || prev == null) continue;
        final improvement = prev - current;
        if (improvement > bestDelta) {
          bestDelta = improvement;
          bestLabel = spec.$1;
        }
      }
    }

    if (bestLabel == null || bestDelta < 0.25) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: AppColors.refinedSlate.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.refinedSlate.withValues(alpha: 0.14),
            width: 0.7,
          ),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.trending_flat_rounded,
              color: AppColors.refinedSlate,
              size: 15,
            ),
            SizedBox(width: 7),
            Expanded(
              child: Text(
                'Stable trend: no major metric change since the previous scan.',
                style: TextStyle(
                  color: AppColors.refinedSlate,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.mutedSage.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.mutedSage.withValues(alpha: 0.28),
          width: 0.7,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.arrow_downward_rounded,
            color: AppColors.mutedSage,
            size: 15,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Biggest win: $bestLabel improved by ${bestDelta.toStringAsFixed(1)} points.',
              style: const TextStyle(
                color: AppColors.refinedSlate,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A tinted, bordered group container with an accent header and a
  /// responsive 2-column grid of metric tiles.
  Widget _buildMetricGroup({
    required IconData icon,
    required String title,
    required Color accent,
    required List<
      ({String label, double value, double? previous, bool lowerIsBetter})
    >
    tiles,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 11),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.22), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: accent),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.7,
                  fontWeight: FontWeight.w900,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          // Two tiles per row; the last odd tile keeps a half-width slot.
          for (int i = 0; i < tiles.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _metricTile(tiles[i], accent)),
                const SizedBox(width: 8),
                if (i + 1 < tiles.length)
                  Expanded(child: _metricTile(tiles[i + 1], accent))
                else
                  const Expanded(child: SizedBox()),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// A single compact metric tile: label + trend arrow, value/10 with a
  /// severity band, and a colour-coded mini bar. Severity colours come
  /// from [_metricValueColor] / [_severityBandForValue] for app-wide
  /// consistency; the group [accent] frames the tile.
  Widget _metricTile(
    ({String label, double value, double? previous, bool lowerIsBetter}) data,
    Color accent,
  ) {
    final label = data.label;
    final value = data.value;
    final previous = data.previous;
    final lowerIsBetter = data.lowerIsBetter;
    final suppressTrend = label == 'Wrinkle' || label == 'Rosacea';
    final delta = previous == null ? null : value - previous;
    final severity = _metricValueColor(value, lowerIsBetter: lowerIsBetter);
    final band = _severityBandForValue(value, lowerIsBetter: lowerIsBetter);
    final previousValue = previous;
    final improved =
        delta != null &&
        delta.abs() >= 0.25 &&
        (lowerIsBetter ? delta < 0 : delta > 0);
    final trendColor = delta == null
        ? null
        : delta.abs() < 0.25
        ? AppColors.refinedSlate
        : improved
        ? AppColors.mutedSage
        : AppColors.softTerracotta;
    final trendLabel = suppressTrend || delta == null
        ? null
        : delta.abs() < 0.25
        ? 'stable from ${previousValue!.toStringAsFixed(1)}'
        : improved
        ? 'improved from ${previousValue!.toStringAsFixed(1)}'
        : 'worsened from ${previousValue!.toStringAsFixed(1)}';
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.18), width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.refinedSlate,
                  ),
                ),
              ),
              if (previous != null && !suppressTrend)
                _trendArrow(value, previous, lowerIsBetter: lowerIsBetter),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.refinedSlate,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                '/10',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.refinedSlate.withValues(alpha: 0.7),
                ),
              ),
              const Spacer(),
              Text(
                band.toUpperCase(),
                style: TextStyle(
                  fontSize: 7.5,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w900,
                  color: severity,
                ),
              ),
            ],
          ),
          if (previous != null && delta != null && trendLabel != null) ...[
            const SizedBox(height: 5),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: trendColor!.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: trendColor.withValues(alpha: 0.18),
                  width: 0.6,
                ),
              ),
              child: Text(
                '${delta.abs() < 0.25
                    ? '→'
                    : improved
                    ? (lowerIsBetter ? '↓' : '↑')
                    : (lowerIsBetter ? '↑' : '↓')} '
                '${delta.abs().toStringAsFixed(1)} · $trendLabel',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: trendColor,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
            ),
          ],
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: (value / 10).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: severity.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(severity),
            ),
          ),
        ],
      ),
    );
  }

  /// Small trend indicator vs the previous scan. All metrics are
  /// "higher = worse", so a drop is an improvement (green ↓), a rise is
  /// a worsening (red ↑), and near-equal is stable (grey →). Shows a
  /// 1-decimal delta for real changes.
  Widget _trendArrow(
    double current,
    double previous, {
    bool lowerIsBetter = true,
  }) {
    final delta = current - previous;
    final improved = lowerIsBetter ? delta < 0 : delta > 0;
    final IconData icon;
    final Color color;
    if (delta.abs() < 0.25) {
      icon = Icons.trending_flat_rounded;
      color = AppColors.refinedSlate;
    } else if (improved) {
      icon = lowerIsBetter
          ? Icons.arrow_downward_rounded
          : Icons.arrow_upward_rounded;
      color = AppColors.mutedSage;
    } else {
      icon = lowerIsBetter
          ? Icons.arrow_upward_rounded
          : Icons.arrow_downward_rounded;
      color = AppColors.softTerracotta;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        if (delta.abs() >= 0.25) ...[
          const SizedBox(width: 1),
          Text(
            delta.abs().toStringAsFixed(1),
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ],
    );
  }

  /// Severity colour for a 0–10 value, mirroring `_valueColor` in
  /// skin_ai_analysis_screen.dart for cross-screen consistency.
  Color _metricValueColor(double v, {bool lowerIsBetter = true}) {
    if (!lowerIsBetter) {
      if (v >= 8) return AppColors.mutedSage;
      if (v >= 6) return const Color(0xFF7AA874);
      if (v >= 4) return const Color(0xFFB89A6E);
      return AppColors.softTerracotta;
    }
    if (v <= 2) return AppColors.mutedSage;
    if (v <= 5) return const Color(0xFFB89A6E);
    if (v <= 7) return const Color(0xFFD08A4A);
    return AppColors.softTerracotta;
  }

  /// Severity band label for a 0–10 value, mirroring
  /// `_severityBandForValue` in skin_ai_analysis_screen.dart.
  String _severityBandForValue(double v, {bool lowerIsBetter = true}) {
    if (!lowerIsBetter) {
      if (v >= 8) return 'Strong';
      if (v >= 6) return 'Good';
      if (v >= 4) return 'Fair';
      return 'Low';
    }
    if (v <= 1) return 'Clear';
    if (v <= 3) return 'Mild';
    if (v <= 5) return 'Moderate';
    if (v <= 7) return 'Marked';
    return 'Severe';
  }

  Widget _scanCountPill(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.champagneGold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.30),
          width: 0.7,
        ),
      ),
      child: Text(
        '$count saved',
        style: const TextStyle(
          color: AppColors.champagneGold,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Future<void> _showSkinAiScanDetails(ScanHistoryEntry scan) async {
    final metrics = _skinAiTimelineMetrics(scan);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Skin AI Analysis'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_formatScanDate(scan.timestamp)),
            const SizedBox(height: 12),
            for (final entry in metrics.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(entry.key),
                    Text(
                      entry.value.toStringAsFixed(1),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            if ((scan.imagePath ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Linked photo is attached to this analysis entry.',
                style: TextStyle(
                  color: AppColors.refinedSlate,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatScanDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = date.hour == 0
        ? 12
        : date.hour > 12
        ? date.hour - 12
        : date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${months[date.month - 1]} ${date.day}, ${date.year} · $hour:$minute $period';
  }

  // ── AI Guidance ────────────────────────────────────────────────────────
  Widget _buildAiGuidanceSection(
    Procedure proc,
    List<ProcedureTimelineMilestone> milestones,
    DateTime todayDate,
  ) {
    final category = ProcedureIntelligence.categoryFor(proc.type);

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < milestones.length; i++)
            _MilestoneTile(
              milestone: milestones[i],
              isLast: i == milestones.length - 1,
              today: todayDate,
              startDate: proc.startDate,
              state: _milestoneState(milestones[i], todayDate),
              prevState: i == 0
                  ? null
                  : _milestoneState(milestones[i - 1], todayDate),
              phaseGuidance:
                  _milestoneState(milestones[i], todayDate) == _MStone.current
                  ? _phaseGuidance(
                      category,
                      _dayOffsetForMilestone(milestones[i], proc.startDate),
                    )
                  : null,
            ),
        ],
      ),
    );
  }

  int _dayOffsetForMilestone(ProcedureTimelineMilestone m, DateTime startDate) {
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(
      m.expectedDate.year,
      m.expectedDate.month,
      m.expectedDate.day,
    );
    return e.difference(s).inDays + 1;
  }

  /// Phase-specific symptoms + focus tied to the procedure category and the
  /// day-offset of the current milestone. Concise, clinical, and supportive.
  _PhaseGuidance? _phaseGuidance(ProcedureCategory category, int dayOffset) {
    if (dayOffset <= 0) {
      return const _PhaseGuidance(
        symptoms: 'Pre-procedure — anticipation is normal',
        focus: 'Hydrate, avoid blood thinners, confirm aftercare supplies',
      );
    }
    switch (category) {
      case ProcedureCategory.laserPeel:
        if (dayOffset <= 3) {
          return const _PhaseGuidance(
            symptoms: 'Erythema, mild swelling, sandpaper texture, warmth',
            focus: 'Bland moisturizer + SPF 50+. No actives, no friction.',
          );
        }
        if (dayOffset <= 7) {
          return const _PhaseGuidance(
            symptoms: 'Light peeling, micro-crusts, tightness',
            focus: 'Hands off. Hyaluronic acid + ceramide barrier support.',
          );
        }
        if (dayOffset <= 21) {
          return const _PhaseGuidance(
            symptoms: 'Pink hue, smoother texture emerging',
            focus:
                'Reintroduce azelaic acid. Strict SPF — pigment risk window.',
          );
        }
        if (dayOffset <= 60) {
          return const _PhaseGuidance(
            symptoms: 'Texture refining, faded discoloration',
            focus: 'Resume gentle vitamin C 10–15% AM. Collagen-cycle phase.',
          );
        }
        return const _PhaseGuidance(
          symptoms: 'Final remodeling, mature collagen',
          focus: 'Capture metric scan to confirm sustained improvement.',
        );

      case ProcedureCategory.injectables:
        if (dayOffset <= 3) {
          return const _PhaseGuidance(
            symptoms: 'Mild swelling, possible bruising, small bumps',
            focus: 'Stay upright. No massage, exercise, or heat.',
          );
        }
        if (dayOffset <= 14) {
          return const _PhaseGuidance(
            symptoms: 'Swelling resolving; product settling into position',
            focus: 'Reassess at 2 weeks — do not judge results before then.',
          );
        }
        return const _PhaseGuidance(
          symptoms: 'Full effect visible, natural integration',
          focus: 'Schedule touch-up window if needed for symmetry.',
        );

      case ProcedureCategory.surgicalFace:
        if (dayOffset <= 7) {
          return const _PhaseGuidance(
            symptoms: 'Swelling, bruising, tightness, possible numbness',
            focus: 'Sleep elevated. Wound care per surgeon. Rest.',
          );
        }
        if (dayOffset <= 28) {
          return const _PhaseGuidance(
            symptoms: 'Visible swelling resolving, sensation returning',
            focus: 'Gentle lymphatic massage if cleared. Avoid sun.',
          );
        }
        if (dayOffset <= 180) {
          return const _PhaseGuidance(
            symptoms: 'Scar maturation, subtle tightness',
            focus: 'Silicone gel/sheets on incisions. Strict SPF 50+.',
          );
        }
        return const _PhaseGuidance(
          symptoms: 'Final results crystallizing',
          focus: 'Long-term sun protection preserves your investment.',
        );

      case ProcedureCategory.hairTransplant:
        if (dayOffset <= 7) {
          return const _PhaseGuidance(
            symptoms: 'Scabbing, redness, tightness in recipient area',
            focus: 'No touching, no picking. Approved shampoo only.',
          );
        }
        if (dayOffset <= 42) {
          return const _PhaseGuidance(
            symptoms: 'Shock-loss between weeks 2–6 — this is expected',
            focus: 'Stay patient. Minoxidil + finasteride if prescribed.',
          );
        }
        if (dayOffset <= 180) {
          return const _PhaseGuidance(
            symptoms: 'New growth emerging fine and slow',
            focus: 'Monthly photos in matched lighting. No bleach yet.',
          );
        }
        return const _PhaseGuidance(
          symptoms: 'Mature density developing',
          focus: 'Density assessment at 9–12 months for full result.',
        );

      case ProcedureCategory.bodyContouring:
        if (dayOffset <= 7) {
          return const _PhaseGuidance(
            symptoms: 'Swelling, soreness, possible bruising or numbness',
            focus: 'Compression garment as directed. Gentle walking.',
          );
        }
        if (dayOffset <= 28) {
          return const _PhaseGuidance(
            symptoms: 'Inflammation peaking then resolving',
            focus: 'Lymphatic drainage. Protein + hydration support healing.',
          );
        }
        if (dayOffset <= 90) {
          return const _PhaseGuidance(
            symptoms: 'Contour refining, residual firmness',
            focus: 'Resume strength training when cleared.',
          );
        }
        return const _PhaseGuidance(
          symptoms: 'Final contour stabilized',
          focus: 'Maintain weight ±5 lb for sustained results.',
        );

      case ProcedureCategory.bodyComposition:
        if (dayOffset <= 14) {
          return const _PhaseGuidance(
            symptoms: 'GI side effects, appetite shifts, fatigue possible',
            focus: 'Hydrate aggressively. Protein at every meal.',
          );
        }
        if (dayOffset <= 84) {
          return const _PhaseGuidance(
            symptoms: 'Steady weight trend, satiety improvements',
            focus: 'Strength training to protect lean mass.',
          );
        }
        return const _PhaseGuidance(
          symptoms: 'Approaching set-point or maintenance phase',
          focus: 'Plan a maintenance protocol with your provider.',
        );

      case ProcedureCategory.generalSkincare:
        if (dayOffset <= 3) {
          return const _PhaseGuidance(
            symptoms: 'Mild redness, sensitivity, possible tightness',
            focus: 'Gentle cleanser + barrier moisturizer + SPF.',
          );
        }
        if (dayOffset <= 14) {
          return const _PhaseGuidance(
            symptoms: 'Skin adjusting, early texture changes',
            focus: 'Reintroduce one active at a time, every other night.',
          );
        }
        return const _PhaseGuidance(
          symptoms: 'Visible cumulative improvement',
          focus: 'Capture a metric scan to quantify your progress.',
        );
    }
  }

  _MStone _milestoneState(ProcedureTimelineMilestone m, DateTime today) {
    final expected = DateTime(
      m.expectedDate.year,
      m.expectedDate.month,
      m.expectedDate.day,
    );
    final diff = expected.difference(today).inDays;
    if (diff < -2) return _MStone.passed;
    if (diff.abs() <= 2) return _MStone.current;
    return _MStone.upcoming;
  }

  // ── Journal ────────────────────────────────────────────────────────────
  Widget _buildJournalSection(Procedure proc) {
    final entries = proc.journalEntries;
    return _SectionCard(
      child: entries.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.champagneGold.withValues(
                            alpha: 0.14,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.edit_note_rounded,
                          size: 18,
                          color: AppColors.champagneGold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'No notes yet',
                          style: TextStyle(
                            color: AppColors.refinedSlate,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Capture how you are feeling, side effects, or anything worth remembering. Notes also enrich your shareable progress report.',
                    style: TextStyle(
                      color: AppColors.refinedSlate,
                      fontSize: 12.5,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _busy ? null : _addJournalEntry,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Your First Note'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.champagneGold,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 11,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < entries.length; i++)
                  _JournalTile(
                    entry: entries[i],
                    onEdit: () => _editJournalEntry(i),
                    onDelete: () => _deleteJournalEntry(i),
                  ),
              ],
            ),
    );
  }

  // ── Reminders ──────────────────────────────────────────────────────────
  Widget _buildRemindersSection(List<String> reminders) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < reminders.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == reminders.length - 1 ? 0 : 10,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(top: 1, right: 10),
                    decoration: BoxDecoration(
                      color: AppColors.mutedSage.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: AppColors.mutedSage.withValues(alpha: 0.28),
                        width: 0.7,
                      ),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: AppColors.mutedSage,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      reminders[i],
                      style: TextStyle(
                        color: AppColors.refinedSlate.withValues(alpha: 0.92),
                        height: 1.45,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Export Button ──────────────────────────────────────────────────────
  Widget _buildExportButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.champagneGold.withValues(alpha: 0.10),
            AppColors.champagneGold.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.32),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.champagneGold.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.champagneGold, AppColors.champagneGold],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.champagneGold.withValues(alpha: 0.32),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.picture_as_pdf_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CLINICAL EXPORT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: AppColors.champagneGold,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Recovery Report PDF',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.refinedSlate,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Share milestones, notes, and metric trends with your provider in a clean, printable summary.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.refinedSlate,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          const ReportDisclaimerNotice(compact: true),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _exportReport,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.file_download_outlined, size: 18),
              label: Text(_busy ? 'Generating…' : 'Generate PDF'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.champagneGold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                textStyle: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Reusable section card
// ───────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.20),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.refinedSlate.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

// Internal milestone state.
enum _MStone { passed, current, upcoming }

class _PhaseGuidance {
  const _PhaseGuidance({required this.symptoms, required this.focus});
  final String symptoms;
  final String focus;
}

class _PulseInsight {
  const _PulseInsight(
    this.title,
    this.detail,
    this.icon,
    this.color,
    this.positive,
  );
  final String title;
  final String detail;
  final IconData icon;
  final Color color;
  final bool positive;
}

// ───────────────────────────────────────────────────────────────────────────
// AI milestone tile
// ───────────────────────────────────────────────────────────────────────────

class _MilestoneTile extends StatelessWidget {
  const _MilestoneTile({
    required this.milestone,
    required this.today,
    required this.isLast,
    required this.startDate,
    required this.state,
    required this.prevState,
    this.phaseGuidance,
  });

  final ProcedureTimelineMilestone milestone;
  final DateTime today;
  final bool isLast;
  final DateTime startDate;
  final _MStone state;
  final _MStone? prevState;
  final _PhaseGuidance? phaseGuidance;

  /// Format an offset from procedure start as a phase label.
  /// E.g. "Day 1–3", "Week 1", "Week 2", "Month 1", "Month 3".
  String _phaseLabel(int dayOffset) {
    if (dayOffset <= 0) return 'Pre-Op';
    if (dayOffset <= 3) return 'Day 1–3';
    if (dayOffset <= 7) return 'Week 1';
    if (dayOffset <= 14) return 'Week 2';
    if (dayOffset <= 21) return 'Week 3';
    if (dayOffset <= 28) return 'Week 4';
    if (dayOffset <= 60) return 'Month ${(dayOffset / 30).round().clamp(1, 2)}';
    if (dayOffset <= 365) {
      return 'Month ${(dayOffset / 30).round().clamp(3, 12)}';
    }
    return 'Year ${(dayOffset / 365).round()}';
  }

  Color _stateColor() {
    switch (state) {
      case _MStone.passed:
        return AppColors.mutedSage;
      case _MStone.current:
        return AppColors.champagneGold;
      case _MStone.upcoming:
        return AppColors.refinedSlate.withValues(alpha: 0.55);
    }
  }

  String _stateLabel() {
    switch (state) {
      case _MStone.passed:
        return 'COMPLETED';
      case _MStone.current:
        return 'CURRENT PHASE';
      case _MStone.upcoming:
        return 'UPCOMING';
    }
  }

  IconData _stateIcon() {
    switch (state) {
      case _MStone.passed:
        return Icons.check_rounded;
      case _MStone.current:
        return Icons.auto_awesome;
      case _MStone.upcoming:
        return Icons.circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _stateColor();
    final isCurrent = state == _MStone.current;
    final isPassed = state == _MStone.passed;
    final dayOffset =
        DateTime(
              milestone.expectedDate.year,
              milestone.expectedDate.month,
              milestone.expectedDate.day,
            )
            .difference(
              DateTime(startDate.year, startDate.month, startDate.day),
            )
            .inDays +
        1;
    final phaseLabel = _phaseLabel(dayOffset);
    final railColor = isPassed
        ? AppColors.mutedSage
        : isCurrent
        ? AppColors.champagneGold
        : AppColors.refinedSlate.withValues(alpha: 0.3);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Timeline rail ─────────────────────────────────────────────
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  gradient: isCurrent
                      ? const LinearGradient(
                          colors: [
                            AppColors.champagneGold,
                            AppColors.champagneGold,
                          ],
                        )
                      : null,
                  color: isCurrent
                      ? null
                      : isPassed
                      ? AppColors.mutedSage
                      : AppColors.cardBackground,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: isCurrent ? 0 : 1.6),
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: AppColors.champagneGold.withValues(
                              alpha: 0.45,
                            ),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  _stateIcon(),
                  size: 12,
                  color: isCurrent || isPassed ? Colors.white : color,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    color: railColor,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          // ── Content card ──────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Container(
                padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
                decoration: BoxDecoration(
                  gradient: isCurrent
                      ? LinearGradient(
                          colors: [
                            AppColors.champagneGold.withValues(alpha: 0.10),
                            AppColors.champagneGold.withValues(alpha: 0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: isCurrent ? null : AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isCurrent
                        ? AppColors.champagneGold.withValues(alpha: 0.42)
                        : isPassed
                        ? AppColors.mutedSage.withValues(alpha: 0.22)
                        : AppColors.refinedSlate.withValues(alpha: 0.18),
                    width: isCurrent ? 1.1 : 0.8,
                  ),
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: AppColors.champagneGold.withValues(
                              alpha: 0.16,
                            ),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Phase chip + status badge ─────────────────────
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: color.withValues(alpha: 0.32),
                              width: 0.7,
                            ),
                          ),
                          child: Text(
                            phaseLabel.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: isPassed
                                  ? AppColors.mutedSage
                                  : isCurrent
                                  ? AppColors.champagneGold
                                  : AppColors.refinedSlate,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _stateLabel(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: isPassed
                                ? AppColors.mutedSage
                                : isCurrent
                                ? AppColors.champagneGold
                                : AppColors.refinedSlate.withValues(alpha: 0.7),
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      milestone.label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.refinedSlate,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      milestone.description,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.refinedSlate,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (phaseGuidance != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        height: 1,
                        color: AppColors.champagneGold.withValues(alpha: 0.18),
                      ),
                      const SizedBox(height: 10),
                      _GuidanceRow(
                        icon: Icons.visibility_outlined,
                        accent: AppColors.mutedSage,
                        label: 'EXPECTED',
                        text: phaseGuidance!.symptoms,
                      ),
                      const SizedBox(height: 8),
                      _GuidanceRow(
                        icon: Icons.flag_rounded,
                        accent: AppColors.champagneGold,
                        label: 'FOCUS',
                        text: phaseGuidance!.focus,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Inline guidance row used inside the current-phase milestone tile
// ───────────────────────────────────────────────────────────────────────────

class _GuidanceRow extends StatelessWidget {
  const _GuidanceRow({
    required this.icon,
    required this.accent,
    required this.label,
    required this.text,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: 0.22),
                accent.withValues(alpha: 0.10),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: accent.withValues(alpha: 0.32),
              width: 0.7,
            ),
          ),
          child: Icon(icon, size: 12, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                  color: accent,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                text,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.refinedSlate.withValues(alpha: 0.92),
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Journal entry tile
// ───────────────────────────────────────────────────────────────────────────

class _JournalTile extends StatelessWidget {
  const _JournalTile({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  final JournalEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  String _formatDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final title = entry.title.trim().isEmpty ? 'Recovery Note' : entry.title;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.22),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.refinedSlate.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 44,
            margin: const EdgeInsets.only(right: 12, top: 2),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.champagneGold, AppColors.champagneGold],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.refinedSlate,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.mutedSage.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppColors.mutedSage.withValues(alpha: 0.22),
                          width: 0.6,
                        ),
                      ),
                      child: Text(
                        _formatDate(entry.date),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.mutedSage,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  entry.content,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.refinedSlate,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: Icon(
              Icons.more_vert,
              color: AppColors.refinedSlate.withValues(alpha: 0.7),
            ),
            onSelected: (v) {
              if (v == 'edit') onEdit();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Horizontal phase ribbon — gives the timeline a strong scannable
// "centerpiece" that previews every phase at a glance with the current one
// emphasized via a rose-gold gradient pill and subtle glow.
// ───────────────────────────────────────────────────────────────────────────

class _PhaseRibbon extends StatelessWidget {
  const _PhaseRibbon({
    required this.milestones,
    required this.startDate,
    required this.today,
    required this.currentIndex,
    required this.stateOf,
  });

  final List<ProcedureTimelineMilestone> milestones;
  final DateTime startDate;
  final DateTime today;
  final int currentIndex;
  final _MStone Function(ProcedureTimelineMilestone) stateOf;

  String _phaseLabel(int dayOffset) {
    if (dayOffset <= 0) return 'Pre-Op';
    if (dayOffset <= 3) return 'Day 1–3';
    if (dayOffset <= 7) return 'Week 1';
    if (dayOffset <= 14) return 'Week 2';
    if (dayOffset <= 21) return 'Week 3';
    if (dayOffset <= 28) return 'Week 4';
    if (dayOffset <= 60) return 'Month ${(dayOffset / 30).round().clamp(1, 2)}';
    if (dayOffset <= 365) {
      return 'Month ${(dayOffset / 30).round().clamp(3, 12)}';
    }
    return 'Year ${(dayOffset / 365).round()}';
  }

  int _dayOffset(ProcedureTimelineMilestone m) {
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(
      m.expectedDate.year,
      m.expectedDate.month,
      m.expectedDate.day,
    );
    return e.difference(s).inDays + 1;
  }

  @override
  Widget build(BuildContext context) {
    final controller = ScrollController(
      initialScrollOffset: (currentIndex.clamp(0, 999) * 96.0).toDouble(),
    );
    // Overall roadmap progress used for the rail beneath the ribbon.
    final passedCount = milestones
        .where((m) => stateOf(m) == _MStone.passed)
        .length;
    final total = milestones.length;
    final progress = total == 0
        ? 0.0
        : ((passedCount + (currentIndex >= 0 ? 0.5 : 0)) / total)
              .clamp(0.0, 1.0)
              .toDouble();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.20),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.refinedSlate.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 9),
            child: Row(
              children: [
                const Icon(
                  Icons.route_rounded,
                  size: 14,
                  color: AppColors.mutedSage,
                ),
                const SizedBox(width: 6),
                const Text(
                  'PHASE OVERVIEW',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                    color: AppColors.refinedSlate,
                  ),
                ),
                const Spacer(),
                Text(
                  'Start  →  Recovery',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: AppColors.refinedSlate.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 60,
            child: ListView.separated(
              controller: controller,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 2),
              itemCount: milestones.length,
              separatorBuilder: (_, __) => const _RibbonConnector(),
              itemBuilder: (context, i) {
                final m = milestones[i];
                final state = stateOf(m);
                final dayOff = _dayOffset(m);
                final isCurrent = i == currentIndex || state == _MStone.current;
                final isPassed = state == _MStone.passed;
                final accent = isPassed
                    ? AppColors.mutedSage
                    : isCurrent
                    ? AppColors.champagneGold
                    : AppColors.refinedSlate.withValues(alpha: 0.55);
                return _PhasePill(
                  label: _phaseLabel(dayOff),
                  accent: accent,
                  isPassed: isPassed,
                  isCurrent: isCurrent,
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          // ── Overall roadmap progress rail ─────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Stack(
                children: [
                  Container(
                    height: 5,
                    color: AppColors.refinedSlate.withValues(alpha: 0.14),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress == 0 ? 0.02 : progress,
                    child: Container(
                      height: 5,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.mutedSage,
                            AppColors.champagneGold,
                            AppColors.champagneGold,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RibbonConnector extends StatelessWidget {
  const _RibbonConnector();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Center(
        child: Container(
          width: 14,
          height: 1.4,
          decoration: BoxDecoration(
            color: AppColors.refinedSlate.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

class _PhasePill extends StatelessWidget {
  const _PhasePill({
    required this.label,
    required this.accent,
    required this.isPassed,
    required this.isCurrent,
  });

  final String label;
  final Color accent;
  final bool isPassed;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final IconData icon = isPassed
        ? Icons.check_rounded
        : isCurrent
        ? Icons.auto_awesome
        : Icons.circle_outlined;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        gradient: isCurrent
            ? const LinearGradient(
                colors: [AppColors.champagneGold, AppColors.champagneGold],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isCurrent
            ? null
            : isPassed
            ? AppColors.mutedSage.withValues(alpha: 0.10)
            : AppColors.cardBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isCurrent
              ? Colors.transparent
              : accent.withValues(alpha: isPassed ? 0.34 : 0.28),
          width: 0.9,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: AppColors.champagneGold.withValues(alpha: 0.32),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: isCurrent
                  ? Colors.white.withValues(alpha: 0.24)
                  : accent.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 10,
              color: isCurrent ? Colors.white : accent,
            ),
          ),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                  color: isCurrent ? Colors.white : accent,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                isCurrent
                    ? 'CURRENT'
                    : isPassed
                    ? 'COMPLETE'
                    : 'UPCOMING',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: isCurrent
                      ? Colors.white.withValues(alpha: 0.85)
                      : accent.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Journal editor bottom sheet
// ───────────────────────────────────────────────────────────────────────────

class _JournalEditorSheet extends StatefulWidget {
  const _JournalEditorSheet({this.existing});

  final JournalEntry? existing;

  @override
  State<_JournalEditorSheet> createState() => _JournalEditorSheetState();
}

class _JournalEditorSheetState extends State<_JournalEditorSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleCtrl = TextEditingController(text: existing?.title ?? '');
    _contentCtrl = TextEditingController(text: existing?.content ?? '');
    _date = existing?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  void _save() {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please write something before saving.')),
      );
      return;
    }
    final entry = JournalEntry(
      date: _date,
      title: _titleCtrl.text.trim(),
      content: content,
      moodRating: widget.existing?.moodRating ?? 3,
      attachedImagePath: widget.existing?.attachedImagePath,
      swellingLevel: widget.existing?.swellingLevel,
    );
    Navigator.of(context).pop(entry);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isEditing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.refinedSlate.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  isEditing ? 'Edit Note' : 'New Note',
                  style: MyApp.sectionTitleStyle(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Title (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(10),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      border: OutlineInputBorder(),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 16,
                          color: AppColors.refinedSlate.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                          style: const TextStyle(color: AppColors.refinedSlate),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _contentCtrl,
                  minLines: 6,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.champagneGold,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(isEditing ? 'Save Changes' : 'Save Note'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
