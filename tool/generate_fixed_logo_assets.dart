import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  const sourcePath = 'assets/logo/logo.png';
  const fixedLogoPath = 'assets/logo/logo_safe_1024.png';
  const swirlSourcePath = 'assets/branding/splash_swirl_background.png';
  const swirlOutputPath = 'assets/branding/blush_swirl.png';

  final sourceFile = File(sourcePath);
  if (!sourceFile.existsSync()) {
    stderr.writeln('Source logo not found: $sourcePath');
    exitCode = 1;
    return;
  }

  final sourceBytes = sourceFile.readAsBytesSync();
  final source = img.decodeImage(sourceBytes);
  if (source == null) {
    stderr.writeln('Failed to decode source logo: $sourcePath');
    exitCode = 1;
    return;
  }

  final fixedLogo = _buildFixedSquareLogo(source);
  File(fixedLogoPath)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(fixedLogo, level: 9));

  final swirl = _buildBlushSwirl(swirlSourcePath);
  File(swirlOutputPath)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(swirl, level: 9));

  stdout.writeln('Generated $fixedLogoPath and $swirlOutputPath');
}

img.Image _buildFixedSquareLogo(img.Image source) {
  const int side = 1024;
  // Larger margin keeps the full motif/text well inside circular/adaptive masks.
  const int margin = 140;
  final maxContentSide = side - (margin * 2);

  final scale = source.width >= source.height
      ? maxContentSide / source.width
      : maxContentSide / source.height;

  final targetWidth = (source.width * scale).round().clamp(1, maxContentSide);
  final targetHeight = (source.height * scale).round().clamp(1, maxContentSide);

  final resized = img.copyResize(
    source,
    width: targetWidth,
    height: targetHeight,
    interpolation: img.Interpolation.average,
  );

  final canvas = img.Image(width: side, height: side, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

  final dx = ((side - targetWidth) / 2).round();
  final dy = ((side - targetHeight) / 2).round();

  img.compositeImage(canvas, resized, dstX: dx, dstY: dy);

  // Remove tiny near-transparent edge speckles that can cause icon fringing.
  for (var y = 0; y < canvas.height; y++) {
    for (var x = 0; x < canvas.width; x++) {
      final pixel = canvas.getPixel(x, y);
      final a = pixel.a.toInt();
      if (a <= 6) {
        canvas.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }

  return canvas;
}

img.Image _buildBlushSwirl(String sourcePath) {
  final sourceFile = File(sourcePath);
  if (sourceFile.existsSync()) {
    final decoded = img.decodeImage(sourceFile.readAsBytesSync());
    if (decoded != null) {
      final resized = img.copyResize(
        decoded,
        width: 1296,
        height: 1296,
        interpolation: img.Interpolation.linear,
      );
      final blurred = img.gaussianBlur(resized, radius: 4);
      return blurred;
    }
  }

  final fallback = img.Image(width: 1296, height: 1296, numChannels: 4);
  img.fill(fallback, color: img.ColorRgb8(252, 232, 239));
  return fallback;
}
