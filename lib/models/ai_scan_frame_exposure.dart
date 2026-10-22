double? exifRationalAsDouble(String? value) {
  if (value == null) return null;
  final parts = value.split('/');
  if (parts.length != 2) return null;
  final numerator = double.tryParse(parts[0]);
  final denominator = double.tryParse(parts[1]);
  if (numerator == null || denominator == null || denominator == 0.0) {
    return null;
  }
  return numerator / denominator;
}

bool? exifFlashFiredFromValue(String? value) {
  final encoded = int.tryParse(value ?? '');
  if (encoded == null) return null;
  return (encoded & 0x1) == 0x1;
}

class AiScanFrameExposure {
  const AiScanFrameExposure({
    this.iso,
    this.exposureBias,
    this.shutterSeconds,
    this.brightnessValue,
    this.flashFired,
    this.exposureLockSucceeded,
    this.focusLockSucceeded,
    this.lensPosition,
    this.whiteBalanceTemperature,
    this.whiteBalanceRedGain,
    this.whiteBalanceGreenGain,
    this.whiteBalanceBlueGain,
  });

  final int? iso;
  final double? exposureBias;
  final double? shutterSeconds;
  final double? brightnessValue;
  final bool? flashFired;
  final bool? exposureLockSucceeded;
  final bool? focusLockSucceeded;
  final double? lensPosition;
  final double? whiteBalanceTemperature;
  final double? whiteBalanceRedGain;
  final double? whiteBalanceGreenGain;
  final double? whiteBalanceBlueGain;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'iso': iso,
    'exposure_bias': exposureBias,
    'shutter_seconds': shutterSeconds,
    'brightness_value': brightnessValue,
    'flash_fired': flashFired,
    'exposure_lock_succeeded': exposureLockSucceeded,
    'focus_lock_succeeded': focusLockSucceeded,
    'lens_position': lensPosition,
    'white_balance_temperature': whiteBalanceTemperature,
    'white_balance_red_gain': whiteBalanceRedGain,
    'white_balance_green_gain': whiteBalanceGreenGain,
    'white_balance_blue_gain': whiteBalanceBlueGain,
  };
}

/// The burst's exposure settings, read back from each frame's EXIF: the
/// first frame's ISO and shutter (the locked values) and whether every
/// frame reports the same ISO and shutter. [shared] is null when any frame
/// is missing either value (nothing to confirm).
({int? iso, double? shutterSeconds, bool? shared}) summarizeAiBurstExposure(
  List<AiScanFrameExposure> frames,
) {
  if (frames.isEmpty) return (iso: null, shutterSeconds: null, shared: null);
  final first = frames.first;
  final complete = frames.every(
    (f) => f.iso != null && f.shutterSeconds != null,
  );
  return (
    iso: first.iso,
    shutterSeconds: first.shutterSeconds,
    shared: complete
        ? frames.every(
            (f) =>
                f.iso == first.iso &&
                (f.shutterSeconds! - first.shutterSeconds!).abs() < 1e-9,
          )
        : null,
  );
}

/// One log line for the burst's locks and the settings the frames share.
String aiBurstLockLogLine({
  required bool exposureLockSucceeded,
  required bool focusLockSucceeded,
  required List<AiScanFrameExposure> frames,
}) {
  final summary = summarizeAiBurstExposure(frames);
  final shutter = summary.shutterSeconds;
  final shutterText = shutter == null || shutter <= 0
      ? 'null'
      : '${shutter.toStringAsFixed(5)}s (1/${(1 / shutter).round()})';
  return '[AI_BURST_LOCK] frames=${frames.length} '
      'exposure_lock=$exposureLockSucceeded focus_lock=$focusLockSucceeded '
      'locked_iso=${summary.iso} locked_exposure_time=$shutterText '
      'frames_share_settings=${summary.shared} '
      'isos=${[for (final f in frames) f.iso]} '
      'exposure_times=${[for (final f in frames) f.shutterSeconds]}';
}
