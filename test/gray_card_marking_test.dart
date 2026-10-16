import 'dart:io';
import 'dart:typed_data';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:aesthetic_skin_tracker/utils/gray_card_region.dart';
import 'package:aesthetic_skin_tracker/widgets/gray_card_mark_dialog.dart';
import 'package:aesthetic_skin_tracker/widgets/image_crop_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 400 x 300 still, gray background, a magenta "card" at px (220..260,
/// 120..160).
Uint8List _still() {
  final image = img.Image(width: 400, height: 300);
  img.fill(image, color: img.ColorRgb8(120, 120, 120));
  img.fillRect(
    image,
    x1: 220,
    y1: 120,
    x2: 259,
    y2: 159,
    color: img.ColorRgb8(255, 0, 255),
  );
  return Uint8List.fromList(img.encodePng(image));
}

const _cardInStill = (x: 220 / 400, y: 120 / 300, w: 40 / 400, h: 40 / 300);

// Square crop of 200 px at (100, 50): left = 100/400, top = 50/300,
// size = 200/300.
const _crop = NormalizedSquareCrop(left: 0.25, top: 50 / 300, size: 2 / 3);

void main() {
  group('grayCardRegionInUploadedFrame', () {
    test('maps a box inside the crop into crop fractions', () {
      final region = grayCardRegionInUploadedFrame(
        stillBox: _cardInStill,
        stillWidth: 400,
        stillHeight: 300,
        crop: _crop,
      )!;
      expect(region.x, closeTo(120 / 200, 1e-9));
      expect(region.y, closeTo(70 / 200, 1e-9));
      expect(region.w, closeTo(40 / 200, 1e-9));
      expect(region.h, closeTo(40 / 200, 1e-9));
    });

    test('lands on the card in the actually cropped (uploaded) frame', () {
      final cropped = img.decodeImage(
        applyNormalizedSquareCrop(_still(), _crop),
      )!;
      final region = grayCardRegionInUploadedFrame(
        stillBox: _cardInStill,
        stillWidth: 400,
        stillHeight: 300,
        crop: _crop,
      )!;
      final cx = ((region.x + region.w / 2) * cropped.width).floor();
      final cy = ((region.y + region.h / 2) * cropped.height).floor();
      final pixel = cropped.getPixel(cx, cy);
      expect(pixel.r, greaterThan(200));
      expect(pixel.g, lessThan(60));
      expect(pixel.b, greaterThan(200));
    });

    test('keeps only the part of the box inside the crop', () {
      final region = grayCardRegionInUploadedFrame(
        stillBox: (x: 280 / 400, y: 100 / 300, w: 40 / 400, h: 40 / 300),
        stillWidth: 400,
        stillHeight: 300,
        crop: _crop,
      )!;
      // Crop spans px 100..300 horizontally: 20 of the 40 px remain.
      expect(region.x, closeTo(180 / 200, 1e-9));
      expect(region.w, closeTo(20 / 200, 1e-9));
    });

    test('a box outside the uploaded crop gives null (nothing sent)', () {
      expect(
        grayCardRegionInUploadedFrame(
          stillBox: (x: 0.0, y: 0.0, w: 0.1, h: 0.1),
          stillWidth: 400,
          stillHeight: 300,
          crop: _crop,
        ),
        isNull,
      );
      expect(
        grayCardRegionInUploadedFrame(
          stillBox: (x: 0.5, y: 0.5, w: 0.0, h: 0.1),
          stillWidth: 400,
          stillHeight: 300,
          crop: _crop,
        ),
        isNull,
      );
    });
  });

  group('GrayCardMarkDialog', () {
    testWidgets('tap places a box on the card and returns still fractions', (
      tester,
    ) async {
      GrayCardRegion? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<GrayCardRegion>(
                  context: context,
                  builder: (_) => GrayCardMarkDialog(
                    imageBytes: _still(),
                    stillWidth: 400,
                    stillHeight: 300,
                    uploadCrop: _crop,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final area = find.byKey(const ValueKey('gray_card_mark_area'));
      final rect = tester.getRect(area);
      // Center of the card: (240, 140) px of 400 x 300.
      await tester.tapAt(
        rect.topLeft + Offset(rect.width * 0.6, rect.height * 140 / 300),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('gray_card_box')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('gray_card_use')));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      // 12% of the shorter side (300 px) = 36 px box centered on the tap.
      expect(result!.w, closeTo(36 / 400, 1e-6));
      expect(result!.h, closeTo(36 / 300, 1e-6));
      expect(result!.x + result!.w / 2, closeTo(0.6, 0.01));
      expect(result!.y + result!.h / 2, closeTo(140 / 300, 0.01));
      final uploaded = grayCardRegionInUploadedFrame(
        stillBox: result!,
        stillWidth: 400,
        stillHeight: 300,
        crop: _crop,
      );
      expect(uploaded, isNotNull);
    });

    testWidgets('drag draws a box; outside the crop it cannot be used', (
      tester,
    ) async {
      GrayCardRegion? result = (x: -1, y: -1, w: -1, h: -1);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<GrayCardRegion>(
                  context: context,
                  builder: (_) => GrayCardMarkDialog(
                    imageBytes: _still(),
                    stillWidth: 400,
                    stillHeight: 300,
                    uploadCrop: _crop,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final rect = tester.getRect(
        find.byKey(const ValueKey('gray_card_mark_area')),
      );

      // Top-left corner: outside the upload square (x 100..300 px).
      final gesture = await tester.startGesture(
        rect.topLeft + Offset(rect.width * 0.02, rect.height * 0.02),
      );
      await gesture.moveBy(Offset(rect.width * 0.05, rect.height * 0.05));
      await gesture.moveBy(Offset(rect.width * 0.05, rect.height * 0.05));
      await gesture.up();
      await tester.pump();
      expect(find.byKey(const ValueKey('gray_card_box')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('gray_card_outside_note')),
        findsOneWidget,
      );
      final use = tester.widget<FilledButton>(
        find.byKey(const ValueKey('gray_card_use')),
      );
      expect(use.onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('gray_card_skip')));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });

  group('wiring', () {
    test('camera marking is opt-in and off by default', () {
      expect(const CameraScreen().markGrayCardAfterCapture, isFalse);
      final source = File(
        'lib/features/skin_tracker/presentation/screens/camera_screen.dart',
      ).readAsStringSync();
      final dialog = source.indexOf('GrayCardMarkDialog(');
      final guard = source.lastIndexOf(
        'if (widget.markGrayCardAfterCapture &&',
        dialog,
      );
      expect(guard, isNonNegative);
      expect(dialog - guard, lessThan(400));
      expect(source, contains('grayCardRegion: grayCardRegion,'));
    });

    test('AI scan sends the marked region and clears it otherwise', () {
      final source = File(
        'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
      ).readAsStringSync();
      expect(source, contains('bool _markGrayCard = false;'));
      expect(source, contains('markGrayCardAfterCapture: _markGrayCard,'));
      expect(source, contains('_grayCardRegion = captured.grayCardRegion;'));
      expect(source, contains('grayCardRegion: _grayCardRegion,'));
      expect(
        '_grayCardRegion = null;'.allMatches(source).length,
        '_capturedGuideType = null;'.allMatches(source).length,
      );
    });
  });
}
