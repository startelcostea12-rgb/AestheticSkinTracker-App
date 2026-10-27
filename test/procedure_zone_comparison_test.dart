import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:aesthetic_skin_tracker/features/procedures/presentation/procedure_profiles_screen.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/widgets/before_after_split_slider.dart';
import 'package:aesthetic_skin_tracker/widgets/image_crop_dialog.dart';
import 'package:aesthetic_skin_tracker/widgets/skin_heatmap_overlay.dart';
import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';

ScanHistoryEntry _scan({
  required Map<String, dynamic> rawPayload,
  String quality = 'normal',
}) {
  return ScanHistoryEntry(
    id: quality,
    timestamp: DateTime(2026, 9, 17),
    estimatedSkinAge: 0,
    metrics: const <String, double>{},
    captureQuality: quality,
    rawPayload: rawPayload,
  );
}

Map<String, dynamic> _zonePayload({
  bool includeUnsupported = false,
  bool validCrop = true,
}) {
  final crop = validCrop
      ? <String, dynamic>{
          'left': 0.25,
          'top': 0.20,
          'size': 0.40,
          'coordinate_space': 'normalized_face',
        }
      : <String, dynamic>{'left': -1, 'top': 0, 'size': 0};
  return {
    'metric_extraction_paths': {'localized_redness': 'cheek_primary'},
    'zone_analysis': {
      'left_cheek': {
        'crop': crop,
        'metrics': {'localized_redness': 44.0, 'pigment_load': 31.0},
      },
      if (includeUnsupported)
        'whole_face': {
          'crop': crop,
          'metrics': {'skin_tone_radiance_evenness': 70.0},
        },
    },
  };
}

void main() {
  test('placeholder baseline never formats a fake -82.7 percent', () {
    const placeholder = LuxeMetric(
      key: 'texture_smoothness',
      name: 'Texture',
      baselineScore: 50,
      currentScore: 8.65,
      improvementPercent: -82.7,
      lowerIsBetter: false,
      hasBaselineValue: false,
      hasStoredBaselineValue: false,
    );
    expect(procedureMetricDeltaText(placeholder), isNull);
    expect(placeholder.improvementPercent, -82.7);
  });

  test(
    'comparison-shaped fallback without stored provenance has no percent',
    () {
      const placeholder = LuxeMetric(
        key: 'texture_smoothness',
        name: 'Texture',
        baselineScore: 50,
        currentScore: 8.65,
        improvementPercent: -82.7,
        lowerIsBetter: false,
        hasBaselineValue: true,
        hasStoredBaselineValue: false,
      );
      expect(procedureMetricDeltaText(placeholder), isNull);
    },
  );

  test('missing parsed baseline has no percent even with a backend delta', () {
    final metric = LuxeMetricParser.parseTimelinePayload({
      'metric_matrix': {'texture_smoothness': 8.65},
      'trend_deltas': {'texture_smoothness': -82.7},
      'trend_status': {'texture_smoothness': 'worsened'},
    }).single;
    expect(procedureMetricDeltaText(metric), isNull);
  });

  test('real stored baseline retains the existing formatted comparison', () {
    for (final (current, delta) in [(55.0, 10.0), (8.65, -82.7)]) {
      final metric = LuxeMetricParser.parseTimelinePayload({
        'metric_matrix': {'texture_smoothness': current},
        'baseline_metric_matrix': {'texture_smoothness': 50},
        'trend_deltas': {'texture_smoothness': delta},
        'trend_status': {
          'texture_smoothness': delta > 0 ? 'improved' : 'worsened',
        },
      }).single;
      expect(
        procedureMetricDeltaText(metric),
        LuxeMetricParser.formatDisplayDeltaWithoutMinus(
          baseline: metric.baselineScore,
          current: metric.currentScore,
          deltaPct: metric.improvementPercent,
        ),
      );
      expect(procedureMetricDeltaText(metric), contains('%'));
    }
  });

  test(
    'face-anchored chin zone follows a face high in the square viewport',
    () {
      const sourceSize = Size(100, 100);
      const sourceFaceRect = Rect.fromLTRB(20, 3, 80, 50);
      final faceRect = faceRectInCoverViewport(
        sourceFaceRect: sourceFaceRect,
        sourceSize: sourceSize,
        viewportSize: sourceSize,
      );
      final spots = faceAnchoredLaserSpots(
        faceRect: faceRect,
        redness: 1,
        wrinkles: 1,
        improvement: 1,
      );
      final chin = spots.singleWhere(
        (spot) => spot.tone == SkinHeatmapTone.improvement,
      );
      final chinY = (chin.alignment.y + 1) / 2;

      expect((0.25 + 1) / 2, greaterThan(faceRect!.bottom));
      expect(chinY, lessThan(faceRect.bottom));
    },
  );

  test('no detected face means no laser stencil spots', () {
    expect(
      faceAnchoredLaserSpots(
        faceRect: null,
        redness: 1,
        wrinkles: 1,
        improvement: 1,
      ),
      isEmpty,
    );
  });

  test(
    'supported zones and supported metrics render from persisted payload',
    () {
      final zones = procedureZoneComparisons(
        baselinePayload: _zonePayload(),
        latestPayload: _zonePayload(),
      );

      expect(zones, hasLength(1));
      expect(zones.single.key, 'left_cheek');
      expect(
        zones.single.baselineMetrics.keys,
        containsAll(<String>['localized_redness', 'pigment_load']),
      );
      expect(zones.single.crop.left, 0.25);
      expect(zones.single.crop.size, 0.40);
    },
  );

  test(
    'zone parser reads zone metrics and crop rather than top-level decoys',
    () {
      final baseline = _zonePayload()
        ..['metrics'] = {'localized_redness': 1.0, 'pigment_load': 2.0}
        ..['crop'] = {'left': 0.99, 'top': 0.99, 'size': 0.01};
      final latest = _zonePayload()
        ..['metrics'] = {'localized_redness': 98.0, 'pigment_load': 99.0}
        ..['crop'] = {'left': 0.99, 'top': 0.99, 'size': 0.01};

      final zone = procedureZoneComparisons(
        baselinePayload: baseline,
        latestPayload: latest,
      ).single;

      expect(zone.baselineMetrics['localized_redness'], 44.0);
      expect(zone.latestMetrics['pigment_load'], 31.0);
      expect(zone.crop.left, 0.25);
      expect(zone.crop.top, 0.20);
      expect(zone.crop.size, 0.40);
    },
  );

  test('unsupported whole-face measures are omitted', () {
    final zones = procedureZoneComparisons(
      baselinePayload: _zonePayload(includeUnsupported: true),
      latestPayload: _zonePayload(includeUnsupported: true),
    );

    expect(zones.map((zone) => zone.key), isNot(contains('whole_face')));
    expect(
      zones.single.latestMetrics.keys,
      isNot(contains('skin_tone_radiance_evenness')),
    );
  });

  test(
    'invalid fallback ROI metadata is omitted rather than displayed as a zone',
    () {
      final zones = procedureZoneComparisons(
        baselinePayload: _zonePayload(validCrop: false),
        latestPayload: _zonePayload(validCrop: false),
      );

      expect(zones, isEmpty);
    },
  );

  test('non-comparable whole scan suppresses every zone result', () {
    final baseline = _scan(rawPayload: _zonePayload());
    final latest = _scan(rawPayload: _zonePayload(), quality: 'low_light');
    final eligibility = procedurePhotoComparisonEligibility(
      isBodyProcedure: false,
      baseline: baseline,
      latest: latest,
    );

    expect(eligibility.isComparable, isFalse);
    expect(
      gatedProcedureZoneComparisons(
        eligibility: eligibility,
        baselinePayload: baseline.rawPayload,
        latestPayload: latest.rawPayload,
      ),
      isEmpty,
    );
  });

  testWidgets('persisted zone crop renders the existing before-after slider', (
    tester,
  ) async {
    final source = img.Image(width: 100, height: 100);
    img.fill(source, color: img.ColorRgb8(220, 120, 120));
    final bytes = Uint8List.fromList(img.encodeJpg(source));
    final cropped = applyNormalizedSquareCrop(
      bytes,
      const NormalizedSquareCrop(left: 0.25, top: 0.20, size: 0.40),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractiveBeforeAfterSlider(
            beforeImage: MemoryImage(cropped),
            afterImage: MemoryImage(cropped),
            beforeLabel: 'Zone before',
            afterLabel: 'Zone after',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Zone before'), findsOneWidget);
    expect(find.text('Zone after'), findsOneWidget);
    final decoded = img.decodeImage(cropped);
    expect(decoded, isNotNull);
    expect(decoded!.width, decoded.height);
  });
}
