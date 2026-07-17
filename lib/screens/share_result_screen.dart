import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_theme.dart';
import '../models/premium_recovery_models.dart';
import '../utils/premium_recovery_service.dart';
import '../widgets/report_share_helper.dart' as report_share;
import '../widgets/clinical_section_header.dart';
import '../widgets/report_disclaimer_notice.dart';

class ShareResultScreen extends StatefulWidget {
  const ShareResultScreen({super.key});

  @override
  State<ShareResultScreen> createState() => _ShareResultScreenState();
}

class _ShareResultScreenState extends State<ShareResultScreen> {
  bool _loading = false;
  List<ProfessionalReportRecord> _reports = const [];

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _loading = true);
    try {
      final raw = await PremiumRecoveryService.loadProfessionalReportRecords();
      final reports =
          raw
              .whereType<Map>()
              .map(
                (item) => ProfessionalReportRecord.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (!mounted) return;
      setState(() {
        _reports = reports;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _reports = const [];
        _loading = false;
      });
    }
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  String _metricPreview(ProfessionalReportRecord report) {
    if (report.keyMetrics.isEmpty) {
      return 'No key metrics saved';
    }
    final pairs = <String>[];
    report.keyMetrics.forEach((key, value) {
      if (pairs.length >= 3) return;
      pairs.add('${key.replaceAll('_', ' ')}: $value');
    });
    return pairs.join('  •  ');
  }

  Uint8List? _decodePdfBytes(String? encoded) {
    if (encoded == null || encoded.trim().isEmpty) return null;
    try {
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _shareSavedReport(ProfessionalReportRecord report) async {
    final decodedBytes = _decodePdfBytes(report.pdfBase64);
    final pdfFileName =
        report.pdfFileName ?? 'professional_report_${report.id}.pdf';

    final acceptedDisclaimer = await confirmReportShareDisclaimer(context);
    if (!mounted || !acceptedDisclaimer) return;

    if (decodedBytes != null && decodedBytes.isNotEmpty) {
      await report_share.shareProfessionalReportPdf(
        decodedBytes,
        fileName: pdfFileName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            kIsWeb ? 'PDF downloaded.' : 'Report is ready to share again.',
          ),
        ),
      );
      return;
    }

    if (report.fileRef == null || report.fileRef!.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'PDF bytes are missing for this report record. Generate the report again to restore download support.',
          ),
        ),
      );
      return;
    }

    await Share.shareXFiles(
      [XFile(report.fileRef!)],
      subject: report.title,
      text: report.summary,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyApp.champagne,
      appBar: AppBar(
        title: const ClinicalAppBarTitle(
          title: 'Professional Reports',
          eyebrow: 'Share & export',
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: MyApp.clinicalNavy,
        elevation: 0,
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 760),
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(24),
          decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.08).copyWith(
            boxShadow: [
              BoxShadow(
                color: MyApp.roseGold.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: _loading
              ? const CircularProgressIndicator()
              : _reports.isEmpty
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No professional reports saved yet.',
                      style: MyApp.cardTitleStyle().copyWith(fontSize: 20),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Generate a provider-ready PDF from a procedure detail screen and it will appear here in the Premium Recovery Hub.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: MyApp.textBrown.withValues(alpha: 0.72),
                        height: 1.45,
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Professional Report Generator',
                      style: MyApp.cardTitleStyle().copyWith(fontSize: 20),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Your generated provider-ready reports are saved here so you can review and reshare them later.',
                      style: TextStyle(
                        color: MyApp.textBrown.withValues(alpha: 0.72),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const ReportDisclaimerNotice(compact: true),
                    const SizedBox(height: 18),
                    ..._reports.map(
                      (report) => Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: MyApp.roseGold.withValues(alpha: 0.16),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    report.title,
                                    style: MyApp.cardTitleStyle().copyWith(
                                      fontSize: 17,
                                    ),
                                  ),
                                ),
                                Text(
                                  _formatDate(report.reportDate),
                                  style: TextStyle(
                                    color: MyApp.textBrown.withValues(
                                      alpha: 0.62,
                                    ),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              report.procedureName.trim().isEmpty
                                  ? 'Procedure: Not specified'
                                  : 'Procedure: ${report.procedureName}',
                              style: TextStyle(
                                color: MyApp.textBrown.withValues(alpha: 0.74),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              report.summary,
                              style: TextStyle(
                                fontSize: 15,
                                color: MyApp.textBrown,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _metricPreview(report),
                              style: TextStyle(
                                color: MyApp.textBrown.withValues(alpha: 0.66),
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              onPressed: () => _shareSavedReport(report),
                              icon: const Icon(
                                kIsWeb ? Icons.download_rounded : Icons.share,
                              ),
                              label: const Text(
                                kIsWeb ? 'Download PDF' : 'Share Again',
                              ),
                              style: MyApp.primaryGoldButton,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
