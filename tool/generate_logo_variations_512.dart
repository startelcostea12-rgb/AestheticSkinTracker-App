import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

void main() {
  final outDir = Directory('assets/branding/logo_variations');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  final variants = <String, img.Image>{
    'ast_logo_v1_wordmark_512.png': _v1Wordmark(),
    'ast_logo_v2_icon_text_512.png': _v2IconText(),
    'ast_logo_v3_monogram_512.png': _v3Monogram(),
    'ast_logo_v4_orb_wordmark_512.png': _v4OrbWordmark(),
    'ast_logo_v5_luxe_badge_512.png': _v5LuxeBadge(),
  };

  for (final entry in variants.entries) {
    File(
      '${outDir.path}/${entry.key}',
    ).writeAsBytesSync(img.encodePng(entry.value));
  }

  stdout.writeln(
    'Generated ${variants.length} optimized 512 logo variations in ${outDir.path}',
  );
}

const _blush = (252, 232, 239);
const _gold = (224, 192, 112);
const _rose = (240, 196, 210);
const _pearl = (255, 247, 250);

img.ColorRgba8 _rgba((int, int, int) rgb, int a) =>
    img.ColorRgba8(rgb.$1, rgb.$2, rgb.$3, a);

img.Image _canvas() {
  final image = img.Image(width: 512, height: 512, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
  return image;
}

int _textWidth(String text, img.BitmapFont font) {
  final perChar = identical(font, img.arial48) ? 15 : 8;
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
  final x = ((image.width - _textWidth(text, useFont)) / 2).round();
  img.drawString(image, text, font: useFont, x: x, y: y, color: color);
}

void _drawSwirls(img.Image image, {required int seed}) {
  final rnd = math.Random(seed);
  final colors = [
    _rgba(_blush, 86),
    _rgba(_rose, 72),
    _rgba(_gold, 58),
    _rgba(_pearl, 62),
  ];

  for (int i = 0; i < 12; i++) {
    final cx = 110 + rnd.nextInt(292);
    final cy = 110 + rnd.nextInt(292);
    final base = 56 + rnd.nextInt(110);
    final c = colors[i % colors.length];

    for (int ring = 0; ring < 3; ring++) {
      final r = base + ring * 10;
      int? px;
      int? py;
      for (double deg = 0; deg <= 360; deg += 8) {
        final t = deg * math.pi / 180.0;
        final wave = math.sin((t * 3.0) + i * 0.6) * (4 + ring * 2);
        final x = (cx + math.cos(t) * (r + wave)).round();
        final y = (cy + math.sin(t) * (r + wave)).round();
        if (px != null && py != null) {
          img.drawLine(
            image,
            x1: px,
            y1: py,
            x2: x,
            y2: y,
            color: c,
            antialias: true,
          );
        }
        px = x;
        py = y;
      }
    }
  }
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

img.Image _v1Wordmark() {
  final image = _canvas();
  _drawSwirls(image, seed: 101);

  img.fillCircle(image, x: 256, y: 246, radius: 170, color: _rgba(_blush, 118));
  img.fillCircle(image, x: 256, y: 246, radius: 145, color: _rgba(_pearl, 96));

  _drawCenteredText(
    image,
    'AestheticSkinTracker',
    y: 218,
    font: img.arial24,
    color: _rgba(_gold, 255),
  );

  return image;
}

img.Image _v2IconText() {
  final image = _canvas();
  _drawSwirls(image, seed: 202);

  img.fillCircle(image, x: 256, y: 192, radius: 96, color: _rgba(_pearl, 120));
  img.fillCircle(image, x: 256, y: 192, radius: 84, color: _rgba(_gold, 92));

  _drawDiamond(image, 256, 192, 66, _rgba(_gold, 255));
  _drawDiamond(image, 256, 192, 52, _rgba(_pearl, 225));

  img.drawLine(
    image,
    x1: 255,
    y1: 164,
    x2: 246,
    y2: 186,
    color: _rgba(_pearl, 245),
    antialias: true,
  );
  img.drawLine(
    image,
    x1: 246,
    y1: 186,
    x2: 253,
    y2: 206,
    color: _rgba(_pearl, 245),
    antialias: true,
  );
  img.drawLine(
    image,
    x1: 253,
    y1: 206,
    x2: 266,
    y2: 222,
    color: _rgba(_pearl, 245),
    antialias: true,
  );

  _drawCenteredText(
    image,
    'AestheticSkinTracker',
    y: 332,
    font: img.arial24,
    color: _rgba(_gold, 255),
  );

  return image;
}

img.Image _v3Monogram() {
  final image = _canvas();
  _drawSwirls(image, seed: 303);

  img.fillCircle(image, x: 256, y: 202, radius: 114, color: _rgba(_blush, 108));

  _drawCenteredText(
    image,
    'AST',
    y: 160,
    font: img.arial48,
    color: _rgba(_pearl, 214),
  );
  _drawCenteredText(
    image,
    'AST',
    y: 163,
    font: img.arial48,
    color: _rgba(_gold, 255),
  );

  _drawCenteredText(
    image,
    'AestheticSkinTracker',
    y: 334,
    font: img.arial24,
    color: _rgba(_gold, 248),
  );

  return image;
}

img.Image _v4OrbWordmark() {
  final image = _canvas();
  _drawSwirls(image, seed: 404);

  img.fillCircle(image, x: 256, y: 182, radius: 104, color: _rgba(_gold, 92));
  img.fillCircle(image, x: 256, y: 182, radius: 82, color: _rgba(_pearl, 148));
  img.fillCircle(image, x: 256, y: 182, radius: 60, color: _rgba(_blush, 138));

  for (int i = 0; i < 8; i++) {
    final a = (math.pi * 2 / 8) * i;
    final x = (256 + math.cos(a) * 116).round();
    final y = (182 + math.sin(a) * 116).round();
    img.fillCircle(image, x: x, y: y, radius: 4, color: _rgba(_gold, 215));
  }

  _drawCenteredText(
    image,
    'AestheticSkinTracker',
    y: 326,
    font: img.arial24,
    color: _rgba(_gold, 255),
  );

  return image;
}

img.Image _v5LuxeBadge() {
  final image = _canvas();
  _drawSwirls(image, seed: 505);

  const left = 86;
  const top = 94;
  const right = 426;
  const bottom = 418;

  img.fillRect(
    image,
    x1: left,
    y1: top,
    x2: right,
    y2: bottom,
    color: _rgba(_pearl, 116),
  );
  img.drawRect(
    image,
    x1: left,
    y1: top,
    x2: right,
    y2: bottom,
    color: _rgba(_gold, 255),
    thickness: 2,
  );

  _drawCenteredText(
    image,
    'AST',
    y: 170,
    font: img.arial48,
    color: _rgba(_gold, 255),
  );
  _drawCenteredText(
    image,
    'AestheticSkinTracker',
    y: 262,
    font: img.arial24,
    color: _rgba(_gold, 248),
  );

  return image;
}
