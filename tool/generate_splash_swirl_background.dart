import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

void main() {
  final outDir = Directory('assets/branding');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  final image = img.Image(width: 1296, height: 1296, numChannels: 4);
  final blush = img.ColorRgb8(252, 232, 239);
  final rose = img.ColorRgb8(242, 203, 217);
  final gold = img.ColorRgb8(224, 192, 112);
  final pearl = img.ColorRgb8(255, 248, 251);

  img.fill(image, color: blush);

  final center = (image.width / 2, image.height / 2);
  for (int i = 0; i < 16; i++) {
    final radius = 150 + (i * 34);
    final pathPoints = <(int, int)>[];
    for (double deg = 0; deg <= 360; deg += 4) {
      final t = deg * math.pi / 180.0;
      final wave = math.sin((t * 3.3) + i * 0.8) * (12 + i * 0.8);
      final r = radius + wave;
      final x = (center.$1 + math.cos(t) * r).round();
      final y = (center.$2 + math.sin(t) * r).round();
      pathPoints.add((x, y));
    }

    final color = switch (i % 4) {
      0 => img.ColorRgba8(rose.r.toInt(), rose.g.toInt(), rose.b.toInt(), 68),
      1 => img.ColorRgba8(gold.r.toInt(), gold.g.toInt(), gold.b.toInt(), 46),
      2 => img.ColorRgba8(
        pearl.r.toInt(),
        pearl.g.toInt(),
        pearl.b.toInt(),
        56,
      ),
      _ => img.ColorRgba8(rose.r.toInt(), rose.g.toInt(), rose.b.toInt(), 40),
    };

    for (int p = 1; p < pathPoints.length; p++) {
      img.drawLine(
        image,
        x1: pathPoints[p - 1].$1,
        y1: pathPoints[p - 1].$2,
        x2: pathPoints[p].$1,
        y2: pathPoints[p].$2,
        color: color,
        antialias: true,
      );
    }
  }

  for (int i = 0; i < 50; i++) {
    final angle = i * (math.pi * 2 / 50);
    final x = (center.$1 + math.cos(angle) * 500).round();
    final y = (center.$2 + math.sin(angle) * 500).round();
    img.fillCircle(
      image,
      x: x,
      y: y,
      radius: 3,
      color: img.ColorRgba8(
        gold.r.toInt(),
        gold.g.toInt(),
        gold.b.toInt(),
        120,
      ),
    );
  }

  final file = File('${outDir.path}/splash_swirl_background.png');
  file.writeAsBytesSync(img.encodePng(image));
  stdout.writeln('Generated ${file.path}');
}
