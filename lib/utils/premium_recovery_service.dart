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
import 'trend_label_resolver.dart';

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

    final trendStatus = trendStatusMapFromRawPayload(latest.rawPayload);
    final trendLockReasons = trendLockReasonMapFromRawPayload(
      latest.rawPayload,
    );

    ResolvedTrendLabel? trendFor(String key) {
      final canonicalKey = shortMetricKeyToCanonical[key];
      return resolveTrendLabel(
        trendStatus: canonicalKey == null ? null : trendStatus[canonicalKey],
        trendLockReason: canonicalKey == null
            ? null
            : trendLockReasons[canonicalKey],
      );
    }

    String directionWord(ResolvedTrendLabel? trend, String fallback) {
      if (trend == null || trend.isInsufficientSignal) return 'tracking';
      if (trend.isImproved) return 'improving';
      if (trend.isWorsened) return 'worsening';
      return trend.lockShortLabel ?? fallback;
    }

    final metricTrends = [
      trendFor('redness'),
      trendFor('texture'),
      trendFor('wrinkle'),
      trendFor('elasticity'),
    ];
    final improvedCount = metricTrends
        .where((trend) => trend?.isImproved ?? false)
        .length;
    final worsenedCount = metricTrends
        .where((trend) => trend?.isWorsened ?? false)
        .length;
    final direction = improvedCount > worsenedCount && improvedCount > 0
        ? 'improving'
        : worsenedCount > improvedCount && worsenedCount > 0
        ? 'worsening'
        : 'tracking';
    final pct =
        ((swellingDelta.abs() +
                    textureDelta.abs() +
                    wrinkleDelta.abs() +
                    contourDelta.abs()) /
                4)
            .round();

    final highlights = <String>[
      '${ProcedureIntelligence.metricLabel('redness', procedureType)} trend: ${directionWord(trendFor('redness'), 'stable')} by ${swellingDelta.abs().round()}%',
      '${ProcedureIntelligence.metricLabel('texture', procedureType)} trend: ${directionWord(trendFor('texture'), 'stable')} by ${textureDelta.abs().round()}%',
      '${ProcedureIntelligence.metricLabel('wrinkle', procedureType)} trend: ${directionWord(trendFor('wrinkle'), 'stable')} by ${wrinkleDelta.abs().round()}%',
      '${ProcedureIntelligence.metricLabel('elasticity', procedureType)} trend: ${directionWord(trendFor('elasticity'), 'stable')} by ${contourDelta.abs().round()}%',
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
    final resolvedProcedureType = _resolveProcedureType(
      explicit: procedureType,
    );
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
    final scanData = AiIntelligenceEngine.buildAiScanContext(
      scans: scans.take(5).toList(),
    );

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
                headers: {
                  'Content-Type': 'application/json',
                  ...BackendConfig.apiKeyHeaders,
                },
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
    return scopeScansToProcedure(allScans, procedure);
  }

  static List<ScanHistoryEntry> scopeScansToProcedure(
    List<ScanHistoryEntry> scans,
    Procedure? procedure,
  ) {
    final sorted = List<ScanHistoryEntry>.from(scans)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (procedure == null) {
      AppLogger.verbose(
        '[PremiumRecoveryService] no active procedure; sending zero scans to AI Coach',
      );
      return const [];
    }

    final scoped = sorted
        .where((scan) => (scan.procedureId ?? '').trim() == procedure.id)
        .toList();
    if (scoped.isEmpty) {
      AppLogger.verbose(
        '[PremiumRecoveryService] procedure id miss for ${procedure.id}; sending zero scans to AI Coach',
      );
      return const [];
    }
    return scoped;
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
      consistencyLine = 'No scan match context is available yet.';
    } else {
      final latest = scans.first;
      scanLine =
          'Latest scan date: ${latest.timestamp.toIso8601String()}. Scan match status is supplied separately.';
      consistencyLine =
          'Scan match status and lock reasons are supplied per scan; no metric values are included.';
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
        timelineProgressLine =
            'Timeline milestones are available for the current procedure.';
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

    final recentUserJournalNotes =
        generalJournalEntries
            .where(
              (entry) =>
                  entry.content.trim().isNotEmpty ||
                  entry.title.trim().isNotEmpty,
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
