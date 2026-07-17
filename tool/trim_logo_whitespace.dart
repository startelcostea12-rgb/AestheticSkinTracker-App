import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  const path = 'assets/images/logo_transparent.png';
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Logo not found: $path');
    exitCode = 1;
    return;
  }

  final bytes = file.readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    stderr.writeln('Failed to decode PNG: $path');
    exitCode = 1;
    return;
  }

  final crop = _alphaBoundsIgnoringSmallComponents(
    decoded,
    alphaThreshold: 10,
    minComponentPixels: 200,
  );
  if (crop == null) {
    stderr.writeln('Image appears fully transparent; skipping.');
    return;
  }

  final trimmed = img.copyCrop(
    decoded,
    x: crop.x,
    y: crop.y,
    width: crop.w,
    height: crop.h,
  );
  file.writeAsBytesSync(img.encodePng(trimmed, level: 9));
  stdout.writeln(
    'Trimmed $path: ${decoded.width}x${decoded.height} -> ${trimmed.width}x${trimmed.height}',
  );
}

_Rect? _alphaBoundsIgnoringSmallComponents(
  img.Image source, {
  required int alphaThreshold,
  required int minComponentPixels,
}) {
  final width = source.width;
  final height = source.height;
  final visited = List<bool>.filled(width * height, false);

  var unionMinX = width;
  var unionMinY = height;
  var unionMaxX = -1;
  var unionMaxY = -1;

  bool isOpaqueEnough(int x, int y) =>
      source.getPixel(x, y).a.toInt() > alphaThreshold;
  int idx(int x, int y) => y * width + x;

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final startIndex = idx(x, y);
      if (visited[startIndex] || !isOpaqueEnough(x, y)) {
        visited[startIndex] = true;
        continue;
      }

      final queueX = <int>[x];
      final queueY = <int>[y];
      visited[startIndex] = true;
      var head = 0;

      var count = 0;
      var minX = x;
      var minY = y;
      var maxX = x;
      var maxY = y;

      while (head < queueX.length) {
        final cx = queueX[head];
        final cy = queueY[head];
        head++;

        count++;
        if (cx < minX) minX = cx;
        if (cy < minY) minY = cy;
        if (cx > maxX) maxX = cx;
        if (cy > maxY) maxY = cy;

        for (var ny = cy - 1; ny <= cy + 1; ny++) {
          for (var nx = cx - 1; nx <= cx + 1; nx++) {
            if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
            final nIndex = idx(nx, ny);
            if (visited[nIndex]) continue;
            visited[nIndex] = true;
            if (!isOpaqueEnough(nx, ny)) continue;
            queueX.add(nx);
            queueY.add(ny);
          }
        }
      }

      if (count >= minComponentPixels) {
        if (minX < unionMinX) unionMinX = minX;
        if (minY < unionMinY) unionMinY = minY;
        if (maxX > unionMaxX) unionMaxX = maxX;
        if (maxY > unionMaxY) unionMaxY = maxY;
      }
    }
  }

  if (unionMaxX < unionMinX || unionMaxY < unionMinY) return null;
  return _Rect(
    unionMinX,
    unionMinY,
    unionMaxX - unionMinX + 1,
    unionMaxY - unionMinY + 1,
  );
}

class _Rect {
  const _Rect(this.x, this.y, this.w, this.h);
  final int x;
  final int y;
  final int w;
  final int h;
}
