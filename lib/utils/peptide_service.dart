// lib/utils/peptide_service.dart
// CRUD + correlation engine for the Peptide Tracker feature.

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import '../models/peptide_model.dart';
import '../models/scan_history.dart';
import 'app_prefs.dart';
import 'trend_label_resolver.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Journal entry
// ─────────────────────────────────────────────────────────────────────────────

class PeptideJournalEntry {
  final String id;
  final String peptideId;
  final DateTime createdAt;
  final String text;

  const PeptideJournalEntry({
    required this.id,
    required this.peptideId,
    required this.createdAt,
    required this.text,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'peptideId': peptideId,
    'createdAt': createdAt.toIso8601String(),
    'text': text,
  };

  factory PeptideJournalEntry.fromJson(Map<String, dynamic> j) =>
      PeptideJournalEntry(
        id: j['id']?.toString() ?? '',
        peptideId: j['peptideId']?.toString() ?? '',
        createdAt:
            DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        text: j['text']?.toString() ?? '',
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Result type
// ─────────────────────────────────────────────────────────────────────────────

class PeptideCorrelationResult {
  final PeptideEntry peptide;

  /// Per-metric improvement delta. Positive = improvement for every metric
  /// (lower-is-better metrics are pre-inverted during computation).
  final Map<String, double> metricDeltas;

  final int daysTracked;
  final int scansAfterCount;

  /// Raw before/after metrics for the detail view before/after visualization.
  final SkinMetrics? baselineMetrics;
  final SkinMetrics? latestMetrics;

  /// Human-readable summary sentence.
  final String insightText;

  /// True when the peptide is body-composition focused (GLP-1, GHRH/GHRP,
  /// AOD-9604, IGF-1, etc.). When true, [metricDeltas] only contains body
  /// metrics and [rawBeforeMetrics] / [rawAfterMetrics] carry the raw values
  /// so the UI can show proper before→after with units.
  final bool isBodyFocused;
  final Map<String, double> rawBeforeMetrics;
  final Map<String, double> rawAfterMetrics;

  const PeptideCorrelationResult({
    required this.peptide,
    required this.metricDeltas,
    required this.daysTracked,
    required this.scansAfterCount,
    this.baselineMetrics,
    this.latestMetrics,
    required this.insightText,
    this.isBodyFocused = false,
    this.rawBeforeMetrics = const {},
    this.rawAfterMetrics = const {},
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

class PeptideService {
  PeptideService._();

  static const _key = 'peptide_tracker_entries';

  // ── CRUD ────────────────────────────────────────────────────────────────────

  static Future<List<PeptideEntry>> loadAll() async {
    final raw = await AppPrefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => PeptideEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('[PeptideService] loadAll error: $e');
      return [];
    }
  }

  static Future<void> upsert(PeptideEntry entry) async {
    final all = await loadAll();
    final idx = all.indexWhere((e) => e.id == entry.id);
    if (idx >= 0) {
      all[idx] = entry;
    } else {
      all.insert(0, entry);
    }
    await AppPrefs.setString(
      _key,
      jsonEncode(all.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> delete(String id) async {
    final all = await loadAll();
    final updated = all.where((e) => e.id != id).toList();
    await AppPrefs.setString(
      _key,
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
  }

  // ── Stack CRUD ────────────────────────────────────────────────────────────

  static const _stacksKey = 'peptide_stacks';

  static Future<List<PeptideStack>> loadStacks() async {
    final raw = await AppPrefs.getString(_stacksKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => PeptideStack.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('[PeptideService] loadStacks error: $e');
      return [];
    }
  }

  static Future<void> saveStacks(List<PeptideStack> stacks) async {
    await AppPrefs.setString(
      _stacksKey,
      jsonEncode(stacks.map((s) => s.toJson()).toList()),
    );
  }

  static Future<PeptideStack> createStack(String name) async {
    final stacks = await loadStacks();
    final stack = PeptideStack(
      id: 'stack_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'New Stack' : name.trim(),
      createdAt: DateTime.now(),
    );
    stacks.insert(0, stack);
    await saveStacks(stacks);
    return stack;
  }

  static Future<void> renameStack(String id, String newName) async {
    final stacks = await loadStacks();
    final idx = stacks.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    stacks[idx] = stacks[idx].copyWith(name: newName);
    await saveStacks(stacks);
  }

  /// Associates a stack with a procedure so scans taken from the stack are
  /// tagged consistently. No-op if already set or stack not found.
  static Future<void> setStackProcedure(
    String stackId,
    String procedureId,
  ) async {
    final stacks = await loadStacks();
    final idx = stacks.indexWhere((s) => s.id == stackId);
    if (idx < 0) return;
    if (stacks[idx].procedureId == procedureId) return;
    stacks[idx] = stacks[idx].copyWith(procedureId: procedureId);
    await saveStacks(stacks);
  }

  /// Deletes a stack. Peptides previously assigned to it become individual
  /// (stackId cleared) rather than being deleted.
  static Future<void> deleteStack(String id) async {
    final stacks = await loadStacks();
    final remaining = stacks.where((s) => s.id != id).toList();
    await saveStacks(remaining);

    final peptides = await loadAll();
    var changed = false;
    final updated = peptides.map((p) {
      if (p.stackId == id) {
        changed = true;
        return p.copyWith(clearStackId: true);
      }
      return p;
    }).toList();
    if (changed) {
      await AppPrefs.setString(
        _key,
        jsonEncode(updated.map((e) => e.toJson()).toList()),
      );
    }
    await deleteJournalForStack(id);
  }

  /// One-time migration: if the user previously tracked peptides under a
  /// single named "stackName" and we have no Stack records yet, create a
  /// stack from that name and assign every existing peptide to it.
  static Future<void> migrateLegacyStackIfNeeded() async {
    final stacks = await loadStacks();
    if (stacks.isNotEmpty) return;

    final peptides = await loadAll();
    if (peptides.isEmpty) return;

    final legacyName =
        (await AppPrefs.getPeptideStackNameOrNull()) ?? 'My Stack';
    final migrated = PeptideStack(
      id: 'stack_${DateTime.now().millisecondsSinceEpoch}',
      name: legacyName,
      createdAt: DateTime.now(),
    );
    await saveStacks([migrated]);

    final updated = peptides
        .map((p) => p.stackId == null ? p.copyWith(stackId: migrated.id) : p)
        .toList();
    await AppPrefs.setString(
      _key,
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
  }

  // ── Stack Journal CRUD ────────────────────────────────────────────────────

  static const _stackJournalKey = 'peptide_stack_journal_v1';

  static Future<List<StackJournalEntry>> loadJournalAll() async {
    final raw = await AppPrefs.getString(_stackJournalKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map(
            (e) =>
                StackJournalEntry.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<List<StackJournalEntry>> loadJournalForStack(
    String stackId,
  ) async {
    final all = await loadJournalAll();
    return all.where((e) => e.stackId == stackId).toList();
  }

  static Future<void> _saveJournalAll(List<StackJournalEntry> entries) async {
    await AppPrefs.setString(
      _stackJournalKey,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  static Future<StackJournalEntry> addStackJournalEntry({
    required String stackId,
    required String text,
    bool isVoice = false,
  }) async {
    final entry = StackJournalEntry(
      id: 'sj_${DateTime.now().millisecondsSinceEpoch}',
      stackId: stackId,
      createdAt: DateTime.now(),
      text: text,
      isVoice: isVoice,
    );
    final all = await loadJournalAll();
    all.insert(0, entry);
    await _saveJournalAll(all);
    return entry;
  }

  static Future<void> deleteStackJournalEntry(String id) async {
    final all = await loadJournalAll();
    all.removeWhere((e) => e.id == id);
    await _saveJournalAll(all);
  }

  /// Updates the text/isVoice fields of an existing journal entry while
  /// preserving id, stackId and createdAt timestamp.
  static Future<StackJournalEntry?> updateStackJournalEntry({
    required String id,
    required String text,
    bool? isVoice,
  }) async {
    final all = await loadJournalAll();
    final idx = all.indexWhere((e) => e.id == id);
    if (idx == -1) return null;
    final existing = all[idx];
    final updated = StackJournalEntry(
      id: existing.id,
      stackId: existing.stackId,
      createdAt: existing.createdAt,
      text: text,
      isVoice: isVoice ?? existing.isVoice,
    );
    all[idx] = updated;
    await _saveJournalAll(all);
    return updated;
  }

  static Future<void> deleteJournalForStack(String stackId) async {
    final all = await loadJournalAll();
    all.removeWhere((e) => e.stackId == stackId);
    await _saveJournalAll(all);
  }

  // ── Correlation Engine ────────────────────────────────────────────────────

  // Body-composition peptide keywords — mirrors _kBodyPeptideKeywords in the UI.
  static const List<String> _kBodyKeywords = [
    'body-composition',
    'body composition',
    'retatrutide',
    'tirzepatide',
    'semaglutide',
    'liraglutide',
    'tesamorelin',
    'aod-9604',
    'aod 9604',
    'aod9604',
    'sermorelin',
    'cjc-1295',
    'cjc 1295',
    'cjc1295',
    'ipamorelin',
    'hexarelin',
    'mots-c',
    'mots c',
    'motsc',
    'igf-1 lr3',
    'igf 1 lr3',
    'igf1 lr3',
  ];

  static bool _isBodyFocused(PeptideEntry p) {
    final hay = '${p.category} ${p.name}'.toLowerCase();
    return _kBodyKeywords.any(hay.contains);
  }

  /// Unit string for a body metric name (e.g. 'Weight' → ' lbs').
  static String _bodyUnit(String name) {
    switch (name) {
      case 'Weight':
        return ' lbs';
      case 'Body Fat %':
        return '%';
      case 'Waist Circumference':
        return ' in';
      case 'Muscle Mass':
        return ' lbs';
      case 'Appetite Control':
        return '/10';
      case 'Body Composition Score':
        return '/10';
      default:
        return '';
    }
  }

  /// Raw scan-metric keys for a body metric name.
  static List<String> _bodyKeysFor(String name) {
    switch (name) {
      case 'Weight':
        return ['weightLbs', 'weight'];
      case 'Body Fat %':
        return ['bodyFatPct', 'bodyFat'];
      case 'Waist Circumference':
        return ['waistInches', 'waistCm', 'waist'];
      case 'Muscle Mass':
        return ['muscleMassLbs', 'muscleMass', 'leanMass'];
      case 'Appetite Control':
        return ['satietyScore', 'appetiteControl', 'satiety'];
      case 'Body Composition Score':
        return ['bodyCompositionScore'];
      default:
        return [];
    }
  }

  /// Computes improvement correlations for each peptide that has at least
  /// 2 scans available (no minimum days requirement). Scans that straddle
  /// the peptide start date are preferred; when all scans fall on the same
  /// side the earliest and latest scans are used as baseline/latest.
  ///
  /// For body-focused peptides (GLP-1, GHRH/GHRP, AOD-9604, IGF-1, etc.)
  /// ALL skin metrics are excluded — only Weight, Body Fat %, Waist,
  /// Muscle Mass, Appetite Control and Body Composition Score are computed.
  static List<PeptideCorrelationResult> computeCorrelations(
    List<PeptideEntry> peptides,
    List<ScanHistoryEntry> allScans,
  ) {
    final results = <PeptideCorrelationResult>[];
    final sorted = [...allScans]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    for (final peptide in peptides) {
      // Need at least 2 scans to compare.
      if (sorted.length < 2) continue;

      final beforeScans = sorted
          .where((s) => !s.timestamp.isAfter(peptide.startDate))
          .toList();
      final afterScans = sorted
          .where((s) => s.timestamp.isAfter(peptide.startDate))
          .toList();

      // Prefer scans that straddle the start date; otherwise fall back to
      // the first and last scan so the user sees progress after 2 scans.
      final ScanHistoryEntry baselineScan;
      final ScanHistoryEntry latestScan;
      final int scansAfterCount;
      if (beforeScans.isNotEmpty && afterScans.isNotEmpty) {
        baselineScan = beforeScans.last;
        latestScan = afterScans.last;
        scansAfterCount = afterScans.length;
      } else {
        baselineScan = sorted.first;
        latestScan = sorted.last;
        scansAfterCount = sorted.length - 1;
      }

      final baseline = baselineScan.toSkinMetrics();
      final latest = latestScan.toSkinMetrics();
      final beforeMetrics = baselineScan.metrics;
      final afterMetrics = latestScan.metrics;

      final isBody = _isBodyFocused(peptide);
      final deltas = <String, double>{};

      // Positive delta = improvement for all metrics.
      void addDelta(
        String name,
        double b,
        double l, {
        bool lowerIsBetter = true,
      }) {
        final raw = b - l;
        deltas[name] = lowerIsBetter ? raw : -raw;
      }

      // Pull a raw scan-metric value by key, returning null if absent.
      double? rawOf(Map<String, double> m, List<String> keys) {
        for (final k in keys) {
          final v = m[k];
          if (v != null) return v;
        }
        return null;
      }

      // Adds a delta only if both before/after raw values exist.
      void addOptionalDelta(
        String name,
        List<String> keys, {
        required bool lowerIsBetter,
      }) {
        final b = rawOf(beforeMetrics, keys);
        final l = rawOf(afterMetrics, keys);
        if (b == null || l == null) return;
        addDelta(name, b, l, lowerIsBetter: lowerIsBetter);
      }

      if (!isBody) {
        // ── Core skin metrics (only for skin-focused peptides) ─────────────
        addDelta('Redness / Swelling', baseline.redness, latest.redness);
        addDelta('Texture', baseline.texture, latest.texture);
        addDelta('Fine Lines / Wrinkles', baseline.wrinkle, latest.wrinkle);
        addDelta('Pore Visibility', baseline.pore, latest.pore);
        addDelta('Dark Spots', baseline.darkSpots, latest.darkSpots);
        addDelta(
          'Skin Elasticity',
          baseline.elasticity,
          latest.elasticity,
          lowerIsBetter: false,
        );

        // ── Extended skin metrics ──────────────────────────────────────────
        addOptionalDelta('Hydration', const [
          'hydration',
          'barrierHealth',
        ], lowerIsBetter: false);
        addOptionalDelta('Firmness', const ['firmness'], lowerIsBetter: false);
        addOptionalDelta('Evenness / Tone', const [
          'evenness',
          'tone',
          'skinTone',
        ], lowerIsBetter: false);
        addOptionalDelta('Inflammation', const [
          'inflammation',
          'swelling',
        ], lowerIsBetter: true);
        addOptionalDelta('Skin Age', const [
          'skinAge',
          'estimatedSkinAge',
          'biologicalAge',
        ], lowerIsBetter: true);
      }

      // ── Body composition (always for body-focused; optional for skin) ───
      addOptionalDelta('Weight', const [
        'weightLbs',
        'weight',
      ], lowerIsBetter: true);
      addOptionalDelta('Body Fat %', const [
        'bodyFatPct',
        'bodyFat',
      ], lowerIsBetter: true);
      addOptionalDelta('Waist Circumference', const [
        'waistInches',
        'waistCm',
        'waist',
      ], lowerIsBetter: true);
      addOptionalDelta('Muscle Mass', const [
        'muscleMassLbs',
        'muscleMass',
        'leanMass',
      ], lowerIsBetter: false);
      addOptionalDelta('Appetite Control', const [
        'satietyScore',
        'appetiteControl',
        'satiety',
      ], lowerIsBetter: false);
      addOptionalDelta('Body Composition Score', const [
        'bodyCompositionScore',
      ], lowerIsBetter: false);

      if (deltas.isEmpty) continue;

      final sortedDeltas = deltas.entries.toList()
        ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
      final top = sortedDeltas.first;

      final conc = peptide.concentration != null
          ? '${peptide.concentration!.toStringAsFixed(1)}% '
          : '';

      // Generate insight text with proper units for body metrics.
      final String insight;
      if (isBody) {
        final unit = _bodyUnit(top.key);
        final bVal = rawOf(beforeMetrics, _bodyKeysFor(top.key));
        final aVal = rawOf(afterMetrics, _bodyKeysFor(top.key));
        if (bVal != null && aVal != null) {
          insight =
              'After ${peptide.daysTracked}d of $conc${peptide.name}, '
              '${top.key} changed '
              '(${bVal.toStringAsFixed(1)}$unit \u2192 ${aVal.toStringAsFixed(1)}$unit).';
        } else {
          insight =
              'After ${peptide.daysTracked}d of $conc${peptide.name}, '
              '${top.key} changed by ${top.value.abs().toStringAsFixed(1)}$unit.';
        }
      } else {
        final canonicalKey = switch (top.key) {
          'Redness / Swelling' => 'localized_redness',
          'Texture' => 'texture_smoothness',
          'Fine Lines / Wrinkles' => 'wrinkle_load',
          'Pore Visibility' => 'pore_visibility',
          'Dark Spots' => 'pigment_load',
          'Skin Elasticity' => 'structural_firmness_elasticity',
          _ => null,
        };
        final trendStatus = trendStatusMapFromRawPayload(latestScan.rawPayload);
        final trendLockReasons = trendLockReasonMapFromRawPayload(
          latestScan.rawPayload,
        );
        final resolvedTrend = resolveTrendLabel(
          trendStatus: canonicalKey == null ? null : trendStatus[canonicalKey],
          trendLockReason: canonicalKey == null
              ? null
              : trendLockReasons[canonicalKey],
        );
        final dir = resolvedTrend == null || resolvedTrend.isInsufficientSignal
            ? 'changed'
            : (resolvedTrend.lockShortLabel ?? resolvedTrend.label.toLowerCase());
        insight =
            'After ${peptide.daysTracked}d of $conc${peptide.name}, '
            '${top.key} $dir by ${top.value.abs().toStringAsFixed(1)} pts.';
      }

      results.add(
        PeptideCorrelationResult(
          peptide: peptide,
          metricDeltas: deltas,
          daysTracked: peptide.daysTracked,
          scansAfterCount: scansAfterCount,
          baselineMetrics: baseline,
          latestMetrics: latest,
          insightText: insight,
          isBodyFocused: isBody,
          rawBeforeMetrics: Map<String, double>.from(beforeMetrics),
          rawAfterMetrics: Map<String, double>.from(afterMetrics),
        ),
      );
    }

    return results;
  }

  // ── Journal CRUD ──────────────────────────────────────────────────────────

  static const _journalKey = 'peptide_journal_entries';

  static Future<List<PeptideJournalEntry>> loadJournal(String peptideId) async {
    final raw = await AppPrefs.getString(_journalKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return (list
            .whereType<Map>()
            .map(
              (e) => PeptideJournalEntry.fromJson(Map<String, dynamic>.from(e)),
            )
            .where((e) => e.peptideId == peptideId)
            .toList())
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      debugPrint('[PeptideService] loadJournal error: $e');
      return [];
    }
  }

  static Future<void> addJournalEntry(PeptideJournalEntry entry) async {
    final raw = await AppPrefs.getString(_journalKey);
    final List all = (raw != null && raw.isNotEmpty)
        ? (jsonDecode(raw) as List)
        : [];
    all.add(entry.toJson());
    await AppPrefs.setString(_journalKey, jsonEncode(all));
  }

  static Future<void> deleteJournalEntry(String id) async {
    final raw = await AppPrefs.getString(_journalKey);
    if (raw == null || raw.isEmpty) return;
    final list = jsonDecode(raw) as List;
    list.removeWhere((e) => (e as Map)['id'] == id);
    await AppPrefs.setString(_journalKey, jsonEncode(list));
  }

  static Future<void> updateJournalEntry(String id, String newText) async {
    final raw = await AppPrefs.getString(_journalKey);
    if (raw == null || raw.isEmpty) return;
    final list = jsonDecode(raw) as List;
    for (final item in list) {
      if ((item as Map)['id'] == id) {
        item['text'] = newText;
        break;
      }
    }
    await AppPrefs.setString(_journalKey, jsonEncode(list));
  }

  // ── AI Coach Context ──────────────────────────────────────────────────────

  /// Returns a formatted string describing the user's active peptide stack,
  /// suitable for prepending to AI coach prompts.
  /// Builds a rich, AI-coach-ready summary of the user's active peptide
  /// stack(s) AND the most recent scan metrics (skin + body composition).
  /// Returns '' when no active peptides exist so the coach can fall back
  /// to the generic procedure-context prompt.
  static Future<String> buildAICoachContext() async {
    final peptides = await loadAll();
    final active = peptides.where((p) => p.isActive).toList();
    if (active.isEmpty) return '';

    final stacks = await loadStacks();
    final allScans = await AppPrefs.getScanEntries();

    // Body-composition heuristic — kept in sync with the UI-side
    // _kBodyPeptideKeywords list in peptide_tracker_screen.dart.
    const bodyKeywords = <String>[
      'body-composition',
      'body composition',
      'retatrutide',
      'tirzepatide',
      'semaglutide',
      'liraglutide',
      'tesamorelin',
      'aod-9604',
      'aod 9604',
      'aod9604',
      'sermorelin',
      'cjc-1295',
      'cjc 1295',
      'cjc1295',
      'ipamorelin',
      'hexarelin',
      'mots-c',
      'mots c',
      'motsc',
      'igf-1 lr3',
      'igf 1 lr3',
      'igf1 lr3',
    ];
    bool isBodyFocused(PeptideEntry e) {
      final hay = '${e.category} ${e.name}'.toLowerCase();
      return bodyKeywords.any(hay.contains);
    }

    // Per-stack grouping so the coach can speak about each stack's
    // peptides and scans together.
    final byStack = <String, List<PeptideEntry>>{};
    for (final p in active) {
      final sid = p.stackId ?? '__unstacked__';
      byStack.putIfAbsent(sid, () => []).add(p);
    }

    final buf = StringBuffer();
    buf.writeln(
      '=== Peptide Tracker context (use this to ground every answer) ===',
    );

    for (final stackId in byStack.keys) {
      final stack = stacks.where((s) => s.id == stackId).firstOrNull;
      final stackName = stack?.name ?? 'Stack';
      final stackPeptides = byStack[stackId]!;
      final bodyFocused = stackPeptides.any(isBodyFocused);

      buf.writeln();
      buf.writeln(
        'Stack: $stackName${bodyFocused ? ' (body-composition / weight-loss focus)' : ' (skin / aesthetic focus)'}',
      );

      for (final p in stackPeptides) {
        final conc = p.concentration != null
            ? '${p.concentration!.toStringAsFixed(1)}% '
            : '';
        buf.writeln(
          '  - $conc${p.name} (${p.category}) — ${p.frequency}, '
          'started ${p.daysTracked} days ago'
          '${p.notes.isNotEmpty ? ', notes: ${p.notes}' : ''}',
        );
      }

      // Scope scans to this stack's pinned procedure (if any).
      final scoped = stack?.procedureId == null
          ? allScans
          : allScans.where((s) => s.procedureId == stack!.procedureId).toList();
      final sorted = [...scoped]
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      if (sorted.isNotEmpty) {
        final baseline = sorted.first;
        final latest = sorted.last;
        buf.writeln(
          '  Scans on file: ${sorted.length}'
          ' (baseline ${_fmtDate(baseline.timestamp)}'
          ' → latest ${_fmtDate(latest.timestamp)})',
        );

        // Body metrics (always include if present; lead for body stacks).
        final bodyLine = _summarizeMetrics(baseline.metrics, latest.metrics, [
          [
            'Weight (lbs)',
            ['weightLbs', 'weight'],
          ],
          [
            'Body Fat %',
            ['bodyFatPct', 'bodyFat'],
          ],
          [
            'Waist (in)',
            ['waistInches', 'waist', 'waistCm'],
          ],
          [
            'Muscle (lbs)',
            ['muscleMassLbs', 'muscleMass', 'leanMass'],
          ],
          [
            'Appetite Control',
            ['satietyScore', 'appetiteControl', 'satiety'],
          ],
        ]);
        if (bodyLine.isNotEmpty) {
          buf.writeln('  Body metrics: $bodyLine');
        }

        // Skin metrics from latest SkinMetrics-style fields.
        final skinLine = _summarizeMetrics(baseline.metrics, latest.metrics, [
          [
            'Redness',
            ['redness', 'inflammation', 'swelling'],
          ],
          [
            'Texture',
            ['texture'],
          ],
          [
            'Wrinkles',
            ['wrinkles', 'wrinkle'],
          ],
          [
            'Pores',
            ['pores', 'pore'],
          ],
          [
            'Dark Spots',
            ['darkSpots'],
          ],
          [
            'Elasticity',
            ['elasticity'],
          ],
          [
            'Hydration',
            ['hydration', 'barrierHealth'],
          ],
          [
            'Firmness',
            ['firmness'],
          ],
          [
            'Evenness',
            ['evenness', 'tone', 'skinTone'],
          ],
        ]);
        if (skinLine.isNotEmpty) {
          buf.writeln('  Skin metrics: $skinLine');
        }

        // Estimated skin age trend (when present).
        if (baseline.estimatedSkinAge > 0 || latest.estimatedSkinAge > 0) {
          buf.writeln(
            '  Estimated skin age: ${baseline.estimatedSkinAge.toStringAsFixed(1)} → ${latest.estimatedSkinAge.toStringAsFixed(1)}',
          );
        }
      } else {
        buf.writeln('  Scans on file: 0 (no metrics yet)');
      }
    }

    buf.writeln();
    buf.writeln(
      'Tailor your guidance to these peptides and metric trends. Reference the user\'s actual numbers (do not invent any).',
    );
    buf.writeln('=== End peptide context ===');
    return buf.toString();
  }

  static String _fmtDate(DateTime dt) {
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
    final l = dt.toLocal();
    return '${months[l.month - 1]} ${l.day}';
  }

  /// For each `[label, [aliasKeys...]]` row, emits `Label: baseline → latest`
  /// using the first non-null alias found in each scan map. Returns a single
  /// comma-separated line, or '' when nothing matched.
  static String _summarizeMetrics(
    Map<String, double> baseline,
    Map<String, double> latest,
    List<List<Object>> rows,
  ) {
    double? pick(Map<String, double> m, List<String> aliases) {
      for (final k in aliases) {
        final v = m[k];
        if (v != null) return v;
      }
      return null;
    }

    final out = <String>[];
    for (final r in rows) {
      final label = r[0] as String;
      final aliases = (r[1] as List).cast<String>();
      final b = pick(baseline, aliases);
      final l = pick(latest, aliases);
      if (b == null && l == null) continue;
      if (b != null && l != null && (b - l).abs() < 0.0001) {
        out.add('$label ${l.toStringAsFixed(1)}');
      } else if (b != null && l != null) {
        out.add('$label ${b.toStringAsFixed(1)} → ${l.toStringAsFixed(1)}');
      } else if (l != null) {
        out.add('$label ${l.toStringAsFixed(1)}');
      } else {
        out.add('$label baseline ${b!.toStringAsFixed(1)}');
      }
    }
    return out.join(', ');
  }
}
