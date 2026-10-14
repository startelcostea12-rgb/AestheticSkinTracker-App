// Limited results for a free local (no-upload) AI scan: only what the
// on-device steps already produced -- the face check, the lighting lock
// check, and an ISO / Bv summary of the captured frames. No metric values
// or trend verdicts are shown, and nothing is uploaded or saved to history.

import 'package:flutter/material.dart';

import '../../../../app_theme.dart';
import '../../../../models/ai_scan_frame_exposure.dart';
import '../../../../utils/upload_gate.dart';
import '../../../../widgets/paywall_screen.dart';

class FreeLocalScanSummary {
  const FreeLocalScanSummary({
    required this.faceFound,
    this.faceCoverage,
    this.symmetryScore,
    this.captureQuality,
    required this.hasBaseline,
    required this.lightingWouldLock,
    required this.missingExposure,
    this.currentBrightnessValue,
    this.baselineBrightnessValue,
    required this.frameCount,
    this.isoMin,
    this.isoMax,
    this.bvMin,
    this.bvMax,
    required this.scansUsed,
    this.scanLimit = kFreeLocalScanLimit,
  });

  /// Builds the summary from the on-device results only.
  factory FreeLocalScanSummary.fromLocal({
    required bool faceFound,
    double? faceCoverage,
    double? symmetryScore,
    String? captureQuality,
    required bool hasBaseline,
    required ({
      bool wouldLock,
      bool missingExposure,
      double? currentBrightnessValue,
      double? baselineBrightnessValue,
    })
    lightingCheck,
    required List<AiScanFrameExposure> frames,
    required int scansUsed,
  }) {
    final isos = [for (final f in frames) ?f.iso];
    final bvs = [
      for (final f in frames)
        if (f.brightnessValue?.isFinite ?? false) f.brightnessValue!,
    ];
    return FreeLocalScanSummary(
      faceFound: faceFound,
      faceCoverage: faceCoverage,
      symmetryScore: symmetryScore,
      captureQuality: captureQuality,
      hasBaseline: hasBaseline,
      lightingWouldLock: lightingCheck.wouldLock,
      missingExposure: lightingCheck.missingExposure,
      currentBrightnessValue: lightingCheck.currentBrightnessValue,
      baselineBrightnessValue: lightingCheck.baselineBrightnessValue,
      frameCount: frames.length,
      isoMin: isos.isEmpty ? null : isos.reduce((a, b) => a < b ? a : b),
      isoMax: isos.isEmpty ? null : isos.reduce((a, b) => a > b ? a : b),
      bvMin: bvs.isEmpty ? null : bvs.reduce((a, b) => a < b ? a : b),
      bvMax: bvs.isEmpty ? null : bvs.reduce((a, b) => a > b ? a : b),
      scansUsed: scansUsed,
    );
  }

  final bool faceFound;
  final double? faceCoverage;
  final double? symmetryScore;
  final String? captureQuality;
  final bool hasBaseline;
  final bool lightingWouldLock;
  final bool missingExposure;
  final double? currentBrightnessValue;
  final double? baselineBrightnessValue;
  final int frameCount;
  final int? isoMin;
  final int? isoMax;
  final double? bvMin;
  final double? bvMax;
  final int scansUsed;
  final int scanLimit;

  int get scansLeft => scansUsed >= scanLimit ? 0 : scanLimit - scansUsed;
}

class FreeLocalScanResultsScreen extends StatelessWidget {
  const FreeLocalScanResultsScreen({super.key, required this.summary});

  final FreeLocalScanSummary summary;

  static const String premiumNote =
      'Full metrics, trends, history, and the PDF report require Premium. '
      'Nothing from this scan was uploaded or saved.';

  String _faceText() {
    if (!summary.faceFound) {
      return 'No face crop on this device; the photo you framed was used '
          'as is.';
    }
    final parts = <String>['Face found and cropped'];
    if (summary.faceCoverage != null) {
      parts.add(
        'full-frame coverage ${(summary.faceCoverage! * 100).round()}%',
      );
    }
    if (summary.symmetryScore != null) {
      parts.add('L/R symmetry ${(summary.symmetryScore! * 100).round()}%');
    }
    return parts.join(' · ');
  }

  String _lightingText() {
    if (!summary.hasBaseline) {
      return 'No baseline yet, so there is nothing to compare lighting '
          'against.';
    }
    if (summary.lightingWouldLock) {
      return 'Locked: brightness differs from your baseline '
          '(Bv ${_bv(summary.currentBrightnessValue)} vs '
          '${_bv(summary.baselineBrightnessValue)}). Retake under the lamp.';
    }
    if (summary.missingExposure) {
      return 'Locked: exposure data is missing on this scan or the '
          'baseline.';
    }
    return 'Not locked: lighting matches your baseline.';
  }

  String _exposureText() {
    if (summary.frameCount == 0) return 'No exposure data on this capture.';
    String range<T extends num>(T? lo, T? hi, String Function(T) f) {
      if (lo == null || hi == null) return 'not recorded';
      return lo == hi ? f(lo) : '${f(lo)}–${f(hi)}';
    }

    return '${summary.frameCount} '
        'frame${summary.frameCount == 1 ? '' : 's'} · ISO '
        '${range<int>(summary.isoMin, summary.isoMax, (v) => '$v')} · Bv '
        '${range<double>(summary.bvMin, summary.bvMax, _bv)}';
  }

  static String _bv(double? v) => v == null ? '—' : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      appBar: AppBar(title: const Text('Free scan check')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _row(
            'free_scan_face',
            Icons.face_retouching_natural_outlined,
            'Face check',
            _faceText(),
          ),
          _row(
            'free_scan_lighting',
            Icons.wb_incandescent_outlined,
            'Lighting lock',
            _lightingText(),
          ),
          _row(
            'free_scan_cheek',
            Icons.lock_outline,
            'Cheek lock',
            'Checked during full analysis (it uses per-cheek readings that '
                'are only measured there).',
          ),
          _row(
            'free_scan_exposure',
            Icons.camera_outlined,
            'ISO / Bv',
            _exposureText(),
          ),
          if (summary.captureQuality != null)
            _row(
              'free_scan_capture_quality',
              Icons.crop_free,
              'Capture',
              summary.captureQuality!,
            ),
          const SizedBox(height: 8),
          const Text(
            premiumNote,
            key: ValueKey('free_scan_premium_note'),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textStructure,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Free scans left: ${summary.scansLeft} of ${summary.scanLimit}',
            key: const ValueKey('free_scan_count'),
            style: const TextStyle(color: AppColors.textStructure),
          ),
          const SizedBox(height: 14),
          FilledButton(
            key: const ValueKey('free_scan_upgrade_button'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PaywallScreen()),
            ),
            child: const Text('See Premium'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _row(String key, IconData icon, String title, String body) {
    return Container(
      key: ValueKey(key),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borders),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.brandAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textStructure,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: AppColors.textStructure,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
