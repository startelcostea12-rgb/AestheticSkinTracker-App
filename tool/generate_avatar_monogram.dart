import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  const sourcePath = 'assets/images/logo.png';
  const outputMonogramPath = 'assets/logo/monogram.png';
  const outputAstMonogramPath = 'assets/images/logo_app_icon.png';

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

  final accent = _averageVisibleColor(source);
  final monogram = _buildMonogram(accent);

  File(outputMonogramPath)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(monogram, level: 9));
  File(outputAstMonogramPath)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(monogram, level: 9));

  stdout.writeln('Generated $outputMonogramPath and $outputAstMonogramPath');
}

img.ColorRgb8 _averageVisibleColor(img.Image source) {
  int r = 0;
  int g = 0;
  int b = 0;
  int count = 0;

  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final p = source.getPixel(x, y);
      if (p.a.toInt() < 20) {
        continue;
      }
      r += p.r.toInt();
      g += p.g.toInt();
      b += p.b.toInt();
      count++;
    }
  }

  if (count == 0) {
    return img.ColorRgb8(237, 190, 140);
  }

  return img.ColorRgb8(r ~/ count, g ~/ count, b ~/ count);
}

img.Image _buildMonogram(img.ColorRgb8 accent) {
  const side = 1024;
  final canvas = img.Image(width: side, height: side, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

  final baseGold = img.ColorRgba8(211, 165, 76, 255);
  final edgeShadow = img.ColorRgba8(148, 106, 41, 120);

  const glyphTop = 290;
  const glyphHeight = 456;
  const glyphWidth = 208;
  const gap = 52;
  const stroke = 28;
  final totalWidth = (glyphWidth * 3) + (gap * 2);
  final startX = ((side - totalWidth) / 2).round();

  final ax = startX;
  final sx = ax + glyphWidth + gap;
  final tx = sx + glyphWidth + gap;

  // Subtle underlay to improve legibility without decorative effects.
  _drawA(
    canvas,
    ax + 2,
    glyphTop + 2,
    glyphWidth,
    glyphHeight,
    stroke,
    edgeShadow,
  );
  _drawS(
    canvas,
    sx + 2,
    glyphTop + 2,
    glyphWidth,
    glyphHeight,
    stroke,
    edgeShadow,
  );
  _drawT(
    canvas,
    tx + 2,
    glyphTop + 2,
    glyphWidth,
    glyphHeight,
    stroke,
    edgeShadow,
  );

  // Main clean glyphs.
  _drawA(canvas, ax, glyphTop, glyphWidth, glyphHeight, stroke, baseGold);
  _drawS(canvas, sx, glyphTop, glyphWidth, glyphHeight, stroke, baseGold);
  _drawT(canvas, tx, glyphTop, glyphWidth, glyphHeight, stroke, baseGold);

  return canvas;
}

void _drawA(
  img.Image image,
  int x,
  int y,
  int w,
  int h,
  int s,
  img.Color color,
) {
  _strokeDiag(image, x + (s ~/ 2), y + h, x + (w ~/ 2), y, s, color);
  _strokeDiag(image, x + (w - (s ~/ 2)), y + h, x + (w ~/ 2), y, s, color);
  _strokeH(image, x + (w ~/ 4), y + (h ~/ 2), x + (w - (w ~/ 4)), s, color);
}

void _drawS(
  img.Image image,
  int x,
  int y,
  int w,
  int h,
  int s,
  img.Color color,
) {
  final topY = y + (s ~/ 2);
  final midY = y + (h ~/ 2);
  final botY = y + h - (s ~/ 2);
  _strokeH(image, x + (s ~/ 2), topY, x + w - (s ~/ 2), s, color);
  _strokeV(image, x + (s ~/ 2), topY, midY, s, color);
  _strokeH(image, x + (s ~/ 2), midY, x + w - (s ~/ 2), s, color);
  _strokeV(image, x + w - (s ~/ 2), midY, botY, s, color);
  _strokeH(image, x + (s ~/ 2), botY, x + w - (s ~/ 2), s, color);
}

void _drawT(
  img.Image image,
  int x,
  int y,
  int w,
  int h,
  int s,
  img.Color color,
) {
  _strokeH(image, x + (s ~/ 2), y + (s ~/ 2), x + w - (s ~/ 2), s, color);
  _strokeV(image, x + (w ~/ 2), y + (s ~/ 2), y + h, s, color);
}

void _strokeH(
  img.Image image,
  int x1,
  int y,
  int x2,
  int stroke,
  img.Color color,
) {
  final top = y - (stroke ~/ 2);
  final bot = y + (stroke ~/ 2);
  img.fillRect(image, x1: x1, y1: top, x2: x2, y2: bot, color: color);
  img.fillCircle(image, x: x1, y: y, radius: stroke ~/ 2, color: color);
  img.fillCircle(image, x: x2, y: y, radius: stroke ~/ 2, color: color);
}

void _strokeV(
  img.Image image,
  int x,
  int y1,
  int y2,
  int stroke,
  img.Color color,
) {
  final left = x - (stroke ~/ 2);
  final right = x + (stroke ~/ 2);
  img.fillRect(image, x1: left, y1: y1, x2: right, y2: y2, color: color);
  img.fillCircle(image, x: x, y: y1, radius: stroke ~/ 2, color: color);
  img.fillCircle(image, x: x, y: y2, radius: stroke ~/ 2, color: color);
}

void _strokeDiag(
  img.Image image,
  int x1,
  int y1,
  int x2,
  int y2,
  int stroke,
  img.Color color,
) {
  for (var i = -(stroke ~/ 2); i <= (stroke ~/ 2); i++) {
    img.drawLine(image, x1: x1 + i, y1: y1, x2: x2 + i, y2: y2, color: color);
  }
  img.fillCircle(image, x: x1, y: y1, radius: stroke ~/ 2, color: color);
  img.fillCircle(image, x: x2, y: y2, radius: stroke ~/ 2, color: color);
}
