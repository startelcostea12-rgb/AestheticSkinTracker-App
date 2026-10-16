/// Gray-card box marked by the user on the full captured still, and the
/// patch cut from each still for upload. The card may sit anywhere in the
/// still (e.g. under the chin, outside the uploaded face square): the patch
/// is uploaded next to the face crop as `gray_card_image`, and main.py
/// samples it before white balance (see _sample_gray_card).
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A box as fractions of an image: left, top, width, height in 0..1.
typedef GrayCardRegion = ({double x, double y, double w, double h});

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
