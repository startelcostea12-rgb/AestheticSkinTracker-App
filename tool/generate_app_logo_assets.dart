import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  const sourcePath = 'assets/logo/AST LOGO1.png';
  const fullLogoPath = 'assets/images/logo.png';
  const iconLogoPath = 'assets/images/logo_app_icon.png';
  const appBarLogoPath = 'assets/images/logo_appbar.png';
  const welcomeLogoPath = 'assets/images/logo_welcome.png';
  const transparentLogoPath = 'assets/images/logo_transparent.png';

  final sourceFile = File(sourcePath);
  if (!sourceFile.existsSync()) {
    stderr.writeln('Source logo not found: $sourcePath');
    exitCode = 1;
    return;
  }

  final decoded = img.decodeImage(sourceFile.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('Failed to decode source logo: $sourcePath');
    exitCode = 1;
    return;
  }

  final displayLogo = _buildDisplayLogo(decoded);
  File(fullLogoPath)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(displayLogo, level: 9));

  final square = _buildSquareIcon(decoded);
  File(iconLogoPath)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(square, level: 9));

  final appBarLogo = _buildAppBarLogo(decoded);
  File(appBarLogoPath)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(appBarLogo, level: 9));

  final welcomeLogo = _buildWelcomeLogo(decoded);
  File(welcomeLogoPath)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(welcomeLogo, level: 9));

  final transparentLogo = _buildTransparentLogo(decoded);
  File(transparentLogoPath)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(transparentLogo, level: 9));

  stdout.writeln(
    'Generated $fullLogoPath, $iconLogoPath, $appBarLogoPath, $welcomeLogoPath, and $transparentLogoPath',
  );
}

img.Image _buildDisplayLogo(img.Image source) {
  final cropped = _trimTransparentBorder(source);
  // Canvas matches the cropped art's aspect ratio with minimal padding
  final double aspect = cropped.width / cropped.height;
  const targetHeight = 280;
  final targetWidth = (targetHeight * aspect).round();
  const horizontalPadding = 4;
  const verticalPadding = 4;

  final canvas = img.Image(
    width: targetWidth,
    height: targetHeight,
    numChannels: 4,
  );
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

  final maxWidth = targetWidth - (horizontalPadding * 2);
  final maxHeight = targetHeight - (verticalPadding * 2);
  final scale = cropped.width / cropped.height > maxWidth / maxHeight
      ? maxWidth / cropped.width
      : maxHeight / cropped.height;

  final resized = img.copyResize(
    cropped,
    width: (cropped.width * scale).round(),
    height: (cropped.height * scale).round(),
    interpolation: img.Interpolation.linear,
  );

  final dx = ((targetWidth - resized.width) / 2).round();
  final dy = ((targetHeight - resized.height) / 2).round();
  img.compositeImage(canvas, resized, dstX: dx, dstY: dy);
  return canvas;
}

img.Image _buildSquareIcon(img.Image source) {
  const side = 1024;
  const margin = 150;
  final canvas = img.Image(width: side, height: side, numChannels: 4);
  img.fill(canvas, color: img.ColorRgb8(255, 253, 250));

  final targetMaxWidth = side - (margin * 2);
  final targetMaxHeight = side - (margin * 2);
  final scale = source.width / source.height > targetMaxWidth / targetMaxHeight
      ? targetMaxWidth / source.width
      : targetMaxHeight / source.height;

  final resized = img.copyResize(
    source,
    width: (source.width * scale).round(),
    height: (source.height * scale).round(),
    interpolation: img.Interpolation.linear,
  );

  final dx = ((side - resized.width) / 2).round();
  final dy = ((side - resized.height) / 2).round();
  img.compositeImage(canvas, resized, dstX: dx, dstY: dy);
  return canvas;
}

img.Image _buildAppBarLogo(img.Image source) {
  final cropped = _trimNearWhiteBorder(source);
  const targetWidth = 720;
  const targetHeight = 168;
  const horizontalPadding = 20;
  const verticalPadding = 14;

  final canvas = img.Image(
    width: targetWidth,
    height: targetHeight,
    numChannels: 4,
  );
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

  final maxWidth = targetWidth - (horizontalPadding * 2);
  final maxHeight = targetHeight - (verticalPadding * 2);
  final scale = cropped.width / cropped.height > maxWidth / maxHeight
      ? maxWidth / cropped.width
      : maxHeight / cropped.height;

  final resized = img.copyResize(
    cropped,
    width: (cropped.width * scale).round(),
    height: (cropped.height * scale).round(),
    interpolation: img.Interpolation.linear,
  );

  final dx = ((targetWidth - resized.width) / 2).round();
  final dy = ((targetHeight - resized.height) / 2).round();
  img.compositeImage(canvas, resized, dstX: dx, dstY: dy);
  return canvas;
}

img.Image _buildWelcomeLogo(img.Image source) {
  final cropped = _trimNearWhiteBorderTight(source);
  const targetWidth = 560;
  const targetHeight = 180;
  const horizontalPadding = 10;
  const verticalPadding = 8;

  final canvas = img.Image(
    width: targetWidth,
    height: targetHeight,
    numChannels: 4,
  );
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

  final maxWidth = targetWidth - (horizontalPadding * 2);
  final maxHeight = targetHeight - (verticalPadding * 2);
  final scale = cropped.width / cropped.height > maxWidth / maxHeight
      ? maxWidth / cropped.width
      : maxHeight / cropped.height;

  final resized = img.copyResize(
    cropped,
    width: (cropped.width * scale).round(),
    height: (cropped.height * scale).round(),
    interpolation: img.Interpolation.linear,
  );

  final dx = ((targetWidth - resized.width) / 2).round();
  final dy = ((targetHeight - resized.height) / 2).round();
  img.compositeImage(canvas, resized, dstX: dx, dstY: dy);
  return canvas;
}

img.Image _buildTransparentLogo(img.Image source) {
  final transparent = img.Image(
    width: source.width,
    height: source.height,
    numChannels: 4,
  );
  img.fill(transparent, color: img.ColorRgba8(0, 0, 0, 0));

  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final pixel = source.getPixel(x, y);
      if (!_isLightBackdropPixel(pixel)) {
        transparent.setPixelRgba(
          x,
          y,
          pixel.r.toInt(),
          pixel.g.toInt(),
          pixel.b.toInt(),
          pixel.a.toInt(),
        );
      }
    }
  }

  return _trimTransparentBorder(transparent);
}

bool _isLightBackdropPixel(img.Pixel pixel) {
  final alpha = pixel.a.toInt();
  if (alpha <= 10) {
    return false;
  }

  final red = pixel.r.toInt();
  final green = pixel.g.toInt();
  final blue = pixel.b.toInt();
  final maxChannel = [red, green, blue].reduce((a, b) => a > b ? a : b);
  final minChannel = [red, green, blue].reduce((a, b) => a < b ? a : b);
  final spread = maxChannel - minChannel;
  final luminance = (red * 0.299) + (green * 0.587) + (blue * 0.114);

  return luminance >= 210 && spread <= 42;
}

img.Image _trimTransparentBorder(img.Image source) {
  int minX = source.width, minY = source.height, maxX = -1, maxY = -1;
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final pixel = source.getPixel(x, y);
      if (pixel.a.toInt() > 10) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX <= minX || maxY <= minY) return source;
  const pad = 2;
  return img.copyCrop(
    source,
    x: (minX - pad).clamp(0, source.width - 1),
    y: (minY - pad).clamp(0, source.height - 1),
    width:
        (maxX + pad).clamp(0, source.width - 1) -
        (minX - pad).clamp(0, source.width - 1) +
        1,
    height:
        (maxY + pad).clamp(0, source.height - 1) -
        (minY - pad).clamp(0, source.height - 1) +
        1,
  );
}

img.Image _trimNearWhiteBorder(img.Image source) {
  int minX = source.width;
  int minY = source.height;
  int maxX = -1;
  int maxY = -1;

  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final pixel = source.getPixel(x, y);
      final alpha = pixel.a.toInt();
      final red = pixel.r.toInt();
      final green = pixel.g.toInt();
      final blue = pixel.b.toInt();
      final isNearlyWhite = red > 245 && green > 245 && blue > 245;
      if (alpha > 10 && !isNearlyWhite) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
  }

  if (maxX <= minX || maxY <= minY) {
    return source;
  }

  const padX = 24;
  const padY = 18;
  final left = (minX - padX).clamp(0, source.width - 1);
  final top = (minY - padY).clamp(0, source.height - 1);
  final right = (maxX + padX).clamp(0, source.width - 1);
  final bottom = (maxY + padY).clamp(0, source.height - 1);

  return img.copyCrop(
    source,
    x: left,
    y: top,
    width: right - left + 1,
    height: bottom - top + 1,
  );
}

img.Image _trimNearWhiteBorderTight(img.Image source) {
  int minX = source.width;
  int minY = source.height;
  int maxX = -1;
  int maxY = -1;

  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final pixel = source.getPixel(x, y);
      final alpha = pixel.a.toInt();
      final red = pixel.r.toInt();
      final green = pixel.g.toInt();
      final blue = pixel.b.toInt();
      final isNearlyWhite = red > 245 && green > 245 && blue > 245;
      if (alpha > 10 && !isNearlyWhite) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
  }

  if (maxX <= minX || maxY <= minY) {
    return source;
  }

  const padX = 6;
  const padY = 6;
  final left = (minX - padX).clamp(0, source.width - 1);
  final top = (minY - padY).clamp(0, source.height - 1);
  final right = (maxX + padX).clamp(0, source.width - 1);
  final bottom = (maxY + padY).clamp(0, source.height - 1);

  return img.copyCrop(
    source,
    x: left,
    y: top,
    width: right - left + 1,
    height: bottom - top + 1,
  );
}
