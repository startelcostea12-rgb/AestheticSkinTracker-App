import 'dart:typed_data';

import 'package:aesthetic_skin_tracker/widgets/image_crop_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _quadrantImage(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, x < width ~/ 2 ? 230 : 20, y < height ~/ 2 ? 230 : 20, 20);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  test('normalized crop applies the same relative square to different frames', () {
    const region = NormalizedSquareCrop(left: 0.25, top: 0.25, size: 0.5);

    final first = img.decodeImage(
      applyNormalizedSquareCrop(_quadrantImage(100, 80), region),
    );
    final second = img.decodeImage(
      applyNormalizedSquareCrop(_quadrantImage(200, 160), region),
    );

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(first!.width, 40);
    expect(first.height, 40);
    expect(second!.width, 80);
    expect(second.height, 80);
  });
}