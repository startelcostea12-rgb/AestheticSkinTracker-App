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
    'lens_position': lensPosition,
    'white_balance_temperature': whiteBalanceTemperature,
    'white_balance_red_gain': whiteBalanceRedGain,
    'white_balance_green_gain': whiteBalanceGreenGain,
    'white_balance_blue_gain': whiteBalanceBlueGain,
  };
}
