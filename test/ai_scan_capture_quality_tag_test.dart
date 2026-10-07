import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:aesthetic_skin_tracker/models/procedure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// The AI Skin Analysis capture_quality tag is measured on the face crop
/// that is uploaded (croppedFrames.first), not on the uncropped still, whose
/// dark background can read soft while the face is sharp.

const double _facialFloor = 36.0;

Uint8List _png(img.Image image) => Uint8List.fromList(img.encodePng(image));

/// A face-sized crop with plenty of edge detail.
img.Image _sharpCrop() {
  final image = img.Image(width: 96, height: 96);
  for (var y = 0; y < 96; y++) {
    for (var x = 0; x < 96; x++) {
      final v = ((x ~/ 4) + (y ~/ 4)).isEven ? 135 : 110;
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  return image;
}

/// The same sharp face pasted into a large, flat, dark scene.
img.Image _softFullStillAround(img.Image crop) {
  const size = 1400;
  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(8, 8, 8));
  img.compositeImage(
    image,
    crop,
    dstX: (size - crop.width) ~/ 2,
    dstY: (size - crop.height) ~/ 2,
  );
  return image;
}

/// A crop with only faint pixel noise: measurable but under the floor.
img.Image _softCrop() {
  final rng = math.Random(7);
  final image = img.Image(width: 96, height: 96);
  for (var y = 0; y < 96; y++) {
    for (var x = 0; x < 96; x++) {
      final v = 120 + rng.nextInt(3) - 1;
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  return image;
}

void main() {
  group('sharpness floor', () {
    test('facial floor is unchanged at 36', () {
      expect(sharpnessVarianceFloorFor(ProcedureCameraGuideType.facial), 36.0);
      expect(sharpnessVarianceFloorFor(ProcedureCameraGuideType.body), 24.0);
      expect(sharpnessVarianceFloorFor(ProcedureCameraGuideType.general), 28.0);
    });
  });

  group('aiScanCaptureQualityFromUploadedCrop', () {
    test('a sharp crop with a soft full still is tagged from the crop', () {
      final crop = _sharpCrop();
      final cropBytes = _png(crop);
      final stillBytes = _png(_softFullStillAround(crop));

      final result = aiScanCaptureQualityFromUploadedCrop(
        uploadedCrop: cropBytes,
        fullStill: stillBytes,
        sharpnessFloor: _facialFloor,
        poorAngle: false,
        lowLight: false,
        unevenLighting: false,
      );

      expect(result.cropSharpness, greaterThanOrEqualTo(_facialFloor));
      expect(result.fullStillSharpness, greaterThan(0));
      expect(result.fullStillSharpness, lessThan(_facialFloor));
      expect(result.tag, 'normal');
      // Tagging the uncropped still, as before, would have said blurry.
      expect(
        captureQualityFromFrameSignals(
          sharpness: imageSharpnessVarianceFromBytes(stillBytes),
          sharpnessFloor: _facialFloor,
          poorAngle: false,
          lowLight: false,
          unevenLighting: false,
        ),
        'blurry',
      );
    });

    test('a crop under the floor is still blurry', () {
      final cropBytes = _png(_softCrop());
      final result = aiScanCaptureQualityFromUploadedCrop(
        uploadedCrop: cropBytes,
        fullStill: _png(_sharpCrop()),
        sharpnessFloor: _facialFloor,
        poorAngle: false,
        lowLight: false,
        unevenLighting: false,
      );

      expect(result.cropSharpness, greaterThan(0));
      expect(result.cropSharpness, lessThan(_facialFloor));
      expect(result.fullStillSharpness, greaterThanOrEqualTo(_facialFloor));
      expect(result.tag, 'blurry');
    });

    test('tag priority is unchanged', () {
      final sharp = _png(_sharpCrop());
      final soft = _png(_softCrop());
      String tag(
        Uint8List crop, {
        bool poorAngle = false,
        bool lowLight = false,
        bool uneven = false,
      }) => aiScanCaptureQualityFromUploadedCrop(
        uploadedCrop: crop,
        fullStill: crop,
        sharpnessFloor: _facialFloor,
        poorAngle: poorAngle,
        lowLight: lowLight,
        unevenLighting: uneven,
      ).tag;

      expect(tag(soft, poorAngle: true), 'poor_angle');
      expect(tag(soft, lowLight: true), 'blurry');
      expect(tag(sharp, lowLight: true), 'low_light');
      expect(tag(sharp, uneven: true), 'uneven_lighting');
    });
  });

  test('the AI-scan capture tags the uploaded crop, not the full still', () {
    final source = File(
      'lib/features/skin_tracker/presentation/screens/camera_screen.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> _captureAiSkinAnalysisFrames');
    expect(start, isNonNegative);
    final end = source.indexOf('\n  }\n', start);
    final body = source.substring(start, end);

    expect(body, contains('aiScanCaptureQualityFromUploadedCrop('));
    expect(body, contains('uploadedCrop: croppedFrames.first'));
    expect(body, contains('full_still_sharpness='));
    expect(
      body,
      isNot(
        contains(
          '_resolveSelectedFrameCaptureQuality(\n        capturedFiles.first',
        ),
      ),
    );
    expect(body, isNot(contains('_resolveSelectedFrameCaptureQuality(')));
  });
}
