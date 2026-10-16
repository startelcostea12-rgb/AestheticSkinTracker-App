/// Gray-card box marked by the user, mapped into the frame that is actually
/// uploaded (the square face crop), as fractions of that frame -- the
/// `gray_card_region` main.py's apply_gray_card_white_balance expects.
library;

import 'dart:math' as math;

import '../widgets/image_crop_dialog.dart' show NormalizedSquareCrop;

/// A box as fractions of an image: left, top, width, height in 0..1.
typedef GrayCardRegion = ({double x, double y, double w, double h});

/// Maps [stillBox] (fractions of the full still, [stillWidth] x
/// [stillHeight] px) into the square crop cut by applyNormalizedSquareCrop
/// with [crop] -- the same size / position / clamp math -- and returns it as
/// fractions of that crop. The part of the box outside the crop is dropped.
/// Returns null when no part of the box falls inside the uploaded crop (the
/// correction then stays off).
GrayCardRegion? grayCardRegionInUploadedFrame({
  required GrayCardRegion stillBox,
  required int stillWidth,
  required int stillHeight,
  required NormalizedSquareCrop crop,
}) {
  if (stillWidth <= 0 || stillHeight <= 0) return null;
  if (stillBox.w <= 0 || stillBox.h <= 0) return null;

  // Same as applyNormalizedSquareCrop.
  final sourceSize = math.min(stillWidth, stillHeight);
  final cropSize = (crop.size * sourceSize).round().clamp(1, sourceSize);
  final cropX = (crop.left * stillWidth).round().clamp(
    0,
    stillWidth - cropSize,
  );
  final cropY = (crop.top * stillHeight).round().clamp(
    0,
    stillHeight - cropSize,
  );

  final left = math.max(stillBox.x * stillWidth, cropX.toDouble());
  final top = math.max(stillBox.y * stillHeight, cropY.toDouble());
  final right = math.min(
    (stillBox.x + stillBox.w) * stillWidth,
    (cropX + cropSize).toDouble(),
  );
  final bottom = math.min(
    (stillBox.y + stillBox.h) * stillHeight,
    (cropY + cropSize).toDouble(),
  );
  if (right <= left || bottom <= top) return null;

  return (
    x: (left - cropX) / cropSize,
    y: (top - cropY) / cropSize,
    w: (right - left) / cropSize,
    h: (bottom - top) / cropSize,
  );
}
