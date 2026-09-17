import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:aesthetic_skin_tracker/features/procedures/presentation/procedure_profiles_screen.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/widgets/before_after_split_slider.dart';
import 'package:aesthetic_skin_tracker/widgets/image_crop_dialog.dart';

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
        'metrics': {
          'localized_redness': 44.0,
          'pigment_load': 31.0,
        },
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
  test('supported zones and supported metrics render from persisted payload', () {
    final zones = procedureZoneComparisons(
      baselinePayload: _zonePayload(),
      latestPayload: _zonePayload(),
    );

    expect(zones, hasLength(1));
    expect(zones.single.key, 'left_cheek');
    expect(zones.single.baselineMetrics.keys,
        containsAll(<String>['localized_redness', 'pigment_load']));
    expect(zones.single.crop.left, 0.25);
    expect(zones.single.crop.size, 0.40);
  });

  test('unsupported whole-face measures are omitted', () {
    final zones = procedureZoneComparisons(
      baselinePayload: _zonePayload(includeUnsupported: true),
      latestPayload: _zonePayload(includeUnsupported: true),
    );

    expect(zones.map((zone) => zone.key), isNot(contains('whole_face')));
    expect(zones.single.latestMetrics.keys,
        isNot(contains('skin_tone_radiance_evenness')));
  });

  test('invalid fallback ROI metadata is omitted rather than displayed as a zone', () {
    final zones = procedureZoneComparisons(
      baselinePayload: _zonePayload(validCrop: false),
      latestPayload: _zonePayload(validCrop: false),
    );

    expect(zones, isEmpty);
  });

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
