import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

void main() {
  final outDir = Directory('assets/branding/logo_variations');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  final outputs = <String, img.Image>{
    'ast_logo_refined_v1.png': _variantWordmarkFocus(),
    'ast_logo_refined_v2.png': _variantMonogramText(),
    'ast_logo_refined_v3.png': _variantIconFaceText(),
  };

  for (final entry in outputs.entries) {
    final file = File('${outDir.path}/${entry.key}');
    file.writeAsBytesSync(img.encodePng(entry.value));
  }

  stdout.writeln(
    'Generated 3 refined 1024x1024 transparent logos in ${outDir.path}',
  );
}

const _blush = (252, 232, 239);
const _gold = (224, 192, 112);
const _roseGold = (232, 176, 183);
const _pearl = (255, 248, 251);

img.ColorRgba8 _rgba((int, int, int) rgb, int a) =>
    img.ColorRgba8(rgb.$1, rgb.$2, rgb.$3, a);

img.Image _canvas() {
  final image = img.Image(width: 1024, height: 1024, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
  return image;
}

void _drawWatercolorSwirls(img.Image image, {required int seed}) {
  final rnd = math.Random(seed);
  final colors = [
    _rgba(_blush, 88),
    _rgba(_roseGold, 64),
    _rgba(_gold, 44),
    _rgba(_pearl, 54),
  ];

  for (int i = 0; i < 16; i++) {
    final cx = 180 + rnd.nextInt(664);
    final cy = 180 + rnd.nextInt(664);
    final base = 130 + rnd.nextInt(190);
    final color = colors[i % colors.length];

    for (int ring = 0; ring < 3; ring++) {
      final r = base + ring * 22;
      int? prevX;
      int? prevY;
      for (double deg = 0; deg <= 360; deg += 5) {
        final t = deg * math.pi / 180.0;
        final wave = math.sin((t * 3.2) + (i * 0.7)) * (8 + ring * 2);
        final x = (cx + math.cos(t) * (r + wave)).round();
        final y = (cy + math.sin(t) * (r + wave)).round();
        if (prevX != null && prevY != null) {
          img.drawLine(
            image,
            x1: prevX,
            y1: prevY,
            x2: x,
            y2: y,
            color: color,
            antialias: true,
          );
        }
        prevX = x;
        prevY = y;
      }
    }
  }
}

void _drawPearlShimmer(img.Image image, int cx, int cy, int radius) {
  img.fillCircle(image, x: cx, y: cy, radius: radius, color: _rgba(_pearl, 84));
  img.fillCircle(
    image,
    x: cx - (radius ~/ 4),
    y: cy - (radius ~/ 4),
    radius: radius ~/ 3,
    color: _rgba(_pearl, 118),
  );
}

void _drawDiamondSparkle(
  img.Image image,
  int cx,
  int cy,
  int size,
  img.Color color,
) {
  img.drawLine(
    image,
    x1: cx,
    y1: cy - size,
    x2: cx + size,
    y2: cy,
    color: color,
    antialias: true,
  );
  img.drawLine(
    image,
    x1: cx + size,
    y1: cy,
    x2: cx,
    y2: cy + size,
    color: color,
    antialias: true,
  );
  img.drawLine(
    image,
    x1: cx,
    y1: cy + size,
    x2: cx - size,
    y2: cy,
    color: color,
    antialias: true,
  );
  img.drawLine(
    image,
    x1: cx - size,
    y1: cy,
    x2: cx,
    y2: cy - size,
    color: color,
    antialias: true,
  );

  img.drawLine(
    image,
    x1: cx - (size + 18),
    y1: cy,
    x2: cx + (size + 18),
    y2: cy,
    color: _rgba(_gold, 120),
    antialias: true,
  );
  img.drawLine(
    image,
    x1: cx,
    y1: cy - (size + 18),
    x2: cx,
    y2: cy + (size + 18),
    color: _rgba(_gold, 120),
    antialias: true,
  );
}

int _measureTextApprox(String text, img.BitmapFont font) {
  final perChar = identical(font, img.arial48) ? 28 : 15;
  return text.length * perChar;
}

void _drawCenteredText(
  img.Image image,
  String text, {
  required int y,
  required img.Color color,
  img.BitmapFont? font,
}) {
  final useFont = font ?? img.arial24;
  final x = ((image.width - _measureTextApprox(text, useFont)) / 2).round();
  img.drawString(image, text, font: useFont, x: x, y: y, color: color);
}

void _drawInfinityMotif(
  img.Image image, {
  required int cx,
  required int cy,
  required int width,
}) {
  final color = _rgba(_gold, 185);
  final loopRadius = width ~/ 5;

  for (int i = 0; i < 2; i++) {
    final offset = i == 0 ? -loopRadius : loopRadius;
    final loopCx = cx + offset;
    int? px;
    int? py;
    for (double deg = 0; deg <= 360; deg += 6) {
      final t = deg * math.pi / 180.0;
      final x = (loopCx + math.cos(t) * loopRadius).round();
      final y = (cy + math.sin(t) * (loopRadius * 0.72)).round();
      if (px != null && py != null) {
        img.drawLine(
          image,
          x1: px,
          y1: py,
          x2: x,
          y2: y,
          color: color,
          antialias: true,
        );
      }
      px = x;
      py = y;
    }
  }
}

img.Image _variantWordmarkFocus() {
  final image = _canvas();
  _drawWatercolorSwirls(image, seed: 711);

  _drawPearlShimmer(image, 512, 470, 320);
  _drawInfinityMotif(image, cx: 512, cy: 420, width: 320);
  _drawDiamondSparkle(image, 512, 360, 54, _rgba(_gold, 250));

  _drawCenteredText(
    image,
    'AestheticSkinTracker',
    y: 520,
    font: img.arial48,
    color: _rgba(_gold, 255),
  );
  _drawCenteredText(
    image,
    'AI Skin Progress Tracker',
    y: 598,
    font: img.arial24,
    color: _rgba(_gold, 218),
  );

  return image;
}

img.Image _variantMonogramText() {
  final image = _canvas();
  _drawWatercolorSwirls(image, seed: 722);

  _drawPearlShimmer(image, 512, 420, 280);
  _drawInfinityMotif(image, cx: 512, cy: 400, width: 260);

  _drawCenteredText(
    image,
    'AST',
    y: 308,
    font: img.arial48,
    color: _rgba(_pearl, 220),
  );
  _drawCenteredText(
    image,
    'AST',
    y: 314,
    font: img.arial48,
    color: _rgba(_gold, 255),
  );
  _drawDiamondSparkle(image, 632, 338, 22, _rgba(_gold, 235));

  _drawCenteredText(
    image,
    'AestheticSkinTracker',
    y: 560,
    font: img.arial48,
    color: _rgba(_gold, 255),
  );

  return image;
}

img.Image _variantIconFaceText() {
  final image = _canvas();
  _drawWatercolorSwirls(image, seed: 733);

  _drawPearlShimmer(image, 512, 390, 295);
  _drawDiamondSparkle(image, 512, 320, 62, _rgba(_gold, 250));

  // Soft face silhouette inside the orb.
  img.drawLine(
    image,
    x1: 510,
    y1: 274,
    x2: 486,
    y2: 350,
    color: _rgba(_pearl, 246),
    antialias: true,
  );
  img.drawLine(
    image,
    x1: 486,
    y1: 350,
    x2: 500,
    y2: 420,
    color: _rgba(_pearl, 246),
    antialias: true,
  );
  img.drawLine(
    image,
    x1: 500,
    y1: 420,
    x2: 538,
    y2: 472,
    color: _rgba(_pearl, 246),
    antialias: true,
  );

  _drawCenteredText(
    image,
    'AestheticSkinTracker',
    y: 574,
    font: img.arial48,
    color: _rgba(_gold, 255),
  );

  return image;
}
