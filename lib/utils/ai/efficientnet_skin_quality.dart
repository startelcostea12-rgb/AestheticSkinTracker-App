// EfficientNetSkinQuality — public facade.
//
// Loads `assets/models/efficientnet_skin_quality.tflite`
// (EfficientNet-B0 multi-head export, 224×224 input, ImageNet
// normalised) and returns global skin-quality scores: texture,
// wrinkles, pores, elasticity, overall. The output head count and
// order are read dynamically from the tensor shape so re-training
// with a different number of heads doesn't break anything.

import 'dart:typed_data';

import 'efficientnet_skin_quality_stub.dart'
    if (dart.library.io) 'efficientnet_skin_quality_native.dart'
    as impl;
import 'skin_detections.dart';

abstract class EfficientNetSkinQuality {
  /// Run inference on already-cropped face [bytes]. Null on failure.
  Future<SkinQualityScores?> analyze(Uint8List bytes);

  void dispose();
}

Future<EfficientNetSkinQuality?> loadEfficientNetSkinQuality() =>
    impl.loadEfficientNetSkinQuality();
