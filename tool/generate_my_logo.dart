import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Generates a concept logo preview PNG.
/// Output: assets/images/logo_preview_concept.png
void main() {
  const side = 1024;
  const cx = side / 2.0;
  const cy = side / 2.0;

  final canvas = img.Image(width: side, height: side, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

  _fillCircleGradient(canvas, cx, cy, 460.0);
  _drawRing(
    canvas,
    cx,
    cy,
    405.0,
    thickness: 3,
    color: img.ColorRgba8(255, 235, 210, 120),
  );
  _drawLeaf(
    canvas,
    cx: cx - 18,
    cy: cy - 55,
    w: 170.0,
    h: 310.0,
    tilt: -0.32,
    color: img.ColorRgba8(255, 255, 255, 200),
  );
  _drawDroplet(
    canvas,
    cx: cx + 52,
    cy: cy + 55,
    r: 58.0,
    tipH: 98.0,
    color: img.ColorRgba8(255, 215, 190, 195),
  );

  for (var i = -55; i <= 55; i++) {
    final x = (cx + i).round();
    final y = (cy + 195).round();
    _blendPixel(canvas, x, y - 1, img.ColorRgba8(255, 255, 255, 100));
    _blendPixel(canvas, x, y, img.ColorRgba8(255, 255, 255, 160));
    _blendPixel(canvas, x, y + 1, img.ColorRgba8(255, 255, 255, 100));
  }

  const outPath = 'assets/images/logo_preview_concept.png';
  File(outPath)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(canvas, level: 9));

  stdout.writeln('Preview saved to $outPath');
}

void _fillCircleGradient(img.Image dst, double cx, double cy, double r) {
  for (var y = (cy - r).floor(); y <= (cy + r).ceil(); y++) {
    for (var x = (cx - r).floor(); x <= (cx + r).ceil(); x++) {
      if (x < 0 || y < 0 || x >= dst.width || y >= dst.height) {
        continue;
      }
      final dist = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
      if (dist > r) {
        continue;
      }
      final t = dist / r;
      final red = (200 + (245 - 200) * t).round().clamp(0, 255);
      final green = (130 + (200 - 130) * t).round().clamp(0, 255);
      final blue = (104 + (180 - 104) * t).round().clamp(0, 255);
      final alpha = dist > r - 2.5
          ? ((r - dist) / 2.5 * 255).round().clamp(0, 255)
          : 255;
      _blendPixel(dst, x, y, img.ColorRgba8(red, green, blue, alpha));
    }
  }
}

void _drawRing(
  img.Image dst,
  double cx,
  double cy,
  double r, {
  required int thickness,
  required img.Color color,
}) {
  final steps = (r * 2 * math.pi * 2).round();
  for (var i = 0; i < steps; i++) {
    final angle = i / steps * 2 * math.pi;
    for (var k = 0; k < thickness; k++) {
      final ri = r - thickness ~/ 2 + k;
      _blendPixel(
        dst,
        (cx + ri * math.cos(angle)).round(),
        (cy + ri * math.sin(angle)).round(),
        color,
      );
    }
  }
}

void _drawLeaf(
  img.Image dst, {
  required double cx,
  required double cy,
  required double w,
  required double h,
  required double tilt,
  required img.Color color,
}) {
  final hw = w / 2;
  final hh = h / 2;
  for (var py = (cy - hh).floor(); py <= (cy + hh).ceil(); py++) {
    for (var px = (cx - hw).floor(); px <= (cx + hw).ceil(); px++) {
      final dx = (px - cx).toDouble();
      final dy = (py - cy).toDouble();
      final lx = dx * math.cos(-tilt) + dy * math.sin(-tilt);
      final ly = -dx * math.sin(-tilt) + dy * math.cos(-tilt);
      final nx = lx / hw;
      final ny = ly / hh;
      if (nx * nx + (ny - 1) * (ny - 1) < 1.02 &&
          nx * nx + (ny + 1) * (ny + 1) < 1.02) {
        _blendPixel(dst, px, py, color);
      }
    }
  }
}

void _drawDroplet(
  img.Image dst, {
  required double cx,
  required double cy,
  required double r,
  required double tipH,
  required img.Color color,
}) {
  final circleTopY = cy - r;
  final tipY = cy - r - tipH;
  for (var py = tipY.floor(); py <= (cy + r).ceil(); py++) {
    for (var px = (cx - r).floor(); px <= (cx + r).ceil(); px++) {
      if (py >= circleTopY) {
        final dx = (px - cx).toDouble();
        final dy = (py - cy).toDouble();
        if (dx * dx + dy * dy < r * r) {
          _blendPixel(dst, px, py, color);
        }
      } else {
        final progress = (py - tipY) / (circleTopY - tipY);
        if ((px - cx).abs() < r * progress) {
          _blendPixel(dst, px, py, color);
        }
      }
    }
  }
}

void _blendPixel(img.Image dst, int x, int y, img.Color src) {
  if (x < 0 || y < 0 || x >= dst.width || y >= dst.height) {
    return;
  }
  final bg = dst.getPixel(x, y);
  final sa = src.a.toInt() / 255.0;
  final da = bg.a.toInt() / 255.0;
  final oa = sa + da * (1 - sa);
  if (oa == 0) {
    return;
  }
  final rv = ((src.r.toInt() * sa + bg.r.toInt() * da * (1 - sa)) / oa)
      .round()
      .clamp(0, 255);
  final gv = ((src.g.toInt() * sa + bg.g.toInt() * da * (1 - sa)) / oa)
      .round()
      .clamp(0, 255);
  final bv = ((src.b.toInt() * sa + bg.b.toInt() * da * (1 - sa)) / oa)
      .round()
      .clamp(0, 255);
  dst.setPixelRgba(x, y, rv, gv, bv, (oa * 255).round().clamp(0, 255));
}
