// Shared types for on-device skin detection (YOLO + EfficientNet
// outputs). Lives in its own file so the public facades and the
// platform-specific native implementations all import the same
// Detection / BBox / NMS code.

import 'dart:math' as math;

/// Normalised bounding box (all values in [0, 1] relative to the
/// cropped face image).
class BBox {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const BBox(this.left, this.top, this.right, this.bottom);

  double get width => (right - left).clamp(0.0, 1.0);
  double get height => (bottom - top).clamp(0.0, 1.0);
  double get area => width * height;
}

/// One lesion / object detection from the YOLO acne model.
class Detection {
  final int classId;
  final String label;
  final double score;
  final BBox box;

  const Detection({
    required this.classId,
    required this.label,
    required this.score,
    required this.box,
  });
}

/// Multi-head skin quality scores from the EfficientNet model. Every
/// field is 0–1 where higher = better skin / less issue, except for
/// [wrinkles] and [pores] / [redness] which are inverted-natural: 0 =
/// none visible, 1 = severe. We intentionally keep the *raw* heads
/// here; the runner maps them into the app's 0–10 metric scale.
class SkinQualityScores {
  final double? texture; // 0=rough, 1=smooth
  final double? wrinkles; // 0=none, 1=severe
  final double? pores; // 0=invisible, 1=very visible
  final double? elasticity; // 0=loose, 1=firm
  final double? overall; // 0=poor, 1=excellent

  const SkinQualityScores({
    this.texture,
    this.wrinkles,
    this.pores,
    this.elasticity,
    this.overall,
  });

  bool get isEmpty =>
      texture == null &&
      wrinkles == null &&
      pores == null &&
      elasticity == null &&
      overall == null;
}

/// IoU between two normalised boxes.
double iou(BBox a, BBox b) {
  final interLeft = math.max(a.left, b.left);
  final interTop = math.max(a.top, b.top);
  final interRight = math.min(a.right, b.right);
  final interBottom = math.min(a.bottom, b.bottom);
  final iw = math.max(0.0, interRight - interLeft);
  final ih = math.max(0.0, interBottom - interTop);
  final inter = iw * ih;
  final union = a.area + b.area - inter;
  if (union <= 0) return 0;
  return inter / union;
}

/// Class-aware Non-Max Suppression. Returns the kept detections.
List<Detection> nonMaxSuppression(
  List<Detection> dets, {
  double iouThreshold = 0.45,
}) {
  if (dets.isEmpty) return const [];
  final sorted = [...dets]..sort((a, b) => b.score.compareTo(a.score));
  final keep = <Detection>[];
  for (final d in sorted) {
    bool drop = false;
    for (final k in keep) {
      if (k.classId == d.classId && iou(k.box, d.box) > iouThreshold) {
        drop = true;
        break;
      }
    }
    if (!drop) keep.add(d);
  }
  return keep;
}

/// Default class labels assumed by the YOLO acne detector. Override
/// at training time and update this list to match.
const List<String> kDefaultAcneLabels = [
  'papule',
  'pustule',
  'cyst',
  'blackhead',
  'whitehead',
  'dark_spot',
];
