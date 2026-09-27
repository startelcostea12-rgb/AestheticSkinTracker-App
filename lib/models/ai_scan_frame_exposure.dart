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

class AiScanFrameExposure {
  const AiScanFrameExposure({
    this.iso,
    this.exposureBias,
    this.shutterSeconds,
    this.brightnessValue,
  });

  final int? iso;
  final double? exposureBias;
  final double? shutterSeconds;
  final double? brightnessValue;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'iso': iso,
    'exposure_bias': exposureBias,
    'shutter_seconds': shutterSeconds,
    'brightness_value': brightnessValue,
  };
}
