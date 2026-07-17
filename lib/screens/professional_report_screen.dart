// lib/screens/professional_report_screen.dart
//
// ProfessionalReportScreen — lists all saved recovery reports and provides
// a "Generate New Report" button for the currently active procedure.
//
// This is the screen that the Premium Hub's /report route opens.
// It can also be pushed directly from ProcedureDetailScreen or any other
// screen that calls  Navigator.pushNamed(context, '/report').

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
// ignore: unused_import
import '../widgets/clinical_section_header.dart';
import '../models/premium_recovery_models.dart';
import '../models/procedure.dart';
import '../utils/app_prefs.dart';
import '../utils/premium_recovery_service.dart';
import '../utils/report_service.dart';
import '../utils/report_purchase.dart';
import '../widgets/report_disclaimer_notice.dart';
import '../widgets/report_share_helper.dart' as report_share;
import '../widgets/report_paywall_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class ProfessionalReportScreen extends StatefulWidget {
  /// Pass an optional [procedure] to pre-seed the "Generate New Report" action.
  /// When null the screen resolves the active procedure from AppPrefs.
  const ProfessionalReportScreen({super.key, this.procedure});

  final Procedure? procedure;

  @override
  State<ProfessionalReportScreen> createState() =>
      _ProfessionalReportScreenState();
}

class _ProfessionalReportScreenState extends State<ProfessionalReportScreen> {
  List<ProfessionalReportRecord> _records = const [];
  bool _loading = true;
  bool _generating = false;
  String? _activeProcedureName;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ── Data loading ───────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final records = await ReportService.loadAll();
      final procName = widget.procedure?.type ?? await _resolveActiveProcName();
      if (!mounted) return;
      setState(() {
        _records = records;
        _activeProcedureName = procName;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _resolveActiveProcName() async {
    final id = await AppPrefs.resolveActiveProcedureId();
    if (id == null || id.trim().isEmpty) return null;
    final entries = await AppPrefs.getProcedureEntries();
    for (final e in entries) {
      if ((e['id'] ?? '').toString() == id) {
        return (e['type'] ?? '').toString().trim();
      }
    }
    return null;
  }

  // ── Generate ───────────────────────────────────────────────────────────────

  Future<void> _generateReport() async {
    if (_generating) return;

    final acceptedDisclaimer = await confirmReportShareDisclaimer(context);
    if (!mounted || !acceptedDisclaimer) return;

    // Resolve procedure
    Procedure? proc = widget.procedure;
    if (proc == null) {
      final id = await AppPrefs.resolveActiveProcedureId();
      if (id != null && id.isNotEmpty) {
        final entries = await AppPrefs.getProcedureEntries();
        final match = entries
            .where((e) => (e['id'] ?? '').toString() == id)
            .firstOrNull;
        if (match != null) {
          proc = Procedure.fromJson(Map<String, dynamic>.from(match));
        }
      }
    }

    if (proc == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No active procedure found. Create a procedure profile first.',
          ),
        ),
      );
      return;
    }

    // ── Hybrid monetization gate ───────────────────────────────────────────────
    // Premium subscribers → unlimited reports.
    // Free users          → must unlock this procedure's report (one-time)
    //                       or upgrade to Premium.
    final canGenerate = await ReportPurchase.canGenerateReport(proc.id);
    if (!canGenerate) {
      if (!mounted) return;
      final unlocked = await showReportPaywallSheet(
        context,
        procedureId: proc.id,
        procedureName: proc.type,
      );
      if (!mounted || !unlocked) return;
    }

    setState(() => _generating = true);

    try {
      // Gather supporting data
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
          .where(
            (p) => p.procedureType.toLowerCase() == proc!.type.toLowerCase(),
          )
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

      final result = await ReportService.generateAndSave(input);

      // Deliver the PDF immediately
      await report_share.shareProfessionalReportPdf(
        result.pdfBytes,
        fileName: result.record.pdfFileName ?? 'recovery_report.pdf',
      );

      await _loadData();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
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
          backgroundColor: AppColors.mutedSage,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not generate report: $e'),
          backgroundColor: AppColors.softTerracotta,
        ),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  // ── Re-download ────────────────────────────────────────────────────────────

  Future<void> _redownload(ProfessionalReportRecord record) async {
    final bytes = ReportService.getPdfBytesFromRecord(record);
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'PDF not available for this report. Please regenerate it.',
          ),
        ),
      );
      return;
    }
    final acceptedDisclaimer = await confirmReportShareDisclaimer(context);
    if (!mounted || !acceptedDisclaimer) return;
    await report_share.shareProfessionalReportPdf(
      bytes,
      fileName: record.pdfFileName ?? 'recovery_report.pdf',
    );
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  Future<void> _deleteRecord(ProfessionalReportRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Report?'),
        content: const Text(
          'This will permanently remove the report and its saved PDF.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ReportService.deleteById(record.id);
    await _loadData();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Uint8List? _decodeImagePath(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('data:image')) {
      try {
        final parts = path.split(',');
        if (parts.length > 1) return base64Decode(parts[1]);
      } catch (_) {}
    }
    return null;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyApp.champagne,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: ClinicalAppBarTitle(
          title: 'Professional Reports',
          eyebrow: 'Progress exports',
          color: MyApp.textBrown,
        ),
        centerTitle: true,
        foregroundColor: MyApp.textBrown,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildGenerateCard(),
                Expanded(
                  child: _records.isEmpty
                      ? _buildEmptyState()
                      : _buildRecordList(),
                ),
              ],
            ),
    );
  }

  // ── Generate card ──────────────────────────────────────────────────────────

  Widget _buildGenerateCard() {
    final procName = _activeProcedureName?.trim() ?? '';
    final hasProc = procName.isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: MyApp.roseGold.withValues(alpha: 0.08),
            blurRadius: 12,
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
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: MyApp.roseGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.picture_as_pdf_outlined,
                  color: MyApp.roseGold,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Generate New Report', style: MyApp.cardTitleStyle()),
                    const SizedBox(height: 2),
                    Text(
                      hasProc
                          ? 'Active: $procName'
                          : 'No active procedure selected',
                      style: TextStyle(
                        fontSize: 12,
                        color: hasProc
                            ? MyApp.textBrown.withValues(alpha: 0.65)
                            : Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Creates a surgeon-ready PDF with your before/after photos, '
            'key metric changes, AI recovery insights, and your recovery '
            'confidence score.',
            style: TextStyle(
              fontSize: 12.5,
              color: MyApp.textBrown.withValues(alpha: 0.72),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          const ReportDisclaimerNotice(compact: true),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _generating ? null : _generateReport,
              icon: _generating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome_outlined, size: 18),
              label: Text(_generating ? 'Generating…' : 'Generate & Download'),
              style: MyApp.primaryGoldButton,
            ),
          ),
        ],
      ),
    );
  }

  // ── Record list ────────────────────────────────────────────────────────────

  Widget _buildRecordList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _records.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _reportCard(_records[i]),
    );
  }

  Widget _reportCard(ProfessionalReportRecord record) {
    final df = DateFormat('MMM d, yyyy');
    final confidence =
        (record.keyMetrics['recovery_confidence'] as num?)?.toDouble() ?? 0.0;
    final scanCount = (record.keyMetrics['scan_count'] as num?)?.toInt() ?? 0;
    final hasPdf = (record.pdfBase64 ?? '').isNotEmpty;

    return Card(
      color: Colors.white,
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: MyApp.roseGold.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.picture_as_pdf_outlined,
                    color: MyApp.roseGold,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.title,
                        style: TextStyle(
                          color: MyApp.textBrown,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        df.format(record.reportDate),
                        style: TextStyle(
                          color: MyApp.textBrown.withValues(alpha: 0.58),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Delete button
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    color: MyApp.textBrown.withValues(alpha: 0.38),
                    size: 20,
                  ),
                  onPressed: () => _deleteRecord(record),
                  tooltip: 'Delete report',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Summary
            if (record.summary.isNotEmpty)
              Text(
                record.summary,
                style: TextStyle(
                  fontSize: 12.5,
                  color: MyApp.textBrown.withValues(alpha: 0.78),
                  height: 1.4,
                ),
              ),
            const SizedBox(height: 10),

            // Metrics chips
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _chip(
                  '${confidence.round()}% confidence',
                  confidence >= 75 ? AppColors.mutedSage : MyApp.roseGold,
                ),
                _chip(
                  '$scanCount scan${scanCount == 1 ? '' : 's'}',
                  MyApp.textBrown.withValues(alpha: 0.7),
                ),
                if (!hasPdf) _chip('No PDF stored', Colors.orange.shade700),
              ],
            ),
            const SizedBox(height: 12),

            // Download / re-download button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: hasPdf ? () => _redownload(record) : null,
                icon: const Icon(
                  kIsWeb ? Icons.download_outlined : Icons.share_outlined,
                  size: 17,
                ),
                label: Text(
                  hasPdf
                      ? (kIsWeb ? 'Download PDF' : 'Share PDF')
                      : 'PDF not stored — regenerate',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: hasPdf ? MyApp.roseGold : Colors.grey,
                  side: BorderSide(
                    color: hasPdf
                        ? MyApp.roseGold.withValues(alpha: 0.5)
                        : Colors.grey.shade300,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.picture_as_pdf_outlined,
              size: 52,
              color: MyApp.roseGold.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 18),
            Text(
              'No reports generated yet',
              style: TextStyle(
                color: MyApp.textBrown,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "Generate & Download" above to create your first '
              'professional recovery report.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MyApp.textBrown.withValues(alpha: 0.65),
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
