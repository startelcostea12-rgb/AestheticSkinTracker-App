/// Gray-card sampling: a fixed under-chin target on the live preview
/// ([grayCardPreviewTarget]), its position in the full captured still
/// ([grayCardTargetInStill]), and the patch cut from each still for upload
/// ([grayCardPatchFromStill]). The patch is uploaded next to the face crop
/// as `gray_card_image`, and main.py samples it before white balance.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A box as fractions of an image: left, top, width, height in 0..1.
typedef GrayCardRegion = ({double x, double y, double w, double h});

/// The fixed "Place gray card here" target, as fractions of the visible face
/// preview: centred horizontally and just below the face oval (which ends at
/// 66% of the preview height in AdaptiveCameraOutline). Centred, so a
/// mirrored front-camera preview does not move it.
const GrayCardRegion grayCardPreviewTarget = (
  x: 0.32,
  y: 0.70,
  w: 0.36,
  h: 0.15,
);

/// [target] (fractions of the visible preview, whose width:height is
/// [previewAspect]) as fractions of the full still. The preview shows a
/// centred BoxFit.cover crop of the frame at [previewAspect] -- the same
/// model the face-framing check uses -- so the visible part of the still is
/// the centred [previewAspect] window and the target maps linearly into it.
GrayCardRegion grayCardTargetInStill({
  required int stillWidth,
  required int stillHeight,
  required double previewAspect,
  GrayCardRegion target = grayCardPreviewTarget,
}) {
  final stillAspect = stillWidth / stillHeight;
  var visibleW = 1.0;
  var visibleH = 1.0;
  if (stillAspect > previewAspect) {
    visibleW = previewAspect / stillAspect;
  } else {
    visibleH = stillAspect / previewAspect;
  }
  final offsetX = (1.0 - visibleW) / 2.0;
  final offsetY = (1.0 - visibleH) / 2.0;
  return (
    x: offsetX + target.x * visibleW,
    y: offsetY + target.y * visibleH,
    w: target.w * visibleW,
    h: target.h * visibleH,
  );
}

/// The pixels inside [box] (fractions of the decoded still in
/// [stillBytes]), cut from the same decoded, upright pixels the face crop is
/// cut from, as lossless PNG so the card's colour is not re-compressed.
/// Null when the still cannot be decoded or the box has no pixels.
Uint8List? grayCardPatchFromStill(Uint8List stillBytes, GrayCardRegion box) {
  img.Image? still;
  try {
    still = img.decodeImage(stillBytes);
  } catch (_) {
    still = null;
  }
  if (still == null) return null;
  final w = still.width;
  final h = still.height;
  final x0 = (box.x * w).round().clamp(0, w);
  final y0 = (box.y * h).round().clamp(0, h);
  final x1 = ((box.x + box.w) * w).round().clamp(0, w);
  final y1 = ((box.y + box.h) * h).round().clamp(0, h);
  if (x1 <= x0 || y1 <= y0) return null;
  final patch = img.copyCrop(
    still,
    x: x0,
    y: y0,
    width: x1 - x0,
    height: y1 - y0,
  );
  return Uint8List.fromList(img.encodePng(patch));
}
