import 'dart:io';
import 'dart:typed_data';

import 'package:aesthetic_skin_tracker/services/skin_analysis_service_io.dart';
import 'package:aesthetic_skin_tracker/utils/acne_rosacea_photo_analysis.dart';
import 'package:aesthetic_skin_tracker/utils/ai/efficientnet_skin_quality.dart';
import 'package:aesthetic_skin_tracker/utils/ai/skin_analysis_model.dart';
import 'package:aesthetic_skin_tracker/utils/ai/skin_analysis_runner.dart';
import 'package:aesthetic_skin_tracker/utils/ai/yolo_acne_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  test('missing model assets do not advertise running neural stages', () async {
    expect(await loadYoloAcneDetector(), isNull);
    expect(await loadEfficientNetSkinQuality(), isNull);
    expect(await SkinAnalysisAi.tryLoad(), isNull);
    final legacy = IoSkinAnalysisBackend();
    await legacy.init();
    expect(legacy.isMainModelReady, isFalse);
    legacy.dispose();

    final input = PhotoAnalysisInput(
      imagePath: 'fixture.jpg', capturedAt: DateTime(2026, 11, 1),
      region: FacialRegion.fullFace, inflammatoryAcne: 0, comedonalLoad: 0,
      cysticActivity: 0, redness: 0, visibleVessels: 0, flushingEpisodes: 0,
      sensitivity: 0, cycleRelatedFlare: false, adultOnset: false,
    );
    final augmentation = await SkinAnalysisRunner.augment(
      baseInput: input, imageBytes: Uint8List.fromList([1, 2, 3]),
    );
    expect(augmentation.modelInfo.isFallback, isTrue);
    expect(augmentation.aiInferenceUsed, isFalse);
    expect(augmentation.yoloUsed, isFalse);
    expect(augmentation.efficientNetUsed, isFalse);
    expect(augmentation.modelOwnedMetrics, isEmpty);
    expect(augmentation.input, same(input));
  });

  test('scan model banners remain gated on inference-use flags', () {
    final scan = File('lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart').readAsStringSync();
    expect(scan, contains("if (yoloUsed) 'YOLOv8-Nano Lesion Detector'"));
    expect(scan, contains("if (effUsed) 'EfficientNet-B0 Skin Quality'"));
    expect(scan, contains('final isAi = !info.isFallback'));
  });
}