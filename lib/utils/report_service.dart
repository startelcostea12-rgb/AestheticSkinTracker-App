// lib/utils/report_service.dart
//
// ReportService - clean, reusable API for generating and persisting
// Professional Recovery Reports (PDF + metadata).
//
// Usage from any screen:
//   final result = await ReportService.generateAndSave(ReportInput(...));
//   await ReportService.triggerDownload(result.pdfBytes, result.record.pdfFileName!);
//
// Re-download a saved report on web:
//   final bytes = ReportService.getPdfBytesFromRecord(record);
//   if (bytes != null) await ReportService.triggerDownload(bytes, record.pdfFileName!);

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/premium_recovery_models.dart';
import '../models/procedure.dart';
import '../models/scan_history.dart';
import '../widgets/report_share_helper.dart' as rsh;
import 'app_logger.dart';
import 'app_prefs.dart';
import 'procedure_intelligence.dart';
import 'trend_label_resolver.dart';
import 'report_disclaimer.dart';
import 'tracked_item_display.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Input DTO
// ─────────────────────────────────────────────────────────────────────────────

class ReportInput {
  const ReportInput({
    required this.procedure,
    required this.scans,
    this.beforePhotoBytes,
    this.afterPhotoBytes,
    this.insights = const [],
    this.surgeonNotes,
    this.patientName,
    this.customPlanMilestones = const [],
  });

  /// The procedure profile this report is for.
  final Procedure procedure;

  /// All scans scoped to this procedure, sorted newest-first.
  final List<ScanHistoryEntry> scans;

  /// Raw image bytes for the baseline / before photo (optional).
  final Uint8List? beforePhotoBytes;

  /// Raw image bytes for the latest / after photo (optional).
  final Uint8List? afterPhotoBytes;

  /// AI recovery insights already loaded for this procedure.
  final List<ProgressPhotoInsight> insights;

  /// Surgeon post-op instructions text (optional).
  final String? surgeonNotes;

  /// Patient display name (falls back to AppPrefs.getUserName if null).
  final String? patientName;

  /// Milestones from a CustomRecoveryPlan (optional).
  final List<ProcedureTimelineMilestone> customPlanMilestones;
}

// ─────────────────────────────────────────────────────────────────────────────
// Result DTO
// ─────────────────────────────────────────────────────────────────────────────

class ReportResult {
  const ReportResult({required this.record, required this.pdfBytes});

  /// The persisted metadata record (already saved to AppPrefs).
  final ProfessionalReportRecord record;

  /// The raw PDF bytes - use [ReportService.triggerDownload] to deliver them.
  final Uint8List pdfBytes;
}

// ─────────────────────────────────────────────────────────────────────────────
// Peptide / protocol profile knowledge layer
// ─────────────────────────────────────────────────────────────────────────────
//
// Provides peptide-specific language used in the Clinical Interpretation
// section, the Most Improved highlight, and the personalized recommendations
// of the PDF report. Falls back to a sensible generic profile when the
// peptide / procedure name is not recognized.

class _PeptideProfile {
  const _PeptideProfile({
    required this.canonicalName,
    required this.category,
    required this.mechanism,
    required this.expectedEffects,
    required this.successMarker,
    required this.clinicalContext,
  });

  /// Display name used in the report (e.g. "Retatrutide").
  final String canonicalName;

  /// One of: 'skin', 'body', 'healing', 'longevity', 'generic'.
  final String category;

  /// Short mechanism description.
  final String mechanism;

  /// What positive change typically looks like for this peptide.
  final String expectedEffects;

  /// Marker of a strong individual response (used in "Most Improved" note).
  final String successMarker;

  /// Background clinical context referenced in the lead-in paragraph.
  final String clinicalContext;
}

const Map<String, _PeptideProfile> _peptideProfiles = {
  // ── GLP-1 / GIP family (body composition) ────────────────────────────────
  'retatrutide': _PeptideProfile(
    canonicalName: 'Retatrutide',
    category: 'body',
    mechanism:
        'triple GLP-1 / GIP / glucagon receptor agonist that modulates '
        'appetite, gastric emptying, and energy expenditure',
    expectedEffects:
        'gradual reduction in body weight and waist circumference, with '
        'preserved lean mass when paired with adequate protein intake',
    successMarker:
        'a consistent downward trend in weight and waist measurements '
        'is the strongest indicator of an effective Retatrutide response',
    clinicalContext:
        'Retatrutide protocols are typically evaluated over 8-24 weeks; '
        'results below reflect changes observed within your current '
        'tracked window.',
  ),
  'tirzepatide': _PeptideProfile(
    canonicalName: 'Tirzepatide',
    category: 'body',
    mechanism:
        'dual GLP-1 / GIP receptor agonist that reduces appetite and '
        'improves glycemic regulation',
    expectedEffects:
        'progressive weight reduction with stabilized appetite and '
        'improved satiety scores',
    successMarker:
        'sustained weight and waist reduction alongside steady satiety '
        'scores indicates a strong therapeutic response',
    clinicalContext:
        'Tirzepatide outcomes are most reliably assessed over 12+ '
        'weeks of consistent dosing.',
  ),
  'semaglutide': _PeptideProfile(
    canonicalName: 'Semaglutide',
    category: 'body',
    mechanism:
        'GLP-1 receptor agonist that suppresses appetite and slows '
        'gastric emptying',
    expectedEffects:
        'steady weight loss and reduced caloric intake driven by '
        'improved satiety',
    successMarker:
        'a clear downward trend in weight with rising satiety scores '
        'reflects an effective Semaglutide response',
    clinicalContext:
        'Semaglutide effects are dose-dependent and most evaluable '
        'after 8-12 weeks of titrated therapy.',
  ),
  // ── Skin / collagen peptides ─────────────────────────────────────────────
  'matrixyl': _PeptideProfile(
    canonicalName: 'Matrixyl',
    category: 'skin',
    mechanism:
        'palmitoyl pentapeptide that stimulates collagen I, III, and '
        'fibronectin synthesis in the dermis',
    expectedEffects:
        'gradual softening of fine lines, improved skin firmness, and '
        'enhanced surface texture',
    successMarker:
        'sustained improvement in elasticity and fine-line scores is '
        'the strongest signal of an effective Matrixyl response',
    clinicalContext:
        'Matrixyl-driven dermal remodeling typically becomes measurable '
        'after 4-8 weeks of consistent topical use.',
  ),
  'ghk-cu': _PeptideProfile(
    canonicalName: 'GHK-Cu',
    category: 'skin',
    mechanism:
        'copper tripeptide that promotes collagen synthesis, '
        'antioxidant defense, and dermal repair',
    expectedEffects:
        'improved skin firmness, reduced redness, and a more even tone '
        'with continued use',
    successMarker:
        'parallel gains in elasticity and texture indicate a strong '
        'GHK-Cu response',
    clinicalContext:
        'GHK-Cu activity is cumulative; meaningful changes are typically '
        'evident after 6-12 weeks.',
  ),
  'argireline': _PeptideProfile(
    canonicalName: 'Argireline',
    category: 'skin',
    mechanism:
        'acetyl hexapeptide-8 that reduces repetitive expression-line '
        'muscle contraction at the dermal-junction level',
    expectedEffects:
        'softening of dynamic expression lines, particularly across '
        'the forehead and around the eyes',
    successMarker:
        'a measurable decline in fine-line / wrinkle scores is the '
        'clearest indicator of Argireline efficacy',
    clinicalContext:
        'Argireline outcomes typically become visible after 4-6 weeks '
        'of consistent twice-daily application.',
  ),
  // ── Healing / recovery peptides ──────────────────────────────────────────
  'bpc-157': _PeptideProfile(
    canonicalName: 'BPC-157',
    category: 'healing',
    mechanism:
        'body protection compound that supports angiogenesis, tendon '
        'recovery, and gut-lining repair',
    expectedEffects:
        'faster resolution of inflammation, reduced redness, and '
        'improved tissue recovery markers',
    successMarker:
        'a steady decline in inflammatory markers and redness reflects '
        'a strong BPC-157 response',
    clinicalContext:
        'BPC-157 effects are most evaluable over 4-8 week cycles in '
        'targeted recovery protocols.',
  ),
  'tb-500': _PeptideProfile(
    canonicalName: 'TB-500',
    category: 'healing',
    mechanism:
        'thymosin beta-4 fragment that supports tissue repair, cell '
        'migration, and reduced inflammation',
    expectedEffects:
        'improved tissue healing rate and reduction in localized '
        'inflammation',
    successMarker:
        'reduced inflammation indicators alongside improved tissue '
        'integrity suggest an effective TB-500 response',
    clinicalContext:
        'TB-500 protocols are typically evaluated over 4-6 weeks per '
        'cycle.',
  ),
  // ── Longevity / metabolic ────────────────────────────────────────────────
  'epitalon': _PeptideProfile(
    canonicalName: 'Epitalon',
    category: 'longevity',
    mechanism:
        'tetrapeptide that supports telomerase activity and circadian '
        'pineal regulation',
    expectedEffects:
        'subjective improvements in sleep quality, recovery, and '
        'overall vitality',
    successMarker:
        'consistent improvement in subjective recovery and energy '
        'scores reflects a positive Epitalon response',
    clinicalContext:
        'Epitalon is typically cycled, and effects are observed across '
        '10-20 day protocols.',
  ),
  'nad+': _PeptideProfile(
    canonicalName: 'NAD+',
    category: 'longevity',
    mechanism:
        'nicotinamide adenine dinucleotide supports mitochondrial '
        'function and cellular energy metabolism',
    expectedEffects:
        'improved energy levels, cognitive clarity, and recovery '
        'markers',
    successMarker:
        'sustained improvement in energy and recovery scores is the '
        'clearest indicator of an effective NAD+ protocol',
    clinicalContext:
        'NAD+ outcomes are typically evaluated over 4-8 weeks of '
        'consistent administration.',
  ),
};

/// Returns a profile for the supplied peptide / procedure name. Falls back
/// to a generic profile when nothing matches.
_PeptideProfile _peptideProfileFor(String name) {
  final key = name.toLowerCase().trim();
  if (key.isEmpty) return _genericProfile(name);
  // Direct match first.
  if (_peptideProfiles.containsKey(key)) return _peptideProfiles[key]!;
  // Fuzzy contains-match.
  for (final entry in _peptideProfiles.entries) {
    if (key.contains(entry.key) || entry.key.contains(key)) {
      return entry.value;
    }
  }
  return _genericProfile(name);
}

_PeptideProfile _genericProfile(String name) {
  final cleaned = name.trim().isEmpty ? 'this protocol' : name.trim();
  return _PeptideProfile(
    canonicalName: cleaned,
    category: 'generic',
    mechanism: 'targeted therapeutic protocol',
    expectedEffects:
        'measurable progress in the metrics most relevant to $cleaned',
    successMarker:
        'consistent improvement across tracked metrics is the '
        'strongest indicator of an effective $cleaned response',
    clinicalContext:
        'Results below reflect changes measured within your current '
        'tracking window for $cleaned.',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ReportService
// ─────────────────────────────────────────────────────────────────────────────

class ReportService {
  ReportService._();

  static const String _storageKey = 'premium_report_records';
  static const int _maxStoredReports = 30;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Generate a full Professional Recovery Report PDF, save its metadata to
  /// AppPrefs, and return a [ReportResult] containing both the bytes and the
  /// persisted [ProfessionalReportRecord].
  ///
  /// Throws on hard failures (e.g. PDF engine crash); callers should wrap in
  /// try/catch and show a user-facing error message.
  static Future<ReportResult> generateAndSave(ReportInput input) async {
    final patientName = ((input.patientName ?? '').trim().isEmpty)
        ? await AppPrefs.getUserName()
        : input.patientName!.trim();
    final resolvedProcedureType = (() {
      final normalized = input.procedure.type.trim();
      if (normalized.isEmpty || normalized.toLowerCase() == 'unknown') {
        return 'General Skincare';
      }
      return normalized;
    })();
    AppLogger.verbose(
      '[ReportService.generateAndSave] resolvedProcedureType=$resolvedProcedureType',
    );

    final pdfBytes = await _buildPdf(input: input, patientName: patientName);
    final record = _buildRecord(input: input, pdfBytes: pdfBytes);
    // Persistence is best-effort - never let a storage failure
    // (e.g. web localStorage QuotaExceededError) block the download.
    try {
      await _persistRecord(record);
    } catch (e) {
      debugPrint('[ReportService.generateAndSave] persist failed: $e');
    }

    debugPrint(
      '[ReportService] Generated report: ${record.id} | '
      '${record.title} | ${pdfBytes.length} bytes',
    );

    return ReportResult(record: record, pdfBytes: pdfBytes);
  }

  /// Load all saved report records, newest first.
  static Future<List<ProfessionalReportRecord>> loadAll() async {
    final raw = await AppPrefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map(
            (e) =>
                ProfessionalReportRecord.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList();
    } catch (e) {
      debugPrint('[ReportService] loadAll parse error: $e - wiping bad data');
      // Corrupt or oversized payload - wipe to recover.
      try {
        await AppPrefs.setString(_storageKey, '');
      } catch (_) {}
      return [];
    }
  }

  /// One-time cleanup helper. Call from app startup to evict any legacy
  /// records that embedded the full PDF as base64 (which blows the web
  /// localStorage quota). Safe to call repeatedly - no-op if already clean.
  static Future<void> cleanupLegacyStorage() async {
    try {
      final raw = await AppPrefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      // If the raw blob is larger than ~256 KB, it almost certainly
      // contains embedded PDFs from a previous version - reset it.
      if (raw.length > 256 * 1024) {
        debugPrint(
          '[ReportService] Evicting oversized record store '
          '(${raw.length} bytes) to recover localStorage quota.',
        );
        await AppPrefs.setString(_storageKey, '');
        return;
      }
      // Otherwise re-serialize with pdfBase64 stripped to defang any
      // smaller-but-still-embedded records.
      final list = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .map((m) {
            m.remove('pdfBase64');
            return m;
          })
          .toList();
      await AppPrefs.setString(_storageKey, jsonEncode(list));
    } catch (e) {
      debugPrint('[ReportService] cleanupLegacyStorage error: $e');
      try {
        await AppPrefs.setString(_storageKey, '');
      } catch (_) {}
    }
  }

  /// Retrieve the PDF bytes stored inside a saved record (for re-download).
  /// Returns null if the record has no embedded PDF (e.g. an old stub record).
  static Uint8List? getPdfBytesFromRecord(ProfessionalReportRecord record) {
    final b64 = record.pdfBase64;
    if (b64 == null || b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  /// Trigger a browser download / share-sheet for the given PDF bytes.
  /// Delegates to the platform-conditional [report_share_helper].
  static Future<void> triggerDownload(
    Uint8List pdfBytes, {
    required String fileName,
  }) async {
    // Import is done conditionally at call site to keep the service pure.
    // Callers should import report_share_helper.dart directly.
    // This helper is kept here so screens can call a single service method.
    await _platformTriggerDownload(pdfBytes, fileName: fileName);
  }

  /// Delete a single report record by id.
  static Future<void> deleteById(String id) async {
    final all = await loadAll();
    final updated = all.where((r) => r.id != id).toList();
    try {
      await AppPrefs.setString(
        _storageKey,
        jsonEncode(updated.map((e) => _lightweightJson(e)).toList()),
      );
    } catch (e) {
      debugPrint('[ReportService] deleteById persist error: $e');
    }
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  /// Returns a metadata-only JSON view of a record, suitable for
  /// SharedPreferences/localStorage. Never includes [pdfBase64] (large)
  /// or other heavy fields - those live only in memory for the lifetime
  /// of the current download flow.
  static Map<String, dynamic> _lightweightJson(ProfessionalReportRecord r) {
    return {
      'id': r.id,
      'createdAt': r.createdAt.toIso8601String(),
      'reportDate': r.reportDate.toIso8601String(),
      'title': r.title,
      'summary': r.summary,
      'procedureName': r.procedureName,
      'keyMetrics': r.keyMetrics,
      'pdfFileName': r.pdfFileName,
      'fileRef': r.fileRef,
      // Intentionally NOT persisted: pdfBase64.
    };
  }

  static Future<void> _persistRecord(ProfessionalReportRecord record) async {
    final all = await loadAll();
    // Idempotent upsert - remove any existing record with the same id.
    final deduped = all.where((r) => r.id != record.id).toList();
    deduped.insert(0, record);
    final trimmed = deduped.take(_maxStoredReports).toList();
    final payload = jsonEncode(
      trimmed.map((e) => _lightweightJson(e)).toList(),
    );
    try {
      await AppPrefs.setString(_storageKey, payload);
    } catch (e) {
      // localStorage quota or other storage failure - shed older
      // records and retry with only the newest entry.
      debugPrint(
        '[ReportService] _persistRecord failed ($e); retrying with newest record only.',
      );
      try {
        await AppPrefs.setString(
          _storageKey,
          jsonEncode([_lightweightJson(record)]),
        );
      } catch (e2) {
        debugPrint(
          '[ReportService] _persistRecord retry failed ($e2); clearing key.',
        );
        try {
          await AppPrefs.setString(_storageKey, '');
        } catch (_) {}
      }
    }
  }

  static ProfessionalReportRecord _buildRecord({
    required ReportInput input,
    required Uint8List pdfBytes,
  }) {
    final procedure = input.procedure;
    final scans = input.scans;
    final procedureLabel = procedureContextLabel(
      procedureType: procedure.type,
      customDescription: procedure.customDescription,
      focusArea: procedure.focusArea,
    );
    final metricProcedureType = procedureMetricContextType(
      procedureType: procedure.type,
      customDescription: procedure.customDescription,
      focusArea: procedure.focusArea,
    );

    final confidence = recoveryConfidenceScore(
      scans: scans,
      insights: input.insights,
      procedureType: metricProcedureType,
    );

    final keyMetrics = <String, dynamic>{
      'scan_count': scans.length,
      'journal_count': procedure.journalEntries.length,
      'recovery_confidence': confidence,
    };

    if (scans.length >= 2) {
      final baseline = scans.last.toSkinMetrics();
      final latest = scans.first.toSkinMetrics();
      for (final def in clinicalMetricsForProcedure(metricProcedureType)) {
        final baselineValue = def.valueFromRaw(scans.last.metrics, baseline);
        final latestValue = def.valueFromRaw(scans.first.metrics, latest);
        if (baselineValue == null || latestValue == null) continue;
        keyMetrics[_keyMetricChangeKey(def.label)] = metricPctChange(
          baselineValue,
          latestValue,
          lowerIsBetter: def.lowerIsBetter,
        );
      }
    }

    final ts = DateTime.now().millisecondsSinceEpoch;
    final fileName =
        'recovery_report_${procedure.id.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}_$ts.pdf';

    return ProfessionalReportRecord(
      id: 'report_${procedure.id}_$ts',
      createdAt: DateTime.now(),
      reportDate: DateTime.now(),
      title: '$procedureLabel Recovery Report',
      summary: _buildSummaryText(input: input, confidence: confidence),
      procedureName: procedureLabel,
      keyMetrics: keyMetrics,
      pdfBase64: base64Encode(pdfBytes),
      pdfFileName: fileName,
    );
  }

  // ── PDF builder ────────────────────────────────────────────────────────────

  static Future<pw.Font> _loadPdfFont(
    String assetPath,
    pw.Font Function() fallback,
  ) async {
    try {
      final data = await rootBundle.load(assetPath);
      return pw.Font.ttf(data);
    } catch (error, stackTrace) {
      debugPrint(
        '[ReportService] Unable to load PDF font assetPath="$assetPath". '
        'Falling back to Helvetica. Error: $error',
      );
      debugPrint(stackTrace.toString());
      return fallback();
    }
  }

  static Future<void> _debugCheckRobotoRegularFontAsset() async {
    const assetPath = 'assets/fonts/Roboto-Regular.ttf';
    try {
      final data = await rootBundle.load(assetPath);
      debugPrint(
        '[ReportService] PDF font asset loaded: $assetPath '
        '(${data.lengthInBytes} bytes)',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[ReportService] PDF font asset check failed assetPath="$assetPath". '
        'Report generation will continue with Helvetica fallback. Error: $error',
      );
      debugPrint(stackTrace.toString());
    }
  }

  static Future<pw.ThemeData> _buildPdfTheme() async {
    try {
      return pw.ThemeData.withFont(
        base: await _loadPdfFont(
          'assets/fonts/Roboto-Regular.ttf',
          pw.Font.helvetica,
        ),
        bold: await _loadPdfFont(
          'assets/fonts/Roboto-Bold.ttf',
          pw.Font.helveticaBold,
        ),
        italic: await _loadPdfFont(
          'assets/fonts/Roboto-Italic.ttf',
          pw.Font.helveticaOblique,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[ReportService] PDF theme creation failed. '
        'Using built-in Helvetica theme. Error: $error',
      );
      debugPrint(stackTrace.toString());
      return pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        italic: pw.Font.helveticaOblique(),
      );
    }
  }

  static Future<Uint8List> _buildPdf({
    required ReportInput input,
    required String patientName,
  }) async {
    await _debugCheckRobotoRegularFontAsset();

    final pdf = pw.Document();
    final proc = input.procedure;
    final scans = input.scans;

    final df = DateFormat('MMMM d, yyyy');
    final dateRange = scans.isEmpty
        ? df.format(proc.startDate)
        : '${df.format(proc.startDate)} - ${df.format(scans.first.timestamp)}';

    final baselineMetrics = scans.length >= 2
        ? scans.last.toSkinMetrics()
        : null;
    final latestMetrics = scans.isNotEmpty ? scans.first.toSkinMetrics() : null;

    final confidence = recoveryConfidenceScore(
      scans: scans,
      insights: input.insights,
      procedureType: procedureMetricContextType(
        procedureType: input.procedure.type,
        customDescription: input.procedure.customDescription,
        focusArea: input.procedure.focusArea,
      ),
    );
    final metricProcedureType = procedureMetricContextType(
      procedureType: input.procedure.type,
      customDescription: input.procedure.customDescription,
      focusArea: input.procedure.focusArea,
    );

    final isBodyContouringReport = usesBodyContouringContext(
      procedureType: input.procedure.type,
      customDescription: input.procedure.customDescription,
      focusArea: input.procedure.focusArea,
    );
    final isCustomProcedure = isCustomProcedureType(input.procedure.type);
    final isBblReport =
        isBodyContouringReport &&
        !isCustomProcedure &&
        ProcedureIntelligence.bodyContouringSubtype(input.procedure.type) ==
            ProcedureBodyContouringSubtype.bbl;

    // ── Decode photos (forced PNG transcode) ───────────────────────────────
    print('=== PDF IMAGE EMBEDDING START ===');
    print(
      '=== INPUT CHECK: baseline bytes = ${input.beforePhotoBytes?.length ?? 0} ===',
    );
    print(
      '=== INPUT CHECK: latest bytes = ${input.afterPhotoBytes?.length ?? 0} ===',
    );

    final beforeImage = await _forcePngImage(
      input.beforePhotoBytes,
      label: 'Baseline',
    );
    final afterImage = await _forcePngImage(
      input.afterPhotoBytes,
      label: 'Latest',
    );

    print('=== RESULT CHECK: baseline converted = ${beforeImage != null} ===');
    print('=== RESULT CHECK: latest converted = ${afterImage != null} ===');
    print('=== PDF IMAGE EMBEDDING END ===');

    // ── Luxury clinical color palette ───────────────────────────────────────
    const navy = PdfColor.fromInt(0xFF2C3539); // refined slate
    const charcoal = PdfColor.fromInt(0xFF2C3539); // body text
    const slate = PdfColor.fromInt(0xFF2C3539); // secondary heading
    const teal = PdfColor.fromInt(0xFF8A9A86); // positive / progress
    const rose = PdfColor.fromInt(0xFFD98880); // healing / transient redness
    const gold = PdfColor.fromInt(0xFFD4AF37); // champagne gold
    const paper = PdfColor.fromInt(0xFFFDFBF7); // warm alabaster
    const cardSurface = PdfColor.fromInt(0xFFF8F6F0); // card background
    const divider = PdfColor.fromInt(0xFFE5E8E8); // borders
    const muted = PdfColor.fromInt(0xFF6D7476); // muted slate
    const redWarn = PdfColor.fromInt(0xFFD98880); // healing alert

    // Aliases kept so existing helpers (which still take these names)
    // continue to compile without further edits.
    const roseGold = rose;
    const champagne = paper;
    const textBrown = charcoal;
    const lightGrey = cardSurface;
    const mutedGrey = muted;
    const greenOk = teal;

    // Universal tracked item display resolver
    final trackedDisplay = await resolveTrackedItemDisplay(proc);
    final pdfTheme = await _buildPdfTheme();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 24),
        theme: pdfTheme,
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(
                color: PdfColor.fromInt(0xFFEAE0D6),
                width: 0.5,
              ),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'AestheticSkinTracker - Confidential Recovery Report',
                style: const pw.TextStyle(fontSize: 8, color: mutedGrey),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8, color: mutedGrey),
              ),
            ],
          ),
        ),
        build: (context) => [
          _clippedPdfPageSection([
            _pdfDisclaimerBox(navy, teal, gold, textBrown, paper, divider),
            pw.SizedBox(height: 14),
            // ── Clinical header bar ─────────────────────────────────────────
            pw.Container(
              decoration: const pw.BoxDecoration(color: navy),
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 12,
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'AESTHETICSKINTRACKER',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 9,
                          letterSpacing: 2.4,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Confidential Recovery Report',
                        style: const pw.TextStyle(
                          color: PdfColor.fromInt(0xFFB8CCDD),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        df.format(DateTime.now()),
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Report Date',
                        style: const pw.TextStyle(
                          color: PdfColor.fromInt(0xFFB8CCDD),
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // ── Prominent tracked item block (universal) ─────────────
            pw.Container(
              width: double.infinity,
              decoration: const pw.BoxDecoration(
                color: paper,
                border: pw.Border(
                  left: pw.BorderSide(color: rose, width: 4),
                  top: pw.BorderSide(color: divider, width: 0.6),
                  right: pw.BorderSide(color: divider, width: 0.6),
                  bottom: pw.BorderSide(color: divider, width: 0.6),
                ),
              ),
              padding: const pw.EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    trackedDisplay.categoryLabel.toUpperCase(),
                    style: pw.TextStyle(
                      color: rose,
                      fontSize: 8.5,
                      letterSpacing: 1.8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    trackedDisplay.title,
                    style: pw.TextStyle(
                      color: navy,
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 7),
                  pw.Text(
                    trackedDisplay.description,
                    style: pw.TextStyle(
                      color: slate,
                      fontSize: 11.5,
                      fontWeight: pw.FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),

            // ── Patient & procedure summary ────────────────────────────────
            pw.Container(
              decoration: pw.BoxDecoration(
                color: paper,
                border: pw.Border.all(color: divider, width: 0.5),
              ),
              padding: const pw.EdgeInsets.all(16),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Report Summary',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: navy,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'Patient and procedure record for this recovery interval.',
                    style: pw.TextStyle(
                      fontSize: 9,
                      color: muted,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  if (patientName.isNotEmpty) ...[
                    _labelValue('Patient', patientName, textBrown),
                    pw.SizedBox(height: 5),
                  ],
                  _labelValue(
                    'Procedure / Peptide',
                    trackedDisplay.title,
                    textBrown,
                  ),
                  pw.SizedBox(height: 5),
                  if (proc.provider.trim().isNotEmpty) ...[
                    _labelValue('Provider / Clinic', proc.provider, textBrown),
                    pw.SizedBox(height: 5),
                  ],
                  _labelValue('Recovery Period', dateRange, textBrown),
                  pw.SizedBox(height: 5),
                  _labelValue('Scans Recorded', '${scans.length}', textBrown),
                  pw.SizedBox(height: 5),
                  _labelValue(
                    'Journal Entries',
                    '${proc.journalEntries.length}',
                    textBrown,
                  ),
                  pw.SizedBox(height: 5),
                  _labelValue(
                    'Status',
                    proc.isCompleted ? 'Completed' : 'Active Recovery',
                    textBrown,
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // ── Recovery confidence score ──────────────────────────────────
            _confidenceGauge(confidence, roseGold, gold, textBrown, champagne),
            pw.SizedBox(height: 16),
          ]),

          // ══════════════════════════════════════════════════════════════
          // PAGE 2 — Key Metrics (baseline vs current)
          // ══════════════════════════════════════════════════════════════
          pw.NewPage(),
          _clippedPdfPageSection([
            if (baselineMetrics != null && latestMetrics != null) ...[
              if (isBblReport) ...[
                _bblResponseSummary(
                  baselineMetrics,
                  latestMetrics,
                  textBrown,
                  paper,
                  teal,
                  gold,
                  redWarn,
                  baselineRaw: scans.last.metrics,
                  latestRaw: scans.first.metrics,
                ),
                pw.SizedBox(height: 18),
              ],
              _sectionHeading('Key Metrics - Baseline vs Current', navy),
              pw.SizedBox(height: 6),
              pw.Text(
                isBblReport
                    ? 'BBL-focused signals from your latest standardized scan compared against baseline.'
                    : isBodyContouringReport
                    ? 'Body-contouring recovery signals from your latest standardized scan compared against baseline.'
                    : 'Headline progress metrics derived from your latest standardized scan compared against your baseline.',
                style: pw.TextStyle(
                  fontSize: 9.5,
                  color: muted,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
              pw.SizedBox(height: 12),
              _metricsTable(
                baselineMetrics,
                latestMetrics,
                textBrown,
                champagne,
                gold,
                lightGrey,
                greenOk,
                redWarn,
                procedureType: metricProcedureType,
                baselineRaw: scans.last.metrics,
                latestRaw: scans.first.metrics,
                trendStatus: _scanTrendStatusMap(scans.first),
                trendLockReason: _scanTrendLockReasonMap(scans.first),
              ),
            ],
          ]),

          // ══════════════════════════════════════════════════════════════
          // PAGE 3 — Visual evidence (Before & After) + Most Improved
          // ══════════════════════════════════════════════════════════════
          pw.NewPage(),

          _clippedPdfPageSection([
            // ── Before & After (enhanced visual evidence page) ─────────────
            _sectionHeading('Before & After', navy),
            pw.SizedBox(height: 6),
            pw.Text(
              'Standardized side-by-side comparison of baseline and most recent scan.',
              style: pw.TextStyle(
                fontSize: 9.5,
                color: muted,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
            pw.SizedBox(height: 14),
            // Result-window pill — clinical framing of the comparison interval.
            pw.Center(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 5,
                ),
                decoration: const pw.BoxDecoration(color: navy),
                child: pw.Text(
                  'RESULT WINDOW: ${DateTime.now().difference(input.procedure.startDate).inDays.abs()} DAYS',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.white,
                    letterSpacing: 1.4,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ),
            pw.SizedBox(height: 16),
            // Enlarged photo pair with premium framing.
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // ── Baseline ──
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.all(6),
                      decoration: pw.BoxDecoration(
                        color: paper,
                        border: pw.Border.all(color: navy, width: 1.2),
                      ),
                      child: (beforeImage != null)
                          ? pw.Container(
                              width: 206,
                              height: 276,
                              decoration: pw.BoxDecoration(
                                color: PdfColors.white,
                                border: pw.Border.all(
                                  color: divider,
                                  width: 0.6,
                                ),
                              ),
                              padding: const pw.EdgeInsets.all(3),
                              child: pw.Image(
                                beforeImage,
                                width: 200,
                                height: 270,
                                fit: pw.BoxFit.contain,
                                dpi: 180,
                              ),
                            )
                          : pw.Container(
                              width: 206,
                              height: 276,
                              decoration: pw.BoxDecoration(
                                color: cardSurface,
                                border: pw.Border.all(
                                  color: divider,
                                  width: 0.6,
                                ),
                              ),
                              child: pw.Center(
                                child: pw.Column(
                                  mainAxisAlignment:
                                      pw.MainAxisAlignment.center,
                                  children: [
                                    pw.Text(
                                      'No photo available',
                                      style: pw.TextStyle(
                                        fontSize: 9,
                                        color: mutedGrey,
                                        fontWeight: pw.FontWeight.bold,
                                      ),
                                    ),
                                    pw.SizedBox(height: 4),
                                    pw.Text(
                                      'No baseline photo available',
                                      style: const pw.TextStyle(
                                        fontSize: 8,
                                        color: mutedGrey,
                                      ),
                                      textAlign: pw.TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Container(
                      width: 218,
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: const pw.BoxDecoration(color: navy),
                      child: pw.Text(
                        'BASELINE',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      df.format(input.procedure.startDate),
                      style: pw.TextStyle(
                        fontSize: 9,
                        color: charcoal,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Procedure start',
                      style: const pw.TextStyle(fontSize: 8, color: muted),
                    ),
                  ],
                ),
                pw.Container(
                  width: 1,
                  height: 330,
                  margin: const pw.EdgeInsets.symmetric(horizontal: 15),
                  color: divider,
                ),
                // ── Current ──
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.all(6),
                      decoration: pw.BoxDecoration(
                        color: paper,
                        border: pw.Border.all(color: teal, width: 1.2),
                      ),
                      child: (afterImage != null)
                          ? pw.Container(
                              width: 206,
                              height: 276,
                              decoration: pw.BoxDecoration(
                                color: PdfColors.white,
                                border: pw.Border.all(
                                  color: divider,
                                  width: 0.6,
                                ),
                              ),
                              padding: const pw.EdgeInsets.all(3),
                              child: pw.Image(
                                afterImage,
                                width: 200,
                                height: 270,
                                fit: pw.BoxFit.contain,
                                dpi: 180,
                              ),
                            )
                          : pw.Container(
                              width: 206,
                              height: 276,
                              decoration: pw.BoxDecoration(
                                color: cardSurface,
                                border: pw.Border.all(
                                  color: divider,
                                  width: 0.6,
                                ),
                              ),
                              child: pw.Center(
                                child: pw.Column(
                                  mainAxisAlignment:
                                      pw.MainAxisAlignment.center,
                                  children: [
                                    pw.Text(
                                      'No photo available',
                                      style: pw.TextStyle(
                                        fontSize: 9,
                                        color: mutedGrey,
                                        fontWeight: pw.FontWeight.bold,
                                      ),
                                    ),
                                    pw.SizedBox(height: 4),
                                    pw.Text(
                                      'No progress photo yet',
                                      style: const pw.TextStyle(
                                        fontSize: 8,
                                        color: mutedGrey,
                                      ),
                                      textAlign: pw.TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Container(
                      width: 218,
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: const pw.BoxDecoration(color: teal),
                      child: pw.Text(
                        'CURRENT',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      df.format(DateTime.now()),
                      style: pw.TextStyle(
                        fontSize: 9,
                        color: charcoal,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Most recent scan',
                      style: const pw.TextStyle(fontSize: 8, color: muted),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Center(
              child: pw.Text(
                'Photographs are shown unretouched at consistent dimensions for progress comparison.',
                style: pw.TextStyle(
                  fontSize: 8,
                  color: muted,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            ),
            pw.SizedBox(height: 18),

            // ── Most Improved Metric (page 3 — paired with Before & After) ─
            if (baselineMetrics != null && latestMetrics != null) ...[
              _mostImprovedHighlight(
                baselineMetrics,
                latestMetrics,
                baselineRaw: scans.last.metrics,
                latestRaw: scans.first.metrics,
                procedureType: metricProcedureType,
                heroName: trackedDisplay.title,
              ),
            ],
          ]),

          // ══════════════════════════════════════════════════════════════
          // PAGE 4 — All Metrics Summary
          // ══════════════════════════════════════════════════════════════
          pw.NewPage(),

          // ── All Metrics Summary (page 4) ──────────────────────────────
          if (baselineMetrics != null && latestMetrics != null) ...[
            _sectionHeading('All Metrics Summary', navy),
            pw.SizedBox(height: 6),
            pw.Text(
              'Complete numeric breakdown of every captured metric, including procedure-specific measurements.',
              style: pw.TextStyle(
                fontSize: 9.5,
                color: muted,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
            pw.SizedBox(height: 12),
            _allMetricsTable(
              baselineMetrics,
              latestMetrics,
              textBrown,
              champagne,
              gold,
              lightGrey,
              greenOk,
              redWarn,
              procedureType: metricProcedureType,
              baselineRaw: scans.last.metrics,
              latestRaw: scans.first.metrics,
            ),
          ],

          // ══════════════════════════════════════════════════════════════
          // PAGE 5 — Clinical interpretation, timeline & disclaimer
          // ══════════════════════════════════════════════════════════════
          pw.NewPage(),

          // ── Surgeon instructions summary ───────────────────────────────
          if ((input.surgeonNotes ?? '').trim().isNotEmpty) ...[
            _sectionHeading('Surgeon Instructions Summary', navy),
            pw.SizedBox(height: 8),
            pw.Container(
              decoration: const pw.BoxDecoration(color: lightGrey),
              padding: const pw.EdgeInsets.all(12),
              child: pw.Text(
                _truncate(input.surgeonNotes!.trim(), 900),
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: textBrown,
                  lineSpacing: 1.4,
                ),
              ),
            ),
            pw.SizedBox(height: 18),
          ],

          // ── Clinical interpretation / AI recovery insights ─────────────
          if (input.insights.isNotEmpty) ...[
            _sectionHeading('Clinical Interpretation', navy),
            pw.SizedBox(height: 8),
            // Peptide / procedure-specific lead-in paragraph.
            pw.Container(
              decoration: pw.BoxDecoration(
                color: paper,
                border: pw.Border.all(color: divider, width: 0.5),
              ),
              padding: const pw.EdgeInsets.all(12),
              child: pw.Text(
                isBblReport
                    ? _bblClinicalLeadIn(scans.length)
                    : isBodyContouringReport
                    ? _bodyContouringClinicalLeadIn(
                        trackedDisplay.title,
                        scans.length,
                      )
                    : _peptideAwareLeadIn(trackedDisplay.title, scans.length),
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: charcoal,
                  lineSpacing: 1.4,
                ),
              ),
            ),
            pw.SizedBox(height: 10),
            ...input.insights.take(4).map((insight) {
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 10),
                child: pw.Container(
                  decoration: const pw.BoxDecoration(
                    color: paper,
                    border: pw.Border(
                      left: pw.BorderSide(color: rose, width: 3),
                      top: pw.BorderSide(color: divider, width: 0.5),
                      right: pw.BorderSide(color: divider, width: 0.5),
                      bottom: pw.BorderSide(color: divider, width: 0.5),
                    ),
                  ),
                  padding: const pw.EdgeInsets.all(12),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        isBblReport
                            ? ReportService._bblClinicalInsightSummary(
                                insight.summary,
                              )
                            : ReportService._clinicalInsightSummary(
                                insight.summary,
                                trackedDisplay.title,
                              ),
                        style: pw.TextStyle(
                          fontSize: 10.5,
                          fontWeight: pw.FontWeight.bold,
                          color: textBrown,
                        ),
                      ),
                      if (insight.highlights.isNotEmpty) ...[
                        pw.SizedBox(height: 6),
                        ...insight.highlights.map(
                          (h) => pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 3),
                            child: pw.Text(
                              '- ${isBblReport ? ReportService._bblClinicalInsightHighlight(h) : ReportService._clinicalInsightHighlight(h, trackedDisplay.title)}',
                              style: const pw.TextStyle(
                                fontSize: 9.5,
                                color: textBrown,
                              ),
                            ),
                          ),
                        ),
                      ],
                      pw.SizedBox(height: 8),
                      pw.Text(
                        'Important Note: This AI-generated assessment is for informational purposes only and does not replace professional medical advice. Please consult your provider for personalized recommendations.',
                        style: pw.TextStyle(
                          fontSize: 7.5,
                          color: textBrown,
                          fontStyle: pw.FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            pw.SizedBox(height: 18),
          ],

          // ── Recovery milestones ────────────────────────────────────────
          if (input.customPlanMilestones.isNotEmpty) ...[
            _sectionHeading('Recovery Timeline Milestones', navy),
            pw.SizedBox(height: 8),
            ...input.customPlanMilestones
                .take(8)
                .map(
                  (m) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 8),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(
                          width: 68,
                          child: pw.Text(
                            m.label,
                            style: pw.TextStyle(
                              fontSize: 9.5,
                              fontWeight: pw.FontWeight.bold,
                              color: roseGold,
                            ),
                          ),
                        ),
                        pw.SizedBox(width: 8),
                        pw.Expanded(
                          child: pw.Text(
                            m.description,
                            style: const pw.TextStyle(
                              fontSize: 9.5,
                              color: textBrown,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            pw.SizedBox(height: 18),
          ],

          if (isBblReport) ...[
            _sectionHeading('BBL Recovery Tips', navy),
            pw.SizedBox(height: 8),
            _bblRecoveryTips(textBrown, paper, teal, gold),
            pw.SizedBox(height: 18),
          ],

          // ── Scan timeline (page 4 — continues after Clinical
          // Interpretation so the closing page reads as a unified
          // "interpretation + history" narrative) ───────────────────────
          if (scans.isNotEmpty) ...[
            _sectionHeading(
              'Scan Timeline (${scans.length} total, showing last 6)',
              navy,
            ),
            pw.SizedBox(height: 12),
            _scanTimeline(
              scans.take(6).toList(),
              textBrown,
              champagne,
              lightGrey,
              roseGold,
              procedureType: metricProcedureType,
            ),
            pw.SizedBox(height: 22),
          ],

          // ── Disclaimer ──────────────────────────────────────────────────
          pw.Container(
            decoration: const pw.BoxDecoration(
              color: PdfColors.white, // Use white to avoid any visual artifacts
            ),
            padding: const pw.EdgeInsets.all(10),
            child: pw.Text(
              recoveryReportDisclaimerText,
              style: const pw.TextStyle(
                fontSize: 8.5,
                color: mutedGrey,
                lineSpacing: 1.3,
              ),
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // ── All Metrics Table (universal baseline-vs-current summary) ─────────────

  static pw.Widget _allMetricsTable(
    SkinMetrics baseline,
    SkinMetrics latest,
    PdfColor textBrown,
    PdfColor champagne,
    PdfColor gold,
    PdfColor lightGrey,
    PdfColor greenOk,
    PdfColor redWarn, {
    String? procedureType,
    Map<String, double>? baselineRaw,
    Map<String, double>? latestRaw,
  }) {
    final allDefs = clinicalMetricsForProcedure(procedureType);

    pw.Widget headerCell(String text) => pw.Container(
      color: const PdfColor.fromInt(0xFF1E2A3A),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: pw.Text(
        text.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
          letterSpacing: 0.8,
        ),
      ),
    );

    pw.Widget dataCell(String text, {PdfColor? textColor, bool bold = false}) =>
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: pw.Text(
            text,
            style: pw.TextStyle(
              fontSize: 9.5,
              color: textColor ?? textBrown,
              fontWeight: bold ? pw.FontWeight.bold : null,
            ),
          ),
        );

    final List<pw.TableRow> metricRows = [];
    for (var i = 0; i < allDefs.length; i++) {
      final def = allDefs[i];
      final b = def.valueFromRaw(baselineRaw, baseline);
      final l = def.valueFromRaw(latestRaw, latest);
      if (b == null || l == null) continue;
      final pct = metricPctChange(b, l, lowerIsBetter: def.lowerIsBetter);
      final isImprovement = pct >= 0;
      final sign = isImprovement ? '+' : '-';
      final changeText = '$sign${pct.abs().toStringAsFixed(1)}%';
      final isImproving = isImprovement && pct.abs() > 0.5;
      final isWorsening = !isImprovement && pct.abs() > 0.5;
      final clinicalSig = isImproving
          ? 'Improvement of ${pct.abs().toStringAsFixed(1)}% - clinically favorable.'
          : isWorsening
          ? 'Decline of ${pct.abs().toStringAsFixed(1)}% - monitor closely.'
          : 'Stable measurement - within expected range.';
      final recommendation = isImproving
          ? 'Continue your current regimen.'
          : isWorsening
          ? 'Consult your provider for tailored recommendations.'
          : 'Maintain current protocol.';
      final bg = i.isEven ? PdfColors.white : lightGrey;
      metricRows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(color: bg),
          children: [
            dataCell(
              def.label,
              bold: true,
              textColor: const PdfColor.fromInt(0xFF1E2A3A),
            ),
            dataCell(b.toStringAsFixed(1)),
            dataCell(l.toStringAsFixed(1)),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 7,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    changeText,
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: isImprovement ? greenOk : redWarn,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    clinicalSig,
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: const PdfColor.fromInt(0xFF7A6F66),
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    recommendation,
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColor.fromInt(0xFF2F2F33),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (metricRows.isEmpty) {
      return pw.Container(
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          border: pw.Border.all(
            color: const PdfColor.fromInt(0xFFD9D2C9),
            width: 0.5,
          ),
        ),
        padding: const pw.EdgeInsets.all(12),
        child: pw.Text(
          'No quantitative metrics available for this protocol yet. '
          'Take at least one scan to enable baseline-vs-current analysis.',
          style: const pw.TextStyle(
            fontSize: 10,
            color: PdfColor.fromInt(0xFF2F2F33),
          ),
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(
        color: const PdfColor.fromInt(0xFFD9D2C9),
        width: 0.5,
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.8),
        1: pw.FlexColumnWidth(1.3),
        2: pw.FlexColumnWidth(1.3),
        3: pw.FlexColumnWidth(3.4),
      },
      children: [
        pw.TableRow(
          children: [
            headerCell('Metric'),
            headerCell('Baseline'),
            headerCell('Current'),
            headerCell('Recommendations'),
          ],
        ),
        ...metricRows,
      ],
    );
  }

  static String _keyMetricChangeKey(String label) {
    final normalized = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return '${normalized}_change';
  }

  // ── PDF widget helpers ─────────────────────────────────────────────────────

  static pw.Widget _clippedPdfPageSection(List<pw.Widget> children) {
    return pw.ClipRect(
      child: pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(0),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  static pw.Widget _pdfDisclaimerBox(
    PdfColor navy,
    PdfColor teal,
    PdfColor gold,
    PdfColor textBrown,
    PdfColor paper,
    PdfColor divider,
  ) {
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFF1FAF9),
        border: pw.Border(
          left: pw.BorderSide(color: teal, width: 5),
          top: pw.BorderSide(color: teal, width: 1),
          right: pw.BorderSide(color: teal, width: 1),
          bottom: pw.BorderSide(color: gold, width: 1.2),
        ),
      ),
      padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(width: 8, height: 8, color: teal),
              pw.SizedBox(width: 8),
              pw.Text(
                'CLINICAL USE DISCLAIMER',
                style: pw.TextStyle(
                  color: navy,
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 7),
          pw.Text(
            recoveryReportDisclaimerText,
            style: pw.TextStyle(
              fontSize: 10.2,
              color: textBrown,
              lineSpacing: 1.42,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _bblResponseSummary(
    SkinMetrics baseline,
    SkinMetrics latest,
    PdfColor textBrown,
    PdfColor paper,
    PdfColor teal,
    PdfColor gold,
    PdfColor redWarn, {
    Map<String, double>? baselineRaw,
    Map<String, double>? latestRaw,
  }) {
    const navy = PdfColor.fromInt(0xFF1E2A3A);
    const muted = PdfColor.fromInt(0xFF7A6F66);
    const divider = PdfColor.fromInt(0xFFD9D2C9);
    final labels = {
      'Fat Retention',
      'Skin Retraction & Tightness',
      'Fibrosis/Firmness',
      'Volume Satisfaction',
    };
    final rows =
        <
          ({ClinicalMetricDef def, double baseline, double latest, double pct})
        >[];
    for (final def in clinicalMetricsForProcedure('BBL')) {
      if (!labels.contains(def.label)) continue;
      final b = def.valueFromRaw(baselineRaw, baseline);
      final l = def.valueFromRaw(latestRaw, latest);
      if (b == null || l == null) continue;
      rows.add((
        def: def,
        baseline: b,
        latest: l,
        pct: metricPctChange(b, l, lowerIsBetter: def.lowerIsBetter),
      ));
    }

    final contourScore = _overallContourImprovement(
      baseline,
      latest,
      baselineRaw: baselineRaw,
      latestRaw: latestRaw,
    );

    pw.Widget metricTile(
      ({ClinicalMetricDef def, double baseline, double latest, double pct}) row,
    ) {
      final improving = row.pct >= 0;
      final color = improving ? teal : redWarn;
      final arrow = improving ? 'UP' : 'DOWN';
      final changeText =
          '${improving ? '+' : '-'}${row.pct.abs().toStringAsFixed(1)}%';
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          border: pw.Border.all(color: divider, width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              row.def.label,
              style: pw.TextStyle(
                fontSize: 9.5,
                color: navy,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${row.baseline.toStringAsFixed(1)} -> ${row.latest.toStringAsFixed(1)}',
                  style: const pw.TextStyle(fontSize: 8.5, color: muted),
                ),
                pw.Text(
                  '$arrow  $changeText',
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    color: color,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFF1FAF9),
        border: pw.Border(
          left: pw.BorderSide(color: teal, width: 5),
          top: pw.BorderSide(color: teal, width: 0.9),
          right: const pw.BorderSide(color: divider, width: 0.7),
          bottom: pw.BorderSide(color: gold, width: 1.2),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'BBL RESPONSE SUMMARY',
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: teal,
                      letterSpacing: 1.4,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Fat graft, contour, firmness, and satisfaction signals.',
                    style: const pw.TextStyle(fontSize: 9, color: muted),
                  ),
                ],
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: pw.BoxDecoration(color: gold),
                child: pw.Text(
                  '${contourScore.round()}% CONTOUR',
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          _contourProgressBar(contourScore, teal, gold, divider),
          pw.SizedBox(height: 14),
          pw.Wrap(
            spacing: 8,
            runSpacing: 8,
            children: rows
                .map((row) => pw.SizedBox(width: 238, child: metricTile(row)))
                .toList(),
          ),
        ],
      ),
    );
  }

  static pw.Widget _contourProgressBar(
    double score,
    PdfColor teal,
    PdfColor gold,
    PdfColor divider,
  ) {
    return pw.LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints?.maxWidth ?? 480.0;
        final fillWidth = totalWidth * (score / 100).clamp(0.0, 1.0);
        return pw.Container(
          height: 14,
          color: divider,
          child: pw.Row(
            children: [
              if (fillWidth > 0)
                pw.Container(
                  width: fillWidth,
                  height: 14,
                  color: score >= 70 ? teal : gold,
                ),
            ],
          ),
        );
      },
    );
  }

  static double _overallContourImprovement(
    SkinMetrics baseline,
    SkinMetrics latest, {
    Map<String, double>? baselineRaw,
    Map<String, double>? latestRaw,
  }) {
    final weightedLabels = <String, double>{
      'Fat Retention': 0.30,
      'Skin Retraction & Tightness': 0.25,
      'Fibrosis/Firmness': 0.20,
      'Volume Satisfaction': 0.25,
    };
    var totalWeight = 0.0;
    var weightedImprovement = 0.0;
    for (final def in clinicalMetricsForProcedure('BBL')) {
      final weight = weightedLabels[def.label];
      if (weight == null) continue;
      final b = def.valueFromRaw(baselineRaw, baseline);
      final l = def.valueFromRaw(latestRaw, latest);
      if (b == null || l == null) continue;
      weightedImprovement +=
          metricPctChange(b, l, lowerIsBetter: def.lowerIsBetter) * weight;
      totalWeight += weight;
    }
    if (totalWeight == 0) return 35;
    final avg = weightedImprovement / totalWeight;
    return (50 + (avg * 1.8)).clamp(0.0, 100.0).toDouble();
  }

  static pw.Widget _bblRecoveryTips(
    PdfColor textBrown,
    PdfColor paper,
    PdfColor teal,
    PdfColor gold,
  ) {
    const divider = PdfColor.fromInt(0xFFD9D2C9);
    const navy = PdfColor.fromInt(0xFF1E2A3A);
    final tips = [
      'Wear compression exactly as directed; many BBL protocols require near-continuous garment use early on while protecting grafted areas from excess pressure.',
      'Avoid direct sitting on the buttocks until your surgeon clears it. Use a BBL pillow under the thighs when sitting is unavoidable.',
      'Begin lymphatic drainage massage only after provider clearance; timing varies by drain status, incision healing, and swelling pattern.',
      'Prioritize protein, hydration, and stable calories. Aggressive dieting during months 1-3 can compromise fat retention.',
    ];
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: pw.BoxDecoration(
        color: paper,
        border: pw.Border(
          left: pw.BorderSide(color: gold, width: 4),
          top: const pw.BorderSide(color: divider, width: 0.5),
          right: const pw.BorderSide(color: divider, width: 0.5),
          bottom: const pw.BorderSide(color: divider, width: 0.5),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Provider instructions override these general BBL recovery reminders.',
            style: pw.TextStyle(
              fontSize: 9.5,
              color: navy,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          ...tips.map(
            (tip) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 5,
                    height: 5,
                    margin: const pw.EdgeInsets.only(top: 4),
                    color: teal,
                  ),
                  pw.SizedBox(width: 7),
                  pw.Expanded(
                    child: pw.Text(
                      tip,
                      style: pw.TextStyle(
                        fontSize: 9.2,
                        color: textBrown,
                        lineSpacing: 1.35,
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

  static pw.Widget _sectionHeading(String text, PdfColor color) {
    // Editorial / medical-journal section header: a short rose accent bar,
    // a strong title, and a hairline divider beneath. Generous breathing
    // room is provided by the caller below this widget.
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 36,
          height: 3.5,
          color: const PdfColor.fromInt(0xFFB0717A),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: color,
            letterSpacing: 0.4,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Container(height: 0.6, color: const PdfColor.fromInt(0xFFD9D2C9)),
      ],
    );
  }

  static pw.Widget _labelValue(String label, String value, PdfColor textBrown) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 115,
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 10.5,
              fontWeight: pw.FontWeight.bold,
              color: textBrown,
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(fontSize: 10.5, color: textBrown),
          ),
        ),
      ],
    );
  }

  static pw.Widget _confidenceGauge(
    double confidence,
    PdfColor roseGold,
    PdfColor gold,
    PdfColor textBrown,
    PdfColor champagne,
  ) {
    // Clinical color tokens (avoids extra params from caller).
    const navy = PdfColor.fromInt(0xFF1E2A3A);
    const teal = PdfColor.fromInt(0xFF3E7C7E);
    const rose = PdfColor.fromInt(0xFFB0717A);
    const goldCl = PdfColor.fromInt(0xFFC8A96A);
    const muted = PdfColor.fromInt(0xFF7A6F66);
    const divider = PdfColor.fromInt(0xFFD9D2C9);
    const paper = PdfColor.fromInt(0xFFFAF8F5);

    final score = confidence.round();
    final String tierLabel;
    final String tierDetail;
    final PdfColor barColor;
    if (confidence >= 75) {
      tierLabel = 'STRONG PROGRESS';
      tierDetail =
          'Your scan density, measured metric improvement, and clinical '
          'insight quality all align with a healthy, well-tracked '
          'recovery. Keep doing what you are doing - this is the kind '
          'of consistency that produces meaningful long-term outcomes.';
      barColor = teal;
    } else if (confidence >= 50) {
      tierLabel = 'STEADY PROGRESS';
      tierDetail =
          'Most of your tracked indicators are moving in the right '
          'direction. Continuing to scan on a regular cadence and add '
          'journal context will sharpen the picture and likely push '
          'this score higher over time.';
      barColor = goldCl;
    } else {
      tierLabel = 'EARLY STAGE';
      tierDetail =
          'This is a normal starting point. Recovery and protocol data '
          'become significantly more informative once a few more scans '
          'and journal entries are recorded - every additional data '
          'point materially improves the accuracy of this score.';
      barColor = rose;
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: paper,
        border: pw.Border(
          left: pw.BorderSide(color: barColor, width: 3.5),
          top: const pw.BorderSide(color: divider, width: 0.5),
          right: const pw.BorderSide(color: divider, width: 0.5),
          bottom: const pw.BorderSide(color: divider, width: 0.5),
        ),
      ),
      padding: const pw.EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'RECOVERY CONFIDENCE SCORE',
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      letterSpacing: 1.6,
                      color: muted,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(
                        width: 9,
                        height: 9,
                        decoration: pw.BoxDecoration(
                          color: barColor,
                          shape: pw.BoxShape.circle,
                        ),
                      ),
                      pw.SizedBox(width: 6),
                      pw.Text(
                        tierLabel,
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: navy,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    '$score',
                    style: pw.TextStyle(
                      fontSize: 36,
                      fontWeight: pw.FontWeight.bold,
                      color: barColor,
                    ),
                  ),
                  pw.SizedBox(width: 3),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 7),
                    child: pw.Text(
                      '/ 100',
                      style: pw.TextStyle(
                        fontSize: 10,
                        color: muted,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          // Progress bar (rounded ends via inner caps)
          pw.LayoutBuilder(
            builder: (context, constraints) {
              final totalWidth = constraints?.maxWidth ?? 460.0;
              final fillWidth = totalWidth * (confidence / 100).clamp(0.0, 1.0);
              final remainWidth = (totalWidth - fillWidth).clamp(
                0.0,
                totalWidth,
              );
              return pw.Row(
                children: [
                  if (fillWidth > 0)
                    pw.Container(width: fillWidth, height: 9, color: barColor),
                  if (remainWidth > 0)
                    pw.Container(width: remainWidth, height: 9, color: divider),
                ],
              );
            },
          ),
          pw.SizedBox(height: 6),
          // Tier scale legend (clinical 3-band reference)
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  '0  •  Early stage',
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    color: muted,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  '50  •  Steady',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    color: muted,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  'Strong  •  100',
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    color: muted,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Container(height: 0.5, color: divider),
          pw.SizedBox(height: 10),
          pw.Text(
            'HOW THIS SCORE IS CALCULATED',
            style: pw.TextStyle(
              fontSize: 8,
              letterSpacing: 1.4,
              fontWeight: pw.FontWeight.bold,
              color: muted,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'The Recovery Confidence Score blends three weighted signals: '
            'scan density (frequency and recency of your recorded photos), '
            'measured metric improvement vs. baseline, and the strength '
            'of the AI-derived clinical insights observed in your scans.',
            style: pw.TextStyle(
              fontSize: 9,
              color: textBrown,
              lineSpacing: 1.4,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.RichText(
            text: pw.TextSpan(
              children: [
                pw.TextSpan(
                  text: 'Your result: ',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: navy,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.TextSpan(
                  text: tierDetail,
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: textBrown,
                    fontStyle: pw.FontStyle.italic,
                    lineSpacing: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Map<String, dynamic> _asDynamicMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  /// Extracts the backend's per-metric trend_status map from [scan]'s raw
  /// payload (preferring a nested luxePayload if present), so the PDF
  /// report's metric table can defer to it instead of recomputing trend
  /// direction from a raw percent change.
  static Map<String, String> _scanTrendStatusMap(ScanHistoryEntry? scan) {
    if (scan == null) return const {};
    final payload = _asDynamicMap(scan.rawPayload);
    final nestedLuxe = _asDynamicMap(payload['luxePayload']);
    final source = nestedLuxe['trend_status'] != null
        ? _asDynamicMap(nestedLuxe['trend_status'])
        : _asDynamicMap(payload['trend_status']);
    return source.map((key, value) => MapEntry(key, value.toString()));
  }

  static Map<String, String> _scanTrendLockReasonMap(ScanHistoryEntry? scan) {
    if (scan == null) return const {};
    final payload = _asDynamicMap(scan.rawPayload);
    final nestedLuxe = _asDynamicMap(payload['luxePayload']);
    final source = nestedLuxe['trend_lock_reasons'] != null
        ? _asDynamicMap(nestedLuxe['trend_lock_reasons'])
        : _asDynamicMap(payload['trend_lock_reasons']);
    return source.map((key, value) => MapEntry(key, value.toString()));
  }

  static pw.Widget _metricsTable(
    SkinMetrics baseline,
    SkinMetrics latest,
    PdfColor textBrown,
    PdfColor champagne,
    PdfColor gold,
    PdfColor lightGrey,
    PdfColor greenOk,
    PdfColor redWarn, {
    String? procedureType,
    Map<String, double>? baselineRaw,
    Map<String, double>? latestRaw,
    Map<String, String>? trendStatus,
    Map<String, String>? trendLockReason,
  }) {
    // Clinical color tokens (kept here to avoid extra params from caller).
    const navy = PdfColor.fromInt(0xFF1E2A3A);
    const charcoal = PdfColor.fromInt(0xFF2F2F33);
    const muted = PdfColor.fromInt(0xFF7A6F66);
    const paper = PdfColor.fromInt(0xFFFAF8F5);
    const divider = PdfColor.fromInt(0xFFD9D2C9);

    // Procedure-aware metric selection driven by ProcedureIntelligence -
    // returns the 5-7 most clinically relevant metrics for this category.
    final defs = clinicalMetricsForProcedure(procedureType);

    // Build rows using valueFromRaw so body-composition metrics (weight,
    // body fat %, waist, lean mass, etc.) read from the raw scan metrics
    // map rather than collapsing to the 5.0 SkinMetrics placeholder.
    final List<Map<String, dynamic>> rows = [];
    for (final def in defs) {
      final b = def.valueFromRaw(baselineRaw ?? const {}, baseline);
      final l = def.valueFromRaw(latestRaw ?? const {}, latest);
      // Skip metrics that don't apply for this scan type (null → no raw data
      // and no SkinMetrics mapping).
      if (b == null || l == null) continue;
      rows.add({
        'name': def.label,
        'baseline': b,
        'latest': l,
        'lowerBetter': def.lowerIsBetter,
        'explanation': def.clinicalContext,
        'suggestionImproving': def.suggestionImproving,
        'suggestionWorsening': def.suggestionWorsening,
        'formatter': def.valueFormatter,
        'sourceKey': def.sourceKey,
      });
    }

    pw.Widget headerCell(String text, {bool center = false}) => pw.Container(
      color: navy,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      alignment: center ? pw.Alignment.center : pw.Alignment.centerLeft,
      child: pw.Text(
        text.toUpperCase(),
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
          letterSpacing: 0.5,
        ),
      ),
    );

    pw.Widget dataCell(
      String text, {
      PdfColor? textColor,
      bool bold = false,
      bool center = false,
    }) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      alignment: center ? pw.Alignment.center : pw.Alignment.centerLeft,
      child: pw.Text(
        text,
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 10,
          color: textColor ?? charcoal,
          fontWeight: bold ? pw.FontWeight.bold : null,
          lineSpacing: 1.5,
        ),
      ),
    );

    String fmt(Map<String, dynamic> r, double v) {
      final fn = r['formatter'] as String Function(double)?;
      if (fn != null) return fn(v);
      return v.toStringAsFixed(1);
    }

    final List<pw.TableRow> metricRows = [];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final b = row['baseline'] as double;
      final l = row['latest'] as double;
      final lowerBetter = row['lowerBetter'] as bool;
      final pct = metricPctChange(b, l, lowerIsBetter: lowerBetter);
      final isImprovement = pct >= 0;
      final sign = isImprovement ? '+' : '-';
      final changeText = '$sign${pct.abs().toStringAsFixed(1)}%';
      // Trend wording (IMPROVING/DECLINING/STABLE) must defer to the
      // backend's honesty-gated trend_status for this metric when
      // available — never a raw percent-change threshold. When no
      // backend verdict exists for this metric (e.g. no prior comparable
      // scan, or the backend judged the comparison invalid), fall back to
      // a neutral "TRACKING" label rather than guessing a direction.
      final sourceKey = row['sourceKey'] as String?;
      final canonicalKey = sourceKey == null
          ? null
          : shortMetricKeyToCanonical[sourceKey];
      final backendTrendStatus = canonicalKey == null
          ? null
          : trendStatus?[canonicalKey];
      final backendTrendLockReason = canonicalKey == null
          ? null
          : trendLockReason?[canonicalKey];
      final resolvedTrend = resolveTrendLabel(
        trendStatus: backendTrendStatus,
        trendLockReason: backendTrendLockReason,
      );
      final isImproving = resolvedTrend?.isImproved ?? false;
      final isWorsening = resolvedTrend?.isWorsened ?? false;
      final isStableVerdict = resolvedTrend?.isStable ?? false;
      final hasBackendVerdict = resolvedTrend != null;
      final suggestion = isImproving
          ? (row['suggestionImproving'] as String? ?? '')
          : isWorsening
          ? (row['suggestionWorsening'] as String? ?? '')
          : (row['explanation'] as String? ?? '');
      // Keep recommendation crisp: first sentence only, capped length.
      String shortSuggestion = suggestion.trim();
      final dotIdx = shortSuggestion.indexOf('. ');
      if (dotIdx > 0) {
        shortSuggestion = shortSuggestion.substring(0, dotIdx + 1);
      }
      if (shortSuggestion.length > 90) {
        shortSuggestion = '${shortSuggestion.substring(0, 87).trimRight()}...';
      } else if (shortSuggestion.isNotEmpty && !shortSuggestion.endsWith('.')) {
        shortSuggestion = '$shortSuggestion.';
      }
      final statusLabel = isImproving
          ? 'IMPROVING'
          : isWorsening
          ? 'DECLINING'
          : isStableVerdict
          ? (resolvedTrend?.lockShortLabel?.toUpperCase() ?? 'STABLE')
          : hasBackendVerdict && !resolvedTrend!.isInsufficientSignal
          ? 'STABLE'
          : 'TRACKING';
      final statusColor = isImproving
          ? greenOk
          : isWorsening
          ? redWarn
          : muted;

      // Zebra striping for readability in the printed report.
      final bg = i.isEven ? PdfColors.white : paper;
      metricRows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(color: bg),
          children: [
            dataCell(row['name'] as String, bold: true, textColor: navy),
            dataCell(fmt(row, b), center: true),
            dataCell(fmt(row, l), center: true),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        changeText,
                        style: pw.TextStyle(
                          fontSize: 13,
                          color: statusColor,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Text(
                        statusLabel,
                        style: pw.TextStyle(
                          fontSize: 8,
                          color: statusColor,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text(
                    shortSuggestion,
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: charcoal,
                      lineSpacing: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (metricRows.isEmpty) {
      return pw.Container(
        decoration: pw.BoxDecoration(
          color: paper,
          border: pw.Border.all(color: divider, width: 0.5),
        ),
        padding: const pw.EdgeInsets.all(12),
        child: pw.Text(
          'No quantitative metrics available for this protocol yet. '
          'Take at least one scan to enable baseline-vs-current analysis.',
          style: const pw.TextStyle(fontSize: 10, color: charcoal),
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: divider, width: 0.5),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      columnWidths: const {
        0: pw.FlexColumnWidth(2.3),
        1: pw.FlexColumnWidth(1.5),
        2: pw.FlexColumnWidth(1.5),
        3: pw.FlexColumnWidth(4.0),
      },
      children: [
        pw.TableRow(
          children: [
            headerCell('Metric'),
            headerCell('Baseline', center: true),
            headerCell('Current', center: true),
            headerCell('Recommendations'),
          ],
        ),
        ...metricRows,
      ],
    );
  }

  /// "Most Improved Metric" highlight box - premium clinical touch.
  static pw.Widget _mostImprovedHighlight(
    SkinMetrics baseline,
    SkinMetrics latest, {
    Map<String, double>? baselineRaw,
    Map<String, double>? latestRaw,
    String? procedureType,
    String heroName = '',
  }) {
    const navy = PdfColor.fromInt(0xFF1E2A3A);
    const teal = PdfColor.fromInt(0xFF3E7C7E);
    const paper = PdfColor.fromInt(0xFFFAF8F5);
    const charcoal = PdfColor.fromInt(0xFF2F2F33);
    const muted = PdfColor.fromInt(0xFF7A6F66);

    final defs = clinicalMetricsForProcedure(procedureType);
    double bestPct = 0;
    ClinicalMetricDef? bestDef;
    for (final def in defs) {
      final b = def.valueFromRaw(baselineRaw ?? const {}, baseline);
      final l = def.valueFromRaw(latestRaw ?? const {}, latest);
      if (b == null || l == null) continue;
      final pct = metricPctChange(b, l, lowerIsBetter: def.lowerIsBetter);
      if (pct > bestPct) {
        bestPct = pct;
        bestDef = def;
      }
    }

    if (bestDef == null || bestPct < 1.0) {
      // Not enough improvement to highlight - return empty placeholder.
      return pw.SizedBox.shrink();
    }

    final profile = _peptideProfileFor(heroName);
    // Tier-aware adjective so the headline scales with the result.
    final String resultTier = bestPct >= 15
        ? 'Outstanding'
        : bestPct >= 7
        ? 'Significant'
        : 'Encouraging';

    return pw.Container(
      width: double.infinity,
      decoration: const pw.BoxDecoration(
        color: paper,
        border: pw.Border(
          left: pw.BorderSide(color: teal, width: 4),
          top: pw.BorderSide(color: PdfColor.fromInt(0xFFD9D2C9), width: 0.5),
          right: pw.BorderSide(color: PdfColor.fromInt(0xFFD9D2C9), width: 0.5),
          bottom: pw.BorderSide(
            color: PdfColor.fromInt(0xFFD9D2C9),
            width: 0.5,
          ),
        ),
      ),
      padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'MOST IMPROVED METRIC',
                style: pw.TextStyle(
                  fontSize: 8,
                  color: teal,
                  letterSpacing: 1.8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: const pw.BoxDecoration(color: teal),
                child: pw.Text(
                  resultTier.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    color: PdfColors.white,
                    letterSpacing: 1.2,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                bestDef.label,
                style: pw.TextStyle(
                  fontSize: 16,
                  color: navy,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Text(
                  '+${bestPct.toStringAsFixed(1)}%  since baseline',
                  style: pw.TextStyle(
                    fontSize: 11,
                    color: teal,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            bestDef.suggestionImproving,
            style: const pw.TextStyle(
              fontSize: 9.5,
              color: charcoal,
              lineSpacing: 1.4,
            ),
          ),
          pw.SizedBox(height: 6),
          // Peptide-specific clinical note tying the result to the
          // protocol's mechanism / success marker.
          pw.Text(
            'Evidence note for ${profile.canonicalName}: '
            '${profile.successMarker}. The improvement shown here is '
            'consistent with that expected ${profile.canonicalName} '
            'response pattern.',
            style: pw.TextStyle(
              fontSize: 8.5,
              color: muted,
              fontStyle: pw.FontStyle.italic,
              lineSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /// Peptide / procedure-aware lead-in paragraph for the Clinical
  /// Interpretation section. Pulls language from the peptide profile so
  /// each report sounds tailored to the specific protocol.
  static String _peptideAwareLeadIn(String heroName, int scanCount) {
    final p = _peptideProfileFor(heroName);
    final scans =
        '$scanCount scan${scanCount == 1 ? '' : 's'} recorded in this window';
    return 'This Clinical Interpretation is generated specifically for '
        '${p.canonicalName}, a ${p.mechanism}. The assessment below is '
        'derived from $scans and focuses on the indicators most relevant '
        'to ${p.canonicalName}: ${p.expectedEffects}. '
        '${p.clinicalContext} Findings should be reviewed alongside '
        'professional medical guidance.';
  }

  static String _bblClinicalLeadIn(int scanCount) {
    final scans =
        '$scanCount scan${scanCount == 1 ? '' : 's'} recorded in this window';
    return 'This Clinical Interpretation is tailored to BBL recovery and gluteal fat transfer tracking. '
        'The assessment is derived from $scans and focuses on body-contour signals: fat retention, volume satisfaction, skin retraction, swelling resolution, bruising clearance, contour evenness, and fibrosis or firmness. '
        'Findings should be reviewed alongside surgeon instructions, especially compression use, sitting restrictions, nutrition, and lymphatic drainage timing.';
  }

  static String _bodyContouringClinicalLeadIn(String heroName, int scanCount) {
    final scans =
        '$scanCount scan${scanCount == 1 ? '' : 's'} recorded in this window';
    return 'This Clinical Interpretation is tailored to $heroName using general body-contouring recovery logic. '
        'The assessment is derived from $scans and focuses on swelling, bruising, firmness or fibrosis, skin retraction, pigment change, contour evenness, and overall healing. '
        'Procedure-specific restrictions vary, so findings should be reviewed alongside provider instructions for compression, positioning, activity, nutrition, and lymphatic drainage timing.';
  }

  static String _cleanBblLanguage(String text) {
    var cleaned = text.trim();
    final replacements = <RegExp, String>{
      RegExp(r'\bwrinkles?\b', caseSensitive: false): 'skin retraction',
      RegExp(r'\brhytids?\b', caseSensitive: false): 'skin retraction',
      RegExp(r'\bfine lines?\b', caseSensitive: false): 'skin retraction',
      RegExp(r'\bfacial\b', caseSensitive: false): 'body-contour',
      RegExp(r'\bface\b', caseSensitive: false): 'treated area',
      RegExp(r'\bskin health\b', caseSensitive: false): 'contour recovery',
      RegExp(r'\bskin quality\b', caseSensitive: false): 'contour quality',
      RegExp(r'\bpores?\b', caseSensitive: false): 'fibrosis/firmness',
      RegExp(r'\berythema\b', caseSensitive: false): 'post-op swelling',
      RegExp(r'\bredness\b', caseSensitive: false): 'post-op swelling',
      RegExp(r'\btexture\b', caseSensitive: false): 'contour evenness',
      RegExp(r'\belasticity\b', caseSensitive: false):
          'fat retention and skin retraction',
    };
    for (final entry in replacements.entries) {
      cleaned = cleaned.replaceAll(entry.key, entry.value);
    }
    return cleaned;
  }

  static String _bblClinicalInsightSummary(String summary) {
    final cleaned = _cleanBblLanguage(summary);
    final lower = cleaned.toLowerCase();
    if (lower.contains('strong') ||
        lower.contains('excellent') ||
        lower.contains('improv')) {
      return 'Assessment: BBL recovery signals are moving in a favorable direction, with the most relevant contour indicators supporting continued progress.';
    }
    if (lower.contains('slow') ||
        lower.contains('declin') ||
        lower.contains('worsen') ||
        lower.contains('concern')) {
      return 'Assessment: BBL recovery signals need closer monitoring. Review compression adherence, pressure avoidance, swelling pattern, and provider-cleared lymphatic massage timing.';
    }
    return 'Assessment: $cleaned';
  }

  static String _bblClinicalInsightHighlight(String highlight) {
    final cleaned = _cleanBblLanguage(highlight);
    final lower = cleaned.toLowerCase();
    if (lower.contains('fat retention') || lower.contains('volume')) {
      return '$cleaned - supports graft-volume tracking and overall BBL shape stability.';
    }
    if (lower.contains('fibrosis') || lower.contains('firmness')) {
      return '$cleaned - important for monitoring post-liposuction firmness and provider-cleared massage response.';
    }
    if (lower.contains('swelling') || lower.contains('bruising')) {
      return '$cleaned - consistent with body-contour recovery monitoring during the early healing window.';
    }
    if (lower.contains('contour') || lower.contains('retraction')) {
      return '$cleaned - directly relevant to contour settling and tissue retraction after BBL.';
    }
    return '$cleaned - relevant to BBL contour recovery.';
  }

  /// Refines AI insight summary to sound like a clinician, with disclaimer.
  static String _clinicalInsightSummary(
    String summary, [
    String heroName = '',
  ]) {
    final p = _peptideProfileFor(heroName);
    final lower = summary.toLowerCase();
    String assessment;
    if (lower.contains('excellent') ||
        lower.contains('exceed') ||
        lower.contains('strong')) {
      assessment =
          'Response to ${p.canonicalName} is exceeding expected '
          'benchmarks for this stage of the protocol.';
    } else if (lower.contains('well') ||
        lower.contains('on track') ||
        lower.contains('normal')) {
      assessment =
          'Response to ${p.canonicalName} is within expected clinical '
          'parameters for this stage of the protocol.';
    } else if (lower.contains('slow') ||
        lower.contains('plateau') ||
        lower.contains('stall')) {
      assessment =
          'Response to ${p.canonicalName} is progressing more slowly '
          'than typical. Consider reviewing adherence and contributing '
          'lifestyle factors with your provider.';
    } else {
      assessment = summary;
    }
    return 'Assessment: $assessment';
  }

  /// Refines AI insight highlights to sound clinical and tailored to the
  /// peptide.
  static String _clinicalInsightHighlight(
    String highlight, [
    String heroName = '',
  ]) {
    final p = _peptideProfileFor(heroName);
    final lower = highlight.toLowerCase();
    String refined = highlight;
    if (lower.contains('redness') || lower.contains('inflammation')) {
      refined =
          '${highlight.replaceAll('Redness', 'Erythema (redness)')} - '
          'consistent with expected inflammatory resolution.';
    } else if (lower.contains('texture')) {
      refined =
          '$highlight - supports improved epidermal barrier '
          'function and surface regularity.';
    } else if (lower.contains('elasticity') || lower.contains('firm')) {
      refined =
          '$highlight - suggests active dermal collagen '
          'remodeling, an expected ${p.canonicalName} outcome.';
    } else if (lower.contains('dark spot') || lower.contains('pigment')) {
      refined =
          '$highlight - pigment normalization is a meaningful '
          'clinical outcome for this protocol.';
    } else if (lower.contains('weight') ||
        lower.contains('waist') ||
        lower.contains('body fat')) {
      refined =
          '$highlight - consistent with the anticipated '
          'metabolic effect of ${p.canonicalName}.';
    } else if (lower.contains('appetite') || lower.contains('satiety')) {
      refined =
          '$highlight - aligns with the appetite-modulating '
          'mechanism of ${p.canonicalName}.';
    }
    return refined;
  }

  /// Generates a clinical-grade, evidence-based narrative for each metric change.
  static String _narrativeForMetric(
    String name,
    double baseline,
    double latest,
    double pct,
    bool lowerBetter,
    String explanation,
  ) {
    final improvement = pct >= 0;
    final pctText = '${pct.abs().toStringAsFixed(1)}%';
    String whatNumberMeans = '';
    String clinicalSignificance = '';
    String recommendation = '';
    // Procedure-aware context for Hyperpigmentation (Dark Spots)
    if (name.contains('Hyperpigmentation') || name.contains('Dark Spots')) {
      whatNumberMeans =
          'This value reflects the degree of visible hyperpigmentation or uneven melanin distribution.';
      clinicalSignificance = improvement
          ? 'A reduction of $pctText indicates that melanin production and distribution are stabilizing, which is a positive sign for pigment-targeting procedures.'
          : 'An increase of $pctText suggests ongoing or worsening hyperpigmentation, which may require more intensive intervention.';
      recommendation = improvement
          ? 'Continue strict photoprotection (SPF 50+ daily) and use of brightening agents such as vitamin C, niacinamide, or azelaic acid. For persistent or worsening pigmentation, consult your provider about prescription options.'
          : 'Review your sun protection habits and consider adding or intensifying topical depigmenting agents. If pigmentation deepens, discuss prescription-strength treatments or procedural options with your provider.';
    } else if (name.contains('Erythema') ||
        name.contains('Redness') ||
        name.contains('Swelling')) {
      whatNumberMeans =
          'This value measures the degree of erythema (redness) and swelling, reflecting the skin\'s inflammatory response.';
      clinicalSignificance = improvement
          ? 'A $pctText reduction indicates that inflammation is resolving, which is expected as healing progresses.'
          : 'A $pctText increase suggests ongoing or worsening inflammation, which may delay recovery or increase risk of complications.';
      recommendation = improvement
          ? 'Continue gentle skincare, avoid irritants, and maintain photoprotection. If swelling or redness persists, consult your provider.'
          : 'Pause active ingredients, increase barrier support, and monitor for signs of infection or delayed healing. Seek provider input if symptoms worsen.';
    } else if (name.contains('Skin Texture') || name == 'Texture') {
      whatNumberMeans =
          'This value reflects the smoothness and organization of the skin surface.';
      clinicalSignificance = improvement
          ? 'A $pctText improvement means the epidermal barrier is normalizing, which supports better healing and product absorption.'
          : 'A $pctText worsening may indicate barrier disruption, dehydration, or delayed remodeling.';
      recommendation = improvement
          ? 'Continue gentle exfoliation and hydration. Maintain your current regimen.'
          : 'Increase hydration, consider gentle exfoliation, and avoid harsh products until texture improves.';
    } else if (name.contains('Rhytids') ||
        name.contains('Fine Lines') ||
        name.contains('Wrinkle')) {
      whatNumberMeans =
          'This value quantifies the depth and visibility of rhytids — fine lines and wrinkles.';
      clinicalSignificance = improvement
          ? 'A $pctText reduction suggests increased collagen synthesis and improved dermal structure, often seen after resurfacing or rejuvenation procedures.'
          : 'A $pctText increase may reflect ongoing photoaging, dehydration, or insufficient collagen support.';
      recommendation = improvement
          ? 'Maintain retinoid and peptide use as tolerated, and continue photoprotection.'
          : 'Discuss retinoid or procedural options with your provider for deeper lines.';
    } else if (name.contains('Pore Visibility') || name == 'Pores') {
      whatNumberMeans =
          'This value measures the prominence of pores, which is influenced by sebum production and dermal support.';
      clinicalSignificance = improvement
          ? 'A $pctText reduction indicates improved dermal remodeling and sebum regulation.'
          : 'A $pctText increase may signal excess oil production or loss of collagen support.';
      recommendation = improvement
          ? 'Continue niacinamide and gentle cleansing. Maintain your current regimen.'
          : 'Consider adding niacinamide or BHA exfoliant. Consult your provider if pore visibility worsens.';
    } else if (name.contains('Skin Laxity') ||
        name.contains('Elasticity') ||
        name.contains('Firmness')) {
      whatNumberMeans =
          'This value reflects skin laxity — the dermis\'s ability to stretch and recoil, indicating collagen and elastin integrity.';
      clinicalSignificance = improvement
          ? 'A $pctText improvement means the dermal matrix is strengthening, which is a positive sign for recovery and long-term skin quality.'
          : 'A $pctText decline may indicate delayed remodeling, aging, or insufficient support.';
      recommendation = improvement
          ? 'Continue collagen-supportive care (retinoids, vitamin C, peptides) and photoprotection.'
          : 'Discuss energy-based tightening or prescription retinoids with your provider.';
    } else {
      whatNumberMeans = 'This value reflects a tracked skin health metric.';
      clinicalSignificance = improvement
          ? 'A $pctText improvement is a positive sign of recovery.'
          : 'A $pctText worsening may require further attention.';
      recommendation = improvement
          ? 'Continue your current regimen.'
          : 'Consult your provider for tailored recommendations.';
    }
    return '$name changed from ${baseline.toStringAsFixed(1)} to ${latest.toStringAsFixed(1)}.\nWhat this means: $whatNumberMeans\nClinical significance: $clinicalSignificance\nEvidence-based recommendation: $recommendation\n\nThis AI-generated assessment is for informational purposes only and does not replace professional medical advice. Always consult your provider for personalized recommendations.';
  }

  /// Refines AI insight highlights to sound clinical, evidence-based, and includes disclaimer.
  // (Older variants of _clinicalInsightSummary / _clinicalInsightHighlight
  // were consolidated into the peptide-aware versions above.)

  static pw.Widget _scanTimeline(
    List<ScanHistoryEntry> scans,
    PdfColor textBrown,
    PdfColor champagne,
    PdfColor lightGrey,
    PdfColor roseGold, {
    String? procedureType,
  }) {
    final df = DateFormat('MMM d, yyyy');
    final isBbl =
        ProcedureIntelligence.categoryFor(procedureType) ==
            ProcedureCategory.bodyContouring &&
        !isCustomProcedureType(procedureType) &&
        ProcedureIntelligence.bodyContouringSubtype(procedureType) ==
            ProcedureBodyContouringSubtype.bbl;
    return pw.Column(
      children: scans.asMap().entries.map((e) {
        final scan = e.value;
        final metrics = scan.toSkinMetrics();
        final isLatest = e.key == 0;
        final timelineDefs = isBbl
            ? clinicalMetricsForProcedure('BBL').take(3).toList()
            : <ClinicalMetricDef>[];
        return pw.Container(
          color: isLatest ? champagne : lightGrey,
          margin: const pw.EdgeInsets.only(bottom: 4),
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: pw.Row(
            children: [
              pw.SizedBox(
                width: 88,
                child: pw.Text(
                  df.format(scan.timestamp),
                  style: pw.TextStyle(fontSize: 9.5, color: textBrown),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Wrap(
                  spacing: 12,
                  children: isBbl
                      ? timelineDefs.map((def) {
                          final value = def.valueFromRaw(scan.metrics, metrics);
                          return pw.Text(
                            '${def.label}: ${(value ?? 0).toStringAsFixed(1)}',
                            style: pw.TextStyle(fontSize: 9, color: textBrown),
                          );
                        }).toList()
                      : [
                          pw.Text(
                            'Erythema: ${metrics.redness.toStringAsFixed(1)}',
                            style: pw.TextStyle(fontSize: 9, color: textBrown),
                          ),
                          pw.Text(
                            'Skin Texture Quality: ${metrics.texture.toStringAsFixed(1)}',
                            style: pw.TextStyle(fontSize: 9, color: textBrown),
                          ),
                          pw.Text(
                            'Skin Laxity: ${metrics.elasticity.toStringAsFixed(1)}',
                            style: pw.TextStyle(fontSize: 9, color: textBrown),
                          ),
                        ],
                ),
              ),
              if (isLatest)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: pw.BoxDecoration(color: roseGold),
                  child: pw.Text(
                    'Latest',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Image conversion ────────────────────────────────────────────────────────

  /// Converts raw image bytes (any format including WebP, GIF, JPEG, PNG) into
  /// a [pw.MemoryImage] that the `pdf` package can embed without producing a
  /// broken red-X placeholder.
  ///
  /// Uses dart:ui decoding and re-encodes to PNG so final bytes are guaranteed
  /// PDF-safe.
  /// Returns null on any failure so the caller can show a placeholder instead.
  static Future<pw.MemoryImage?> _forcePngImage(
    Uint8List? bytes, {
    required String label,
  }) async {
    print('============================================================');
    print('[$label] FORCE PNG PIPELINE: START');
    print('============================================================');

    if (bytes == null || bytes.isEmpty) {
      print('[$label] NULL or empty bytes. Placeholder will be used.');
      print('[$label] FORCE PNG PIPELINE: END (FAILED EARLY)');
      return null;
    }

    print('[$label] INPUT BYTE LENGTH: ${bytes.length}');
    print('[$label] STEP 1/4: instantiateImageCodec()');

    try {
      final codec = await ui.instantiateImageCodec(bytes);
      print('[$label] STEP 1/4: SUCCESS');
      print('[$label] STEP 2/4: getNextFrame()');

      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;
      print('[$label] STEP 2/4: SUCCESS (${width}x$height)');
      print('[$label] STEP 3/4: toByteData(PNG)');

      final byteData = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      frame.image.dispose();
      print('[$label] STEP 3/4: COMPLETE');
      print('[$label] STEP 4/4: validate PNG bytes');

      if (byteData == null || byteData.lengthInBytes == 0) {
        print(
          '[$label] Conversion returned empty PNG bytes. Placeholder will be used.',
        );
        print('[$label] FORCE PNG PIPELINE: END (FAILED EMPTY PNG)');
        return null;
      }

      final pngBytes = byteData.buffer.asUint8List();
      print('[$label] STEP 4/4: SUCCESS - PNG ${pngBytes.length} bytes');
      print('[$label] FORCE PNG PIPELINE: END (SUCCESS)');
      return pw.MemoryImage(pngBytes);
    } catch (e, st) {
      print('[$label] FORCE PNG PIPELINE: FAILED - $e');
      print('[$label] Placeholder will be used; no image will be embedded.');
      debugPrint(st.toString());
      return null;
    }
  }

  // ── Math helpers ────────────────────────────────────────────────────────────

  /// Returns percentage improvement (positive = improvement).
  /// Lower-is-better: decrease = positive; higher-is-better: increase = positive.
  static double metricPctChange(
    double baseline,
    double latest, {
    required bool lowerIsBetter,
  }) {
    if (baseline.abs() < 0.01) return 0;
    final raw = ((baseline - latest) / baseline) * 100;
    return lowerIsBetter ? raw : -raw;
  }

  /// Recovery confidence score 0-100, based on scan density,
  /// average metric improvement, and insight count.
  static double recoveryConfidenceScore({
    required List<ScanHistoryEntry> scans,
    required List<ProgressPhotoInsight> insights,
    String? procedureType,
  }) {
    if (scans.isEmpty) return 15.0;

    final isBbl =
        ProcedureIntelligence.categoryFor(procedureType) ==
            ProcedureCategory.bodyContouring &&
        !isCustomProcedureType(procedureType) &&
        ProcedureIntelligence.bodyContouringSubtype(procedureType) ==
            ProcedureBodyContouringSubtype.bbl;

    // Scan count component: 1 scan = 8 pts, cap at 5 scans = 40 pts
    var score = isBbl
        ? (scans.length.clamp(1, 5) * 6).toDouble()
        : (scans.length.clamp(1, 5) * 8).toDouble();

    // Metric improvement component (max 40 pts; 60 pts for BBL-specific signals)
    if (scans.length >= 2) {
      final baseline = scans.last.toSkinMetrics();
      final latest = scans.first.toSkinMetrics();
      if (isBbl) {
        final weightedLabels = <String, double>{
          'Fat Retention': 0.28,
          'Skin Retraction & Tightness': 0.24,
          'Fibrosis/Firmness': 0.22,
          'Volume Satisfaction': 0.26,
        };
        var totalWeight = 0.0;
        var weighted = 0.0;
        for (final def in clinicalMetricsForProcedure(procedureType)) {
          final weight = weightedLabels[def.label];
          if (weight == null) continue;
          final b = def.valueFromRaw(scans.last.metrics, baseline);
          final l = def.valueFromRaw(scans.first.metrics, latest);
          if (b == null || l == null) continue;
          weighted +=
              metricPctChange(b, l, lowerIsBetter: def.lowerIsBetter) * weight;
          totalWeight += weight;
        }
        if (totalWeight > 0) {
          final avg = weighted / totalWeight;
          score += (avg / 20 * 60).clamp(0, 60).toDouble();
        }
      } else {
        final improvements = [
          metricPctChange(
            baseline.redness,
            latest.redness,
            lowerIsBetter: true,
          ),
          metricPctChange(
            baseline.texture,
            latest.texture,
            lowerIsBetter: true,
          ),
          metricPctChange(
            baseline.wrinkle,
            latest.wrinkle,
            lowerIsBetter: true,
          ),
          metricPctChange(
            baseline.elasticity,
            latest.elasticity,
            lowerIsBetter: false,
          ),
        ];
        final avg = improvements.reduce((a, b) => a + b) / improvements.length;
        // 20% avg improvement = full 40 pts
        score += (avg / 20 * 40).clamp(0, 40).toDouble();
      }
    }

    // Insights component: each insight = 10 pts, max 20 pts (15 for BBL)
    if (isBbl) {
      score = score.clamp(0.0, 100.0).toDouble();
      if (scans.length >= 2) {
        score = score < 38 ? 38 : score;
      } else {
        score = score < 35 ? 35 : score;
      }
    }

    score += isBbl
        ? (insights.length.clamp(0, 3) * 5).toDouble()
        : (insights.length.clamp(0, 2) * 10).toDouble();

    return score.clamp(0.0, 100.0);
  }

  static String _buildSummaryText({
    required ReportInput input,
    required double confidence,
  }) {
    final proc = input.procedure;
    final scans = input.scans;
    final df = DateFormat('MMM d, yyyy');
    final since = df.format(proc.startDate);

    final scanNote = scans.isEmpty
        ? 'No scans recorded.'
        : '${scans.length} scan${scans.length == 1 ? '' : 's'} recorded since $since.';

    final confidenceNote = confidence >= 75
        ? 'Strong recovery progress detected.'
        : confidence >= 50
        ? 'Steady recovery progress observed.'
        : 'Early recovery stage - keep tracking consistently.';

    return '$scanNote $confidenceNote';
  }

  static String _truncate(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}...';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Platform download shim - delegates to report_share_helper conditional import.
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _platformTriggerDownload(
  Uint8List bytes, {
  required String fileName,
}) async {
  await rsh.shareProfessionalReportPdf(bytes, fileName: fileName);
}
