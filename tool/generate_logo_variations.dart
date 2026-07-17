import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

void main() {
  final outDir = Directory('assets/branding/logo_variations');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  final variants = <String, img.Image>{
    'ast_logo_v1_wordmark.png': _variantWordmark(),
    'ast_logo_v2_icon_text.png': _variantIconText(),
    'ast_logo_v3_monogram.png': _variantMonogram(),
    'ast_logo_v4_orb_wordmark.png': _variantOrbWordmark(),
    'ast_logo_v5_luxe_badge.png': _variantLuxeBadge(),
  };

  for (final entry in variants.entries) {
    final file = File('${outDir.path}/${entry.key}');
    file.writeAsBytesSync(img.encodePng(entry.value));
  }

  stdout.writeln(
    'Generated ${variants.length} logo PNG variations in ${outDir.path}',
  );
}

img.Image _canvas() {
  final image = img.Image(width: 1024, height: 1024, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
  return image;
}

const _blush = (252, 232, 239);
const _gold = (224, 192, 112);
const _rose = (240, 196, 210);
const _pearl = (255, 247, 250);

img.ColorRgba8 _rgba((int, int, int) rgb, int a) =>
    img.ColorRgba8(rgb.$1, rgb.$2, rgb.$3, a);

void _drawSoftSwirls(img.Image image, {int seed = 0}) {
  final rnd = math.Random(seed);
  final paintColors = [
    _rgba(_blush, 90),
    _rgba(_rose, 75),
    _rgba(_gold, 55),
    _rgba(_pearl, 65),
  ];

  for (int i = 0; i < 18; i++) {
    final cx = 220 + rnd.nextInt(580);
    final cy = 220 + rnd.nextInt(580);
    final baseR = 110 + rnd.nextInt(250);
    final color = paintColors[i % paintColors.length];

    for (int ring = 0; ring < 4; ring++) {
      final r = baseR + ring * 18;
      final points = <(int x, int y)>[];
      for (double deg = 0; deg <= 360; deg += 6) {
        final t = deg * math.pi / 180.0;
        final wave = math.sin((t * 3.0) + i * 0.7) * (7 + ring * 3);
        final x = (cx + math.cos(t) * (r + wave)).round();
        final y = (cy + math.sin(t) * (r + wave)).round();
        points.add((x, y));
      }
      for (int p = 1; p < points.length; p++) {
        img.drawLine(
          image,
          x1: points[p - 1].$1,
          y1: points[p - 1].$2,
          x2: points[p].$1,
          y2: points[p].$2,
          color: color,
          antialias: true,
        );
      }
    }
  }
}

int _estimateTextWidth(String text, img.BitmapFont font) {
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
  final width = _estimateTextWidth(text, useFont);
  final x = ((image.width - width) / 2).round();
  img.drawString(image, text, font: useFont, x: x, y: y, color: color);
}

void _drawDiamond(img.Image image, int cx, int cy, int size, img.Color color) {
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
}

img.Image _variantWordmark() {
  final image = _canvas();
  _drawSoftSwirls(image, seed: 11);

  // Blush watercolor disk behind wordmark while keeping transparent outer canvas.
  img.fillCircle(image, x: 512, y: 500, radius: 320, color: _rgba(_blush, 118));
  img.fillCircle(image, x: 512, y: 500, radius: 290, color: _rgba(_pearl, 92));

  _drawCenteredText(
    image,
    'AestheticSkinTracker',
    y: 470,
    font: img.arial48,
    color: _rgba(_gold, 255),
  );
  _drawCenteredText(
    image,
    'AI Skin Progress Tracker',
    y: 545,
    font: img.arial24,
    color: _rgba(_gold, 220),
  );

  return image;
}

img.Image _variantIconText() {
  final image = _canvas();
  _drawSoftSwirls(image, seed: 22);

  img.fillCircle(image, x: 512, y: 395, radius: 190, color: _rgba(_pearl, 115));
  img.fillCircle(image, x: 512, y: 395, radius: 165, color: _rgba(_gold, 95));

  _drawDiamond(image, 512, 395, 142, _rgba(_gold, 255));
  _drawDiamond(image, 512, 395, 112, _rgba(_pearl, 210));

  // Subtle face silhouette line.
  img.drawLine(
    image,
    x1: 510,
    y1: 332,
    x2: 493,
    y2: 380,
    color: _rgba(_pearl, 245),
    antialias: true,
  );
  img.drawLine(
    image,
    x1: 493,
    y1: 380,
    x2: 505,
    y2: 426,
    color: _rgba(_pearl, 245),
    antialias: true,
  );
  img.drawLine(
    image,
    x1: 505,
    y1: 426,
    x2: 530,
    y2: 460,
    color: _rgba(_pearl, 245),
    antialias: true,
  );

  _drawCenteredText(
    image,
    'AestheticSkinTracker',
    y: 670,
    font: img.arial48,
    color: _rgba(_gold, 255),
  );

  return image;
}

img.Image _variantMonogram() {
  final image = _canvas();
  _drawSoftSwirls(image, seed: 33);

  img.fillCircle(image, x: 512, y: 410, radius: 230, color: _rgba(_blush, 96));

  // Layered text for shimmer-like gradient effect.
  _drawCenteredText(
    image,
    'AST',
    y: 325,
    font: img.arial48,
    color: _rgba(_pearl, 220),
  );
  _drawCenteredText(
    image,
    'AST',
    y: 330,
    font: img.arial48,
    color: _rgba(_gold, 255),
  );
  _drawCenteredText(
    image,
    'AST',
    y: 335,
    font: img.arial48,
    color: _rgba(_rose, 210),
  );

  _drawCenteredText(
    image,
    'AestheticSkinTracker',
    y: 620,
    font: img.arial24,
    color: _rgba(_gold, 245),
  );

  return image;
}

img.Image _variantOrbWordmark() {
  final image = _canvas();
  _drawSoftSwirls(image, seed: 44);

  img.fillCircle(image, x: 512, y: 365, radius: 210, color: _rgba(_gold, 90));
  img.fillCircle(image, x: 512, y: 365, radius: 165, color: _rgba(_pearl, 155));
  img.fillCircle(image, x: 512, y: 365, radius: 125, color: _rgba(_blush, 135));

  for (int i = 0; i < 8; i++) {
    final angle = (math.pi * 2 / 8) * i;
    final x = (512 + math.cos(angle) * 235).round();
    final y = (365 + math.sin(angle) * 235).round();
    img.fillCircle(image, x: x, y: y, radius: 8, color: _rgba(_gold, 205));
  }

  _drawCenteredText(
    image,
    'AestheticSkinTracker',
    y: 620,
    font: img.arial48,
    color: _rgba(_gold, 255),
  );

  return image;
}

img.Image _variantLuxeBadge() {
  final image = _canvas();
  _drawSoftSwirls(image, seed: 55);

  final left = 220;
  final top = 220;
  final right = 804;
  final bottom = 804;

  img.fillRect(
    image,
    x1: left,
    y1: top,
    x2: right,
    y2: bottom,
    color: _rgba(_pearl, 115),
  );
  img.drawRect(
    image,
    x1: left,
    y1: top,
    x2: right,
    y2: bottom,
    color: _rgba(_gold, 255),
    thickness: 3,
  );

  _drawCenteredText(
    image,
    'AST',
    y: 370,
    font: img.arial48,
    color: _rgba(_gold, 255),
  );
  _drawCenteredText(
    image,
    'AestheticSkinTracker',
    y: 520,
    font: img.arial24,
    color: _rgba(_gold, 248),
  );
  _drawCenteredText(
    image,
    'Blush Champagne Luxe',
    y: 565,
    font: img.arial24,
    color: _rgba(_rose, 210),
  );

  return image;
}
