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
