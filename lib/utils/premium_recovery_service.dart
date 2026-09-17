import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

import '../models/premium_recovery_models.dart';
import '../models/procedure.dart';
import '../models/scan_history.dart';
import '../models/journal_entry.dart';
import 'app_prefs.dart';
import 'app_logger.dart';
import 'ai_intelligence_engine.dart';
import 'backend_config.dart';
import 'procedure_intelligence.dart';
import 'report_service.dart';
// --- Storage keys for AppPrefs ---
const String _reportRecordsKey = 'premium_report_records';
const String _coachMessagesKey = 'premium_coach_messages';
const String _progressInsightsKey = 'premium_progress_insights';
const String _customPlansKey = 'premium_custom_plans';
const String _scarEntriesKey = 'premium_scar_entries';
const String _futurePredictionsKey = 'premium_future_predictions';
const String _smartRemindersKey = 'premium_smart_reminders';
const String _voiceJournalsKey = 'premium_voice_journals';

class PremiumRecoveryService {
  static String _normalizedProcedureType(String? value) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) return '';
    if (normalized.toLowerCase() == 'unknown') return '';
    return normalized;
  }

  static String _resolveProcedureType({
    String? explicit,
    Procedure? activeProcedure,
    List<ScanHistoryEntry>? scans,
    List<Map<String, dynamic>>? procedureEntries,
  }) {
    final direct = _normalizedProcedureType(explicit);
    if (direct.isNotEmpty) return direct;

    final fromActive = _normalizedProcedureType(activeProcedure?.type);
    if (fromActive.isNotEmpty) return fromActive;

    if (scans != null) {
      for (final scan in scans) {
        final fromScan = _normalizedProcedureType(scan.procedure);
        if (fromScan.isNotEmpty) return fromScan;
      }
    }

    if (procedureEntries != null) {
      for (final entry in procedureEntries) {
        final fromEntry = _normalizedProcedureType(entry['type']?.toString());
        if (fromEntry.isNotEmpty) return fromEntry;
      }
    }

    return 'General Skincare';
  }

  // --- Static methods for app screens and persistence ---
  static Future<void> saveProfessionalReportRecords(
    List<dynamic> records,
  ) async {
    await AppPrefs.setString(_reportRecordsKey, jsonEncode(records));
  }

  static Future<List<dynamic>> loadProfessionalReportRecords() async {
    final raw = await AppPrefs.getString(_reportRecordsKey);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List).toList();
  }

  static String _coachMessagesKeyForProcedure(String? procedureId) {
    if (procedureId == null || procedureId.trim().isEmpty) {
      return _coachMessagesKey;
    }
    return '${_coachMessagesKey}_${procedureId.trim()}';
  }

  static Future<void> saveCoachMessages(
    List<dynamic> messages, {
    String? procedureId,
  }) async {
    final key = _coachMessagesKeyForProcedure(procedureId);
    await AppPrefs.setString(key, jsonEncode(messages));
  }

  static Future<List<dynamic>> loadCoachMessages({String? procedureId}) async {
    final key = _coachMessagesKeyForProcedure(procedureId);
    final raw = await AppPrefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List)
        .map((e) => RecoveryCoachMessage.fromJson(e))
        .toList();
  }

  static Future<void> saveProgressInsights(List<dynamic> insights) async {
    await AppPrefs.setString(_progressInsightsKey, jsonEncode(insights));
  }

  static Future<List<dynamic>> loadProgressInsights() async {
    final raw = await AppPrefs.getString(_progressInsightsKey);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List)
        .map((e) => ProgressPhotoInsight.fromJson(e))
        .toList();
  }

  static Future<void> saveCustomPlans(List<dynamic> plans) async {
    await AppPrefs.setString(_customPlansKey, jsonEncode(plans));
  }

  static Future<List<dynamic>> loadCustomPlans() async {
    final raw = await AppPrefs.getString(_customPlansKey);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List)
        .map((e) => CustomRecoveryPlan.fromJson(e))
        .toList();
  }

  static Future<void> saveScarEntries(List<dynamic> entries) async {
    await AppPrefs.setString(_scarEntriesKey, jsonEncode(entries));
  }

  static Future<List<dynamic>> loadScarEntries() async {
    final raw = await AppPrefs.getString(_scarEntriesKey);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List)
        .map((e) => ScarHealingEntry.fromJson(e))
        .toList();
  }

  static Future<void> saveFuturePredictions(List<dynamic> predictions) async {
    await AppPrefs.setString(_futurePredictionsKey, jsonEncode(predictions));
  }

  static Future<List<dynamic>> loadFuturePredictions() async {
    final raw = await AppPrefs.getString(_futurePredictionsKey);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List)
        .map((e) => FutureAppearancePrediction.fromJson(e))
        .toList();
  }

  static Future<void> saveSmartReminders(List<dynamic> reminders) async {
    await AppPrefs.setString(_smartRemindersKey, jsonEncode(reminders));
  }

  static Future<List<dynamic>> loadSmartReminders() async {
    final raw = await AppPrefs.getString(_smartRemindersKey);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List)
        .map((e) => SmartReminderPrediction.fromJson(e))
        .toList();
  }

  static Future<void> saveVoiceJournals(List<dynamic> journals) async {
    await AppPrefs.setString(_voiceJournalsKey, jsonEncode(journals));
  }

  static Future<List<dynamic>> loadVoiceJournals() async {
    final raw = await AppPrefs.getString(_voiceJournalsKey);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List)
        .map((e) => VoiceJournalEntry.fromJson(e))
        .toList();
  }

  // --- Stubs for missing static methods referenced in screens ---
  static Future<dynamic> autoGenerateFuturePredictionFromHistory(
    List<dynamic> sorted,
  ) async {
    // TODO: Implement actual logic
    return null;
  }

  static Future<dynamic> buildSmartRemindersFromLatestScan(
    List<dynamic> sorted,
  ) async {
    // TODO: Implement actual logic
    return null;
  }

  static Future<List<int>> generateProfessionalReportPdfBytes({
    required dynamic procedure,
    required List<dynamic> scans,
    required List<dynamic> journalEntries,
    required List<dynamic> milestones,
    required List<dynamic> reminders,
    required List<dynamic> insights,
    required List<dynamic> plans,
    required List<dynamic> scarEntries,
    required List<dynamic> voiceJournals,
    required String? surgeonNotes,
    required String? patientName,
    required String? procedureType,
    required DateTime? startDate,
    String? userName,
  }) async {
    final resolvedProcedureType = _resolveProcedureType(
      explicit: procedureType,
      activeProcedure: procedure is Procedure ? procedure : null,
    );
    AppLogger.verbose(
      '[PremiumRecoveryService.generateProfessionalReportPdfBytes] resolvedProcedureType=$resolvedProcedureType',
    );
    // Delegate to the canonical ReportService so all callers get a real PDF.
    try {
      final proc = procedure is Procedure
          ? procedure
          : Procedure.fromJson(Map<String, dynamic>.from(procedure as Map));
      final typedScans = scans.whereType<ScanHistoryEntry>().toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final typedInsights = insights.whereType<ProgressPhotoInsight>().toList();
      final typedMilestones = milestones
          .whereType<ProcedureTimelineMilestone>()
          .toList();

      final input = ReportInput(
        procedure: proc,
        scans: typedScans,
        insights: typedInsights,
        surgeonNotes: (surgeonNotes ?? '').trim().isEmpty
            ? null
            : surgeonNotes!.trim(),
        patientName: (patientName ?? userName ?? '').trim().isEmpty
            ? null
            : (patientName ?? userName)!.trim(),
        customPlanMilestones: typedMilestones,
      );

      // Build PDF only (do not double-save the record — callers manage that).
      final result = await ReportService.generateAndSave(input);
      return result.pdfBytes.toList();
    } catch (e) {
      return <int>[];
    }
  }

  static Future<ProgressPhotoInsight?> autoAnalyzeLatestProgressFromHistory(
    List<ScanHistoryEntry> sortedHistory,
  ) async {
    final resolvedProcedureType = _resolveProcedureType(scans: sortedHistory);
    AppLogger.verbose(
      '[PremiumRecoveryService.autoAnalyzeLatestProgressFromHistory] resolvedProcedureType=$resolvedProcedureType',
    );
    if (sortedHistory.length < 2) {
      return null;
    }
    final chronological = List<ScanHistoryEntry>.from(sortedHistory)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final baseline = chronological.first;
    final latest = chronological.last;
    if (baseline.id == latest.id) {
      return null;
    }
    final insight = _buildProgressInsight(
      latest: latest,
      baseline: baseline,
      procedureType: latest.procedure,
      productName: latest.productName,
    );
    final current = await loadProgressInsights();
    final deduped = current.where((e) => e.latestScanId != latest.id).toList();
    deduped.insert(0, insight);
    await saveProgressInsights(deduped.take(40).toList());
    return insight;
  }

  static ProgressPhotoInsight _buildProgressInsight({
    required ScanHistoryEntry latest,
    required ScanHistoryEntry baseline,
    String? procedureType,
    String? productName,
  }) {
    final latestMetrics = latest.toSkinMetrics();
    final baselineMetrics = baseline.toSkinMetrics();

    double pctChangeLowIsBetter(double oldV, double newV) {
      if (oldV.abs() < 0.01) return 0;
      return ((oldV - newV) / oldV) * 100;
    }

    double pctChangeHighIsBetter(double oldV, double newV) {
      if (oldV.abs() < 0.01) return 0;
      return ((newV - oldV) / oldV) * 100;
    }

    final swellingDelta = pctChangeLowIsBetter(
      baselineMetrics.redness,
      latestMetrics.redness,
    );
    final textureDelta = pctChangeLowIsBetter(
      baselineMetrics.texture,
      latestMetrics.texture,
    );
    final wrinkleDelta = pctChangeLowIsBetter(
      baselineMetrics.wrinkle,
      latestMetrics.wrinkle,
    );
    final contourDelta = pctChangeHighIsBetter(
      baselineMetrics.elasticity,
      latestMetrics.elasticity,
    );

    final positiveScores = [
      swellingDelta,
      textureDelta,
      wrinkleDelta,
      contourDelta,
    ].map((e) => e.isFinite ? e : 0).toList();

    final avg = positiveScores.reduce((a, b) => a + b) / positiveScores.length;
    final direction = avg >= 0 ? 'improved' : 'mildly regressed';
    final pct = avg.abs().round();

    final highlights = <String>[
      '${ProcedureIntelligence.metricLabel('redness', procedureType)} trend: ${swellingDelta >= 0 ? 'down' : 'up'} by ${swellingDelta.abs().round()}%',
      '${ProcedureIntelligence.metricLabel('texture', procedureType)} trend: ${textureDelta >= 0 ? 'smoother' : 'rougher'} by ${textureDelta.abs().round()}%',
      '${ProcedureIntelligence.metricLabel('wrinkle', procedureType)} trend: ${wrinkleDelta >= 0 ? 'reduced' : 'increased'} by ${wrinkleDelta.abs().round()}%',
      '${ProcedureIntelligence.metricLabel('elasticity', procedureType)} trend: ${contourDelta >= 0 ? 'better definition' : 'less defined'} by ${contourDelta.abs().round()}%',
    ];

    final scope = (procedureType ?? '').trim().isNotEmpty
        ? procedureType!.trim()
        : ((productName ?? '').trim().isNotEmpty
              ? productName!.trim()
              : 'your treatment area');

    return ProgressPhotoInsight(
      id: premiumEntityId('insight'),
      summary:
          '$scope appears $direction by about $pct% vs your baseline photo.',
      highlights: highlights,
      createdAt: DateTime.now(),
      procedureType: procedureType,
      productName: productName,
      latestScanId: latest.id,
      // Backward-compatible field used as baseline anchor.
      previousScanId: baseline.id,
    );
  }

  static Future<CustomRecoveryPlan> buildCustomPlanFromNotes({
    required String notes,
    required String procedureType,
    required DateTime startDate,
    String? uploadedInstructionImageRef,
  }) async {
    final resolvedProcedureType = _resolveProcedureType(explicit: procedureType);
    AppLogger.verbose(
      '[PremiumRecoveryService.buildCustomPlanFromNotes] resolvedProcedureType=$resolvedProcedureType',
    );
    final parsedMilestones = _extractMilestonesFromNotes(
      notes: notes,
      startDate: startDate,
    );

    final milestones = parsedMilestones.isNotEmpty
        ? parsedMilestones
        : _defaultFallbackMilestones(startDate, procedureType: procedureType);

    return CustomRecoveryPlan(
      id: premiumEntityId('plan'),
      title: 'Custom Recovery Plan',
      procedureType: resolvedProcedureType,
      surgeonNotes: notes.trim(),
      startDate: startDate,
      timelineMilestones: milestones,
      createdAt: DateTime.now(),
      uploadedInstructionImageRef: uploadedInstructionImageRef,
    );
  }

  static List<ProcedureTimelineMilestone> _defaultFallbackMilestones(
    DateTime startDate, {
    String? procedureType,
  }) {
    // Delegate to ProcedureIntelligence for procedure-specific milestones.
    if (procedureType != null && procedureType.trim().isNotEmpty) {
      final milestones = ProcedureIntelligence.defaultMilestones(
        procedureType,
        startDate,
      );
      if (milestones.isNotEmpty) return milestones;
    }
    // Generic fallback if procedure type is unknown
    final normalized = DateTime(startDate.year, startDate.month, startDate.day);
    final ranges = <({String label, int offset, String desc})>[
      (
        label: 'Day 1-3',
        offset: 3,
        desc:
            'Initial swelling and tenderness can be common. Prioritize gentle aftercare and rest.',
      ),
      (
        label: 'Week 1',
        offset: 7,
        desc:
            'Early inflammation usually starts settling. Keep following your provider instructions.',
      ),
      (
        label: 'Week 2-3',
        offset: 21,
        desc:
            'Visible healing trend should continue. Keep photo and symptom tracking consistent.',
      ),
      (
        label: 'Month 1',
        offset: 30,
        desc: 'Early contour/texture improvements become easier to evaluate.',
      ),
      (
        label: 'Month 3',
        offset: 90,
        desc:
            'Further tissue remodeling and refinement are often more noticeable.',
      ),
    ];
    return ranges.asMap().entries.map((entry) {
      final item = entry.value;
      return ProcedureTimelineMilestone(
        id: premiumEntityId('ms_default'),
        label: item.label,
        description: item.desc,
        expectedDate: normalized.add(Duration(days: item.offset)),
        displayOrder: entry.key,
      );
    }).toList();
  }

  static List<ProcedureTimelineMilestone> _extractMilestonesFromNotes({
    required String notes,
    required DateTime startDate,
  }) {
    final lines = notes
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final milestones = <ProcedureTimelineMilestone>[];
    var index = 0;

    final dayRegex = RegExp(r'(day\s*\d+|\d+\s*day)', caseSensitive: false);
    final weekRegex = RegExp(r'(week\s*\d+|\d+\s*week)', caseSensitive: false);
    final monthRegex = RegExp(
      r'(month\s*\d+|\d+\s*month)',
      caseSensitive: false,
    );

    int? offsetDaysFromLine(String line) {
      final lower = line.toLowerCase();

      final dayMatch = dayRegex.firstMatch(lower);
      if (dayMatch != null) {
        final n = int.tryParse(
          dayMatch.group(0)!.replaceAll(RegExp(r'[^0-9]'), ''),
        );
        if (n != null) return n;
      }

      final weekMatch = weekRegex.firstMatch(lower);
      if (weekMatch != null) {
        final n = int.tryParse(
          weekMatch.group(0)!.replaceAll(RegExp(r'[^0-9]'), ''),
        );
        if (n != null) return n * 7;
      }

      final monthMatch = monthRegex.firstMatch(lower);
      if (monthMatch != null) {
        final n = int.tryParse(
          monthMatch.group(0)!.replaceAll(RegExp(r'[^0-9]'), ''),
        );
        if (n != null) return n * 30;
      }

      if (lower.contains('today') || lower.contains('immediately')) return 0;
      return null;
    }

    for (final line in lines) {
      final offset = offsetDaysFromLine(line);
      if (offset == null) continue;
      final expectedDate = DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
      ).add(Duration(days: offset));

      milestones.add(
        ProcedureTimelineMilestone(
          id: premiumEntityId('ms'),
          label: 'Day $offset',
          description: line,
          expectedDate: expectedDate,
          displayOrder: index,
        ),
      );
      index += 1;
    }

    return milestones;
  }

  static Future<String> generateRecoveryCoachReply({
    required String question,
    bool hasImageAttachment = false,
    Procedure? activeProcedure,
    List<ScanHistoryEntry>? scopedScans,
  }) async {
    final userName = await AppPrefs.getUserName();
    final appProcedureType = await AppPrefs.getProcedureType();
    final procedure =
        activeProcedure ?? await _resolveActiveProcedureFromPrefs();
    final scans = scopedScans ?? await _loadScansScopedToProcedure(procedure);
    final procedures = await AppPrefs.getProcedureEntries();
    final generalJournalEntries = await AppPrefs.getGeneralJournalEntries();
    final procedureType = _resolveProcedureType(
      explicit: appProcedureType,
      activeProcedure: procedure,
      scans: scans,
      procedureEntries: procedures,
    );
    AppLogger.verbose(
      '[PremiumRecoveryService.generateRecoveryCoachReply] resolvedProcedureType=$procedureType',
    );
    final journalsRaw = await AppPrefs.getString('skincare_journal_entries');

    final context = _buildCoachContext(
      procedure: procedure,
      scans: scans,
      procedures: procedures,
      skincareJournalRaw: journalsRaw,
      generalJournalEntries: generalJournalEntries,
    );
    final day = procedure?.startDate == null
        ? 0
        : (DateTime.now()
                  .difference(
                    DateTime(
                      procedure!.startDate.year,
                      procedure.startDate.month,
                      procedure.startDate.day,
                    ),
                  )
                  .inDays +
              1)
              .clamp(1, 999);
    final scanData = scans.take(5).map((scan) {
      final metrics = scan.toSkinMetrics();
      return <String, dynamic>{
        'id': scan.id,
        'timestamp': scan.timestamp.toIso8601String(),
        'procedure': (scan.procedure ?? '').trim(),
        'procedureId': (scan.procedureId ?? '').trim(),
        'scanType': scan.resolvedScanType,
        'metrics': {
          'redness': metrics.redness,
          'texture': metrics.texture,
          'wrinkle': metrics.wrinkle,
          'pore': metrics.pore,
          'darkSpots': metrics.darkSpots,
          'elasticity': metrics.elasticity,
        },
      };
    }).toList();

    final requestBody = <String, dynamic>{
      'prompt': question,
      'procedure': procedureType,
      'day': day,
      'scanData': scanData,
      'hasImageAttachment': hasImageAttachment,
      'context': '${procedureType.trim()} - Day $day',
      'userName': userName,
      'contextSummary': context.summaryForPrompt,
    };

    final endpoints = <Uri>[
      BackendConfig.buildUri('/api/ai-coach'),
      BackendConfig.aiCoachUri,
    ];

    final client = http.Client();
    try {
      String? lastError;

      for (final endpoint in endpoints) {
        try {
          final response = await client
              .post(
                endpoint,
                headers: const {'Content-Type': 'application/json'},
                body: jsonEncode(requestBody),
              )
              .timeout(const Duration(seconds: 25));

          Map<String, dynamic> body = const <String, dynamic>{};
          if (response.body.trim().isNotEmpty) {
            final decoded = jsonDecode(response.body);
            if (decoded is Map<String, dynamic>) {
              body = decoded;
            }
          }

          if (response.statusCode < 200 || response.statusCode >= 300) {
            final message =
                body['error']?.toString() ??
                body['message']?.toString() ??
                'Backend request failed with HTTP ${response.statusCode}.';
            lastError = message;
            continue;
          }

          final reply =
              body['reply']?.toString().trim() ??
              body['message']?.toString().trim() ??
              body['text']?.toString().trim() ??
              '';
          if (reply.isEmpty) {
            lastError = 'Backend returned an empty coach reply.';
            continue;
          }

          return _ensureSafetyDisclaimer(reply);
        } on TimeoutException {
          lastError = 'AI Recovery Coach request timed out.';
        } catch (e) {
          lastError = e.toString();
        }
      }

      throw Exception(
        lastError ?? 'Unable to reach AI Recovery Coach backend endpoint.',
      );
    } finally {
      client.close();
    }
  }

  static String _fallbackCoachReply({
    required String question,
    required _CoachContextSnapshot context,
    required _UserAffect affect,
  }) {
    final q = question.toLowerCase();
    final procedure = context.procedureType;

    if (q.contains('left side') ||
        q.contains('one side') ||
        q.contains('asymmetr')) {
      return _composeStructuredReply(
        affect: affect,
        context: context,
        reassuranceTail:
            'Mild side-to-side swelling can be completely normal at this point after $procedure.',
        explanation:
            'Based on your stage and trend, uneven fluid settling can happen even when healing is progressing well.',
        actions:
            'Take one same-angle photo now and another tomorrow in similar lighting, keep head position consistent, and continue your surgeon-approved swelling routine.',
        surgeonGuidance:
            'Contact your surgeon promptly if one side is rapidly worsening, or if you notice significant pain, warmth, redness, drainage, fever, or new firmness.',
      );
    }

    if (q.contains('scar') && (q.contains('itch') || q.contains('itching'))) {
      return _composeStructuredReply(
        affect: affect,
        context: context,
        reassuranceTail:
            'Mild itching is very common during scar remodeling and usually settles gradually.',
        explanation:
            'At your current recovery stage, itch can reflect normal tissue healing, but it should not intensify day after day.',
        actions:
            'Keep the area moisturized with surgeon-approved products, avoid scratching, and log itch severity today so your trend is easier to interpret.',
        surgeonGuidance:
            'Contact your surgeon if itching is worsening or paired with spreading redness, heat, rash, drainage, or increasing pain.',
      );
    }

    if (q.contains('makeup') &&
        procedure.toLowerCase().contains('rhinoplasty')) {
      return _composeStructuredReply(
        affect: affect,
        context: context,
        reassuranceTail:
            'You are asking exactly the kind of question that protects long-term rhinoplasty results.',
        explanation:
            'Makeup readiness after rhinoplasty is usually driven by incision healing and skin sensitivity, not a single fixed day.',
        actions:
            'Ask your clinic for explicit clearance based on your current day/week, then use only clean, gentle products once cleared.',
        surgeonGuidance:
            'Avoid makeup on irritated or unhealed skin, and contact your surgeon if redness, stinging, or swelling increases after product use.',
      );
    }

    if (q.contains('swelling')) {
      return _composeStructuredReply(
        affect: affect,
        context: context,
        reassuranceTail:
            'Some day-to-day swelling fluctuation is very common, even when recovery is on track.',
        explanation:
            'Your current pattern suggests expected variation for this stage, as long as the overall trend is stable or improving.',
        actions:
            'Continue your provider-approved swelling care, hydrate, prioritize rest tonight, and compare tomorrow\'s scan/photo under the same angle and lighting.',
        surgeonGuidance:
            'Reach out to your surgeon quickly for rapidly increasing swelling, one-sided severe pain, fever, warmth, progressive redness, or worsening firmness.',
      );
    }

    if (q.contains('makeup')) {
      return _composeStructuredReply(
        affect: affect,
        context: context,
        reassuranceTail:
            'Being cautious with product timing is one of the best ways to protect healing quality.',
        explanation:
            'Readiness is usually based on barrier recovery and surgeon protocol rather than calendar date alone.',
        actions:
            'Wait until sensitive areas are fully settled, patch-test gentle products if approved, and confirm exact timing with your clinic.',
        surgeonGuidance:
            'Stop products and contact your surgeon if you notice burning, increased redness, or swelling flare after application.',
      );
    }

    return _composeStructuredReply(
      affect: affect,
      context: context,
      reassuranceTail:
          'You are doing well by staying consistent with your recovery tracking.',
      explanation:
          'Your recent data suggests a recovery pattern that can be monitored safely with continued trend-based follow-up.',
      actions:
          'Keep daily symptom notes and consistent same-angle scans, and set one comfort-focused goal today (hydration, rest, or gentle aftercare adherence).',
      surgeonGuidance:
          'Contact your surgeon if pain, swelling, redness, warmth, drainage, or asymmetry is clearly worsening instead of stabilizing.',
    );
  }

  static String _composeStructuredReply({
    required _UserAffect affect,
    required _CoachContextSnapshot context,
    required String reassuranceTail,
    required String explanation,
    required String actions,
    required String surgeonGuidance,
  }) {
    final reassurance = _reassuranceForAffect(affect);
    final contextAnchor = _buildContextAnchor(context);
    final styleTip = _styleTipForAffect(affect);

    final sec1 = _cap2('$reassurance $reassuranceTail');
    final sec2 = _cap2('$contextAnchor $explanation');
    final sec3 = _cap2('$actions $styleTip');
    final sec4 = _cap2(surgeonGuidance);

    return 'Reassurance: $sec1\n\n'
        'What this likely means: $sec2\n\n'
        'What to do today: $sec3\n\n'
        'When to contact your surgeon: $sec4';
  }

  /// Trims [text] to at most [maxSentences] sentences.
  static String _cap2(String text, [int maxSentences = 2]) {
    final trimmed = text.trim();
    // Split on sentence-ending punctuation followed by a space or end-of-string.
    final sentenceEnds = RegExp(r'(?<=[.!?])\s+');
    final parts = trimmed.split(sentenceEnds);
    if (parts.length <= maxSentences) return trimmed;
    // Re-join the first N parts preserving the original punctuation.
    var end = 0;
    var count = 0;
    for (var i = 0; i < trimmed.length; i++) {
      final ch = trimmed[i];
      if (ch == '.' || ch == '!' || ch == '?') {
        end = i;
        count++;
        if (count == maxSentences) break;
      }
    }
    if (end == 0) return trimmed; // no sentence boundary found
    return trimmed.substring(0, end + 1).trim();
  }

  static String _buildContextAnchor(_CoachContextSnapshot context) {
    final points = <String>[
      'You are around recovery day ${context.recoveryDay} (week ${context.recoveryWeek}).',
      context.swellingTrendLine,
      context.timelineStageLine,
      context.consistencyLine,
      context.journalHighlightsLine,
    ];

    final selected = <String>[];
    for (final item in points) {
      final normalized = item.toLowerCase();
      if (normalized.contains('no ') || normalized.contains('unavailable')) {
        continue;
      }
      selected.add(item);
      if (selected.length == 3) break;
    }

    if (selected.isEmpty) {
      return 'Your latest tracked recovery context is limited, so we should use careful daily comparisons.';
    }
    return selected.join(' ');
  }

  static _UserAffect _inferUserAffect(String question) {
    final q = question.toLowerCase();

    const anxiousSignals = {
      'scared': 3,
      'worried': 2,
      'anxious': 3,
      'panic': 3,
      'is this bad': 2,
      'urgent': 2,
      'afraid': 3,
      'concerned': 2,
      'normal?': 1,
    };
    const frustratedSignals = {
      'not improving': 3,
      'worse': 2,
      'frustrated': 3,
      'annoyed': 2,
      'upset': 2,
      'still swollen': 2,
      'nothing is working': 3,
      'why is this not': 2,
    };
    const positiveSignals = {
      'better': 2,
      'improving': 2,
      'happy': 2,
      'great': 1,
      'thank you': 2,
      'feels better': 2,
      'healing beautifully': 3,
    };

    int scoreFor(Map<String, int> lexicon) {
      var score = 0;
      for (final entry in lexicon.entries) {
        if (q.contains(entry.key)) score += entry.value;
      }
      return score;
    }

    var anxious = scoreFor(anxiousSignals);
    final frustrated = scoreFor(frustratedSignals);
    final positive = scoreFor(positiveSignals);

    if (q.contains('!!!')) anxious += 2;
    if (q.contains('!!')) anxious += 1;

    if (anxious >= frustrated && anxious >= positive && anxious >= 2) {
      return const _UserAffect(_AffectKind.anxious, 'anxious');
    }
    if (frustrated > anxious && frustrated >= positive && frustrated >= 2) {
      return const _UserAffect(_AffectKind.frustrated, 'frustrated');
    }
    if (positive > anxious && positive > frustrated && positive >= 2) {
      return const _UserAffect(_AffectKind.positive, 'positive');
    }
    return const _UserAffect(_AffectKind.practical, 'practical');
  }

  static String _reassuranceForAffect(_UserAffect affect) {
    switch (affect.kind) {
      case _AffectKind.anxious:
        return 'I know this part can feel scary, and you are absolutely doing the right thing by checking in.';
      case _AffectKind.frustrated:
        return 'I know this part can be really frustrating, and your feelings make complete sense.';
      case _AffectKind.positive:
        return 'You are doing so well staying consistent, and that really supports confident healing decisions.';
      case _AffectKind.practical:
        return 'You are asking a smart, well-timed question for this stage of healing.';
    }
  }

  static String _styleTipForAffect(_UserAffect affect) {
    switch (affect.kind) {
      case _AffectKind.anxious:
        return 'Take this one step at a time and focus on 24-hour trend changes rather than moment-to-moment shifts.';
      case _AffectKind.frustrated:
        return 'Use a simple 48-hour comparison to judge progress so normal short-term fluctuations feel less discouraging.';
      case _AffectKind.positive:
        return 'Keep this same consistent rhythm, because steady routines usually give the clearest recovery trend.';
      case _AffectKind.practical:
        return 'Keep one reliable daily check-in so your trend data stays clean and useful.';
    }
  }

  static String _ensureSafetyDisclaimer(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return 'This is general guidance, not a diagnosis. Please follow your surgeon\'s instructions first.';
    }

    final lower = trimmed.toLowerCase();
    final hasGeneralGuidance = lower.contains('general guidance');
    final hasDiagnosis = lower.contains('not a diagnosis');
    final hasSurgeon = lower.contains('surgeon') || lower.contains('provider');
    if (hasGeneralGuidance && hasDiagnosis && hasSurgeon) {
      return trimmed;
    }

    return '$trimmed\n\nThis is general guidance, not a diagnosis. Please follow your surgeon\'s instructions first.';
  }

  static Future<Procedure?> _resolveActiveProcedureFromPrefs() async {
    final entries = await AppPrefs.getProcedureEntries();
    if (entries.isEmpty) return null;

    final selectedId = await AppPrefs.getSelectedProcedureIdOrNull();
    if (selectedId != null && selectedId.trim().isNotEmpty) {
      for (final item in entries) {
        final id = (item['id'] ?? item['procedureId'] ?? '').toString().trim();
        if (id == selectedId.trim()) {
          return Procedure.fromJson(Map<String, dynamic>.from(item));
        }
      }
    }

    return Procedure.fromJson(Map<String, dynamic>.from(entries.first));
  }

  static Future<List<ScanHistoryEntry>> _loadScansScopedToProcedure(
    Procedure? procedure,
  ) async {
    final allScans = await AppPrefs.getScanEntries();
    final sorted = List<ScanHistoryEntry>.from(allScans)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (procedure == null) return sorted;

    final scoped = sorted
        .where((scan) => (scan.procedureId ?? '').trim() == procedure.id)
        .toList();
    return scoped.isNotEmpty ? scoped : sorted;
  }

  static _CoachContextSnapshot _buildCoachContext({
    required Procedure? procedure,
    required List<ScanHistoryEntry> scans,
    required List<Map<String, dynamic>> procedures,
    required String? skincareJournalRaw,
    required List<JournalEntry> generalJournalEntries,
  }) {
    final procedureType = (procedure?.type ?? 'your procedure').trim().isEmpty
        ? 'your procedure'
        : procedure!.type.trim();

    final swellingEntries =
        (procedure?.journalEntries ?? const [])
            .where((entry) => entry.swellingLevel != null)
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    final recoveryDay = procedure == null
        ? 1
        : DateTime.now()
                  .difference(
                    DateTime(
                      procedure.startDate.year,
                      procedure.startDate.month,
                      procedure.startDate.day,
                    ),
                  )
                  .inDays +
              1;

    String swellingTrendLine;
    if (swellingEntries.isEmpty) {
      swellingTrendLine = 'No swelling log entries yet.';
    } else if (swellingEntries.length == 1) {
      final latest = swellingEntries.last.swellingLevel!;
      swellingTrendLine =
          'Latest swelling is $latest/10 (${swellingEntries.length} entry tracked).';
    } else {
      final latest = swellingEntries.last.swellingLevel!;
      final previous =
          swellingEntries[swellingEntries.length - 2].swellingLevel!;
      final direction = latest < previous
          ? 'trending down'
          : latest > previous
          ? 'trending up'
          : 'currently stable';
      swellingTrendLine =
          'Swelling is $direction (latest $latest/10, previous $previous/10).';
    }

    String scanLine;
    String consistencyLine;
    if (scans.isEmpty) {
      scanLine = 'No scan history available yet.';
      consistencyLine =
          'Consistency score is unavailable yet because there are no recent scans.';
    } else {
      final latest = scans.first;
      final poseSimilarity = latest.metrics['capture_pose_similarity'];
      final landmarkQuality = latest.metrics['capture_landmark_quality'];
      final consistencyScore = latest.metrics['consistency_score'];
      final qualityBits = <String>[];
      if (poseSimilarity != null) {
        qualityBits.add('pose similarity ${poseSimilarity.round()}%');
      }
      if (landmarkQuality != null) {
        qualityBits.add('landmark quality ${(landmarkQuality * 100).round()}%');
      }
      if (latest.lightingConfidence != null) {
        qualityBits.add(
          'lighting ${(latest.lightingConfidence! * 100).round()}%',
        );
      }
      final qualitySummary = qualityBits.isEmpty
          ? 'quality metrics limited'
          : qualityBits.join(', ');
      scanLine =
          '${scans.length} recovery scans available; latest capture has $qualitySummary.';

      if (consistencyScore != null) {
        consistencyLine =
            'Recent capture consistency is ${(consistencyScore * 100).round()}%, which helps trend confidence.';
      } else if (poseSimilarity is num || landmarkQuality is num) {
        consistencyLine =
            'Recent scan consistency appears usable for trend review, though not fully scored.';
      } else {
        consistencyLine =
            'Recent scan consistency is limited; comparisons may be less precise.';
      }
    }

    final timelineMilestones =
        procedure?.timelineMilestones ?? const <ProcedureTimelineMilestone>[];
    final now = DateTime.now();
    String timelineStageLine;
    String timelineProgressLine;
    if (timelineMilestones.isEmpty) {
      timelineStageLine = 'No timeline milestones saved.';
      timelineProgressLine =
          'Timeline progress cannot be estimated without milestones.';
    } else {
      final sortedMilestones = List<ProcedureTimelineMilestone>.from(
        timelineMilestones,
      )..sort((a, b) => a.expectedDate.compareTo(b.expectedDate));
      ProcedureTimelineMilestone? next;
      for (final item in sortedMilestones) {
        if (!item.expectedDate.isBefore(now)) {
          next = item;
          break;
        }
      }
      final active = next ?? sortedMilestones.last;
      timelineStageLine =
          'Recovery timeline focus: ${active.label} (${DateFormat('MMM d').format(active.expectedDate)}).';

      final firstDate = sortedMilestones.first.expectedDate;
      final lastDate = sortedMilestones.last.expectedDate;
      final totalSpanDays = lastDate.difference(firstDate).inDays;
      if (totalSpanDays <= 0) {
        timelineProgressLine =
            'Timeline progress is in an early calibration phase.';
      } else {
        final elapsed = now
            .difference(firstDate)
            .inDays
            .clamp(0, totalSpanDays);
        final progressPct = ((elapsed / totalSpanDays) * 100).round();
        timelineProgressLine =
            'You are about $progressPct% through your planned recovery timeline.';
      }
    }

    final procedureSummary = procedures.isEmpty
        ? 'No active procedure records.'
        : procedures
              .take(3)
              .map((p) {
                final type = (p['type'] ?? 'Procedure').toString();
                final notes = (p['notes'] ?? '').toString().trim();
                return '$type${notes.isEmpty ? '' : ' ($notes)'}';
              })
              .join('; ');

    final journalSummary = (skincareJournalRaw ?? '').trim().isEmpty
        ? 'No skincare journal notes found.'
        : 'Skincare journal entries are available.';

    final recentProcedureJournal =
        (procedure?.journalEntries ?? const [])
            .where(
              (entry) =>
                  entry.content.trim().isNotEmpty ||
                  entry.title.trim().isNotEmpty,
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final journalLine = recentProcedureJournal.isEmpty
        ? 'No procedure journal notes captured yet.'
        : 'Recent journal note: ${recentProcedureJournal.first.title.isEmpty ? recentProcedureJournal.first.content : recentProcedureJournal.first.title}.';

    final recentJournalHighlights = recentProcedureJournal
        .take(2)
        .map(
          (entry) => entry.title.trim().isNotEmpty
              ? entry.title.trim()
              : entry.content.trim(),
        )
        .where((text) => text.isNotEmpty)
        .toList();
    final journalHighlightsLine = recentJournalHighlights.isEmpty
        ? 'No additional recent journal highlights.'
        : 'Recent journal highlights: ${recentJournalHighlights.join(' | ')}.';

    final recentUserJournalNotes = generalJournalEntries
        .where(
          (entry) =>
              entry.content.trim().isNotEmpty || entry.title.trim().isNotEmpty,
        )
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final generalJournalLine = recentUserJournalNotes.isEmpty
        ? 'No recent general journal notes.'
        : 'Recent user journal notes: ${recentUserJournalNotes.take(3).map((entry) => entry.content.trim().isNotEmpty ? entry.content.trim() : entry.title.trim()).where((text) => text.isNotEmpty).join(' | ')}.';

    // Build AI metric context from scan data
    final scanMetricContext = AiIntelligenceEngine.buildCoachMetricContext(
      scans: scans,
      procedureType: procedure?.type,
    );

    return _CoachContextSnapshot(
      procedureType: procedureType,
      recoveryDay: recoveryDay < 1 ? 1 : recoveryDay,
      recoveryWeek: (((recoveryDay < 1 ? 1 : recoveryDay) - 1) ~/ 7) + 1,
      swellingTrendLine: swellingTrendLine,
      scanLine: scanLine,
      consistencyLine: consistencyLine,
      timelineStageLine: timelineStageLine,
      timelineProgressLine: timelineProgressLine,
      procedureSummary: procedureSummary,
      journalSummary: journalSummary,
      procedureJournalLine: journalLine,
      journalHighlightsLine: journalHighlightsLine,
      generalJournalLine: generalJournalLine,
      scanMetricContext: scanMetricContext,
    );
  }
}

enum _AffectKind { anxious, practical, frustrated, positive }

class _UserAffect {
  const _UserAffect(this.kind, this.label);

  final _AffectKind kind;
  final String label;
}

class _CoachContextSnapshot {
  const _CoachContextSnapshot({
    required this.procedureType,
    required this.recoveryDay,
    required this.recoveryWeek,
    required this.swellingTrendLine,
    required this.scanLine,
    required this.consistencyLine,
    required this.timelineStageLine,
    required this.timelineProgressLine,
    required this.procedureSummary,
    required this.journalSummary,
    required this.procedureJournalLine,
    required this.journalHighlightsLine,
    required this.generalJournalLine,
    this.scanMetricContext,
  });

  final String procedureType;
  final int recoveryDay;
  final int recoveryWeek;
  final String swellingTrendLine;
  final String scanLine;
  final String consistencyLine;
  final String timelineStageLine;
  final String timelineProgressLine;
  final String procedureSummary;
  final String journalSummary;
  final String procedureJournalLine;
  final String journalHighlightsLine;
  final String generalJournalLine;
  final String? scanMetricContext;

  String get summaryForPrompt {
    return [
      'Procedure type: $procedureType',
      'Recovery day: $recoveryDay',
      'Recovery week: $recoveryWeek',
      scanLine,
      consistencyLine,
      swellingTrendLine,
      timelineStageLine,
      timelineProgressLine,
      procedureJournalLine,
      journalHighlightsLine,
      generalJournalLine,
      'Procedure records: $procedureSummary',
      journalSummary,
      if (scanMetricContext != null && scanMetricContext!.isNotEmpty)
        '\nSkin metric analysis:\n$scanMetricContext',
    ].join('\n');
  }
}
