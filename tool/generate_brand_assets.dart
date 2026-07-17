import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

class _Ipt {
  final int x;
  final int y;

  const _Ipt(this.x, this.y);
}

void main() {
  final outDir = Directory('assets/branding');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  final icon = _buildBrandImage(512, withText: true);
  final splash = _buildBrandImage(512, withText: false);

  File('${outDir.path}/app_icon_512.png').writeAsBytesSync(img.encodePng(icon));
  File(
    '${outDir.path}/splash_logo_512.png',
  ).writeAsBytesSync(img.encodePng(splash));

  stdout.writeln('Generated brand assets in assets/branding');
}

img.Image _buildBrandImage(int size, {required bool withText}) {
  final blush = img.ColorRgb8(247, 225, 216);
  final swirl = img.ColorRgb8(232, 188, 169);
  final gold = img.ColorRgb8(224, 192, 112);
  final deepGold = img.ColorRgb8(186, 147, 66);

  final image = img.Image(width: size, height: size, numChannels: 4);
  img.fill(image, color: blush);

  final centerX = size / 2;
  final centerY = size / 2;

  for (int i = 0; i < 9; i++) {
    final radius = size * (0.12 + (i * 0.055));
    final amp = 8 + (i * 2);
    final points = <_Ipt>[];
    for (double deg = 0; deg <= 360; deg += 4) {
      final t = deg * math.pi / 180.0;
      final wave = math.sin((t * 3.2) + i * 0.7) * amp;
      final r = radius + wave;
      final x = centerX + math.cos(t) * r;
      final y = centerY + math.sin(t) * r;
      points.add(_Ipt(x.toInt(), y.toInt()));
    }
    for (int p = 1; p < points.length; p++) {
      img.drawLine(
        image,
        x1: points[p - 1].x,
        y1: points[p - 1].y,
        x2: points[p].x,
        y2: points[p].y,
        color: i.isEven ? swirl : gold,
        antialias: true,
      );
    }
  }

  img.fillCircle(
    image,
    x: centerX.toInt(),
    y: centerY.toInt(),
    radius: (size * 0.16).toInt(),
    color: img.ColorRgba8(gold.r.toInt(), gold.g.toInt(), gold.b.toInt(), 180),
  );
  img.fillCircle(
    image,
    x: centerX.toInt(),
    y: centerY.toInt(),
    radius: (size * 0.135).toInt(),
    color: img.ColorRgba8(
      blush.r.toInt(),
      blush.g.toInt(),
      blush.b.toInt(),
      235,
    ),
  );

  if (withText) {
    img.drawString(
      image,
      'AST',
      font: img.arial48,
      x: (size * 0.365).toInt(),
      y: (size * 0.425).toInt(),
      color: deepGold,
    );
  } else {
    img.drawString(
      image,
      'A',
      font: img.arial48,
      x: (size * 0.455).toInt(),
      y: (size * 0.425).toInt(),
      color: deepGold,
    );
  }

  return image;
}
