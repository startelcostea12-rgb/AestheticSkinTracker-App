/// rawPayload keys recording the sharpness that decided an AI scan's
/// capture_quality tag: the uploaded face crop's sharpness (the value
/// compared against the floor), the uncropped full still's sharpness (for
/// comparison only), and the floor in force. Absent on scans saved before
/// these fields existed. Logging only -- nothing reads them to decide a
/// tag, metric, or lock.
const String aiCaptureCropSharpnessKey = 'crop_sharpness';
const String aiCaptureFullStillSharpnessKey = 'full_still_sharpness';
const String aiCaptureSharpnessFloorKey = 'sharpness_floor';

/// Records the capture sharpness values on [payload]. A null value is
/// written as null so an export shows an empty cell rather than a guess.
void recordAiCaptureSharpness(
  Map<String, dynamic> payload, {
  required double? cropSharpness,
  required double? fullStillSharpness,
  required double? sharpnessFloor,
}) {
  payload[aiCaptureCropSharpnessKey] = cropSharpness;
  payload[aiCaptureFullStillSharpnessKey] = fullStillSharpness;
  payload[aiCaptureSharpnessFloorKey] = sharpnessFloor;
}

/// Agreed facial AI-scan crop-sharpness floor, in the shared 4-neighbour
/// Laplacian-variance units used by both the app and the backend. Must stay
/// equal to [sharpnessVarianceFloorFor] for a facial guide. The older
/// backend cv2 ksize=3 threshold of 80 is a different scale and is no
/// longer used to decide [image_blurry].
const double aiScanCropSharpnessFloor = 36.0;

/// rawPayload / aggregate flag: the whole scan is unusable because at least
/// one frame's crop sharpness was below [aiScanCropSharpnessFloor]. Such a
/// scan must not be saved as a normal scan, a baseline, or a trend point.
const String aiScanRejectedForBlurKey = 'scan_rejected_for_blur';

/// True when a frame's crop sharpness is below [sharpnessFloor], including
/// a zero (undecodable) reading. The capture_quality "blurry" tag still
/// ignores a literal 0 so existing tag priority is unchanged; whole-scan
/// rejection is stricter because a 0-sharpness frame cannot be used.
bool cropSharpnessIsBelowFloor(
  double sharpness, [
  double sharpnessFloor = aiScanCropSharpnessFloor,
]) => sharpness < sharpnessFloor;

/// True when the burst cannot be kept: no crop sharpnesses, or any frame
/// is below [sharpnessFloor]. Checks every frame, not just frame 1.
bool aiScanFailsSharpnessFloor(
  Iterable<double> cropSharpnesses, {
  double sharpnessFloor = aiScanCropSharpnessFloor,
}) =>
    cropSharpnesses.isEmpty ||
    cropSharpnesses.any(
      (sharpness) => cropSharpnessIsBelowFloor(sharpness, sharpnessFloor),
    );
