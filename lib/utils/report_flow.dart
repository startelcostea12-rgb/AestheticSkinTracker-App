// lib/utils/report_flow.dart
//
// Shared "gated Professional Report" generation flow.
//
// Use this helper from anywhere in the app that exposes a
// "Share / Generate Professional Report" button (Home quick actions,
// Peptide Tracker provider-share card, etc.).
//
// Behavior:
//   1. Resolve the procedure (passed in or the active one from AppPrefs).
//   2. Check entitlement via ReportPurchase.canGenerateReport.
//        - Premium subscriber  → proceed immediately.
//        - Already unlocked    → proceed immediately.
//        - Otherwise           → present the clinical paywall sheet.
//   3. Gather scans / insights / milestones / before-after photos.
//   4. Generate the PDF via ReportService.generateAndSave (which also
//      persists a ProfessionalReportRecord so free users can re-download
//      from the saved-reports screen later).
//   5. Deliver the PDF through report_share.shareProfessionalReportPdf.
//
// Returns `true` when a report was generated; `false` when the user
// cancelled, was not entitled, or no active procedure exists.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/premium_recovery_models.dart';
import '../models/procedure.dart';
import 'app_prefs.dart';
import 'premium_recovery_service.dart';
import 'report_purchase.dart';
import 'report_service.dart';
import '../widgets/report_paywall_sheet.dart';
import '../widgets/report_disclaimer_notice.dart';
import '../widgets/report_share_helper.dart' as report_share;

/// Run the full gated Professional Report flow.
///
/// Pass [procedure] when a specific procedure is in context (e.g. from the
/// procedure detail screen). When null, the active procedure stored in
/// AppPrefs is used.
Future<bool> runGatedReportFlow(
  BuildContext context, {
  Procedure? procedure,
}) async {
  // ── 1. Resolve procedure ──────────────────────────────────────────────────
  Procedure? proc = procedure;
  if (proc == null) {
    final id = await AppPrefs.resolveActiveProcedureId();
    if (id != null && id.isNotEmpty) {
      final entries = await AppPrefs.getProcedureEntries();
      for (final e in entries) {
        if ((e['id'] ?? '').toString() == id) {
          proc = Procedure.fromJson(Map<String, dynamic>.from(e));
          break;
        }
      }
    }
  }

  if (proc == null) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No active procedure found. Create a procedure profile first.',
        ),
      ),
    );
    return false;
  }

  // ── 2. Hybrid monetization gate ───────────────────────────────────────────
  final canGenerate = await ReportPurchase.canGenerateReport(proc.id);
  if (!canGenerate) {
    if (!context.mounted) return false;
    final unlocked = await showReportPaywallSheet(
      context,
      procedureId: proc.id,
      procedureName: proc.type,
    );
    if (!context.mounted || !unlocked) return false;
  }

  final acceptedDisclaimer = await confirmReportShareDisclaimer(context);
  if (!context.mounted || !acceptedDisclaimer) return false;

  // ── 3. Show a non-blocking "Preparing report…" indicator ──────────────────
  if (!context.mounted) return false;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          SizedBox(width: 12),
          Text('Preparing your progress report...'),
        ],
      ),
      duration: Duration(seconds: 30),
    ),
  );

  try {
    // ── 4. Gather supporting data ───────────────────────────────────────────
    final allScans = await AppPrefs.getScanEntries();
    final scans =
        allScans.where((s) => (s.procedureId ?? '') == proc!.id).toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final insightsRaw = await PremiumRecoveryService.loadProgressInsights();
    final insights =
        insightsRaw
            .whereType<ProgressPhotoInsight>()
            .where(
              (i) =>
                  (i.procedureType ?? '').toLowerCase() ==
                  proc!.type.toLowerCase(),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final plansRaw = await PremiumRecoveryService.loadCustomPlans();
    final milestones = plansRaw
        .whereType<CustomRecoveryPlan>()
        .where((p) => p.procedureType.toLowerCase() == proc!.type.toLowerCase())
        .expand((p) => p.timelineMilestones)
        .take(8)
        .toList();

    final comparison = await AppPrefs.getProcedurePhotoComparison(proc.id);
    final Uint8List? beforeBytes = _decodeImagePath(
      comparison['baselineImagePath'],
    );
    final Uint8List? afterBytes = _decodeImagePath(
      comparison['latestImagePath'],
    );

    final patientName = await AppPrefs.getUserName();

    final input = ReportInput(
      procedure: proc,
      scans: scans,
      beforePhotoBytes: beforeBytes,
      afterPhotoBytes: afterBytes,
      insights: insights,
      surgeonNotes: proc.notes.trim().isEmpty ? null : proc.notes.trim(),
      patientName: patientName,
      customPlanMilestones: milestones,
    );

    // ── 5. Generate + deliver ───────────────────────────────────────────────
    final result = await ReportService.generateAndSave(input);

    await report_share.shareProfessionalReportPdf(
      result.pdfBytes,
      fileName: result.record.pdfFileName ?? 'recovery_report.pdf',
    );

    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                kIsWeb
                    ? 'Report generated and downloaded.'
                    : 'Report generated and ready to share.',
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green[700],
        duration: const Duration(seconds: 4),
      ),
    );
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not generate report: $e'),
        backgroundColor: Colors.red[700],
      ),
    );
    return false;
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

Uint8List? _decodeImagePath(String? path) {
  if (path == null || path.trim().isEmpty) return null;
  if (path.startsWith('data:image')) {
    try {
      final base64Part = path.split(',').last;
      return base64Decode(base64Part);
    } catch (_) {
      return null;
    }
  }
  // For non-data URLs we let the PDF renderer handle network fetching.
  return null;
}
