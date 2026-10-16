import 'dart:io';
import 'dart:typed_data';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:aesthetic_skin_tracker/utils/gray_card_region.dart';
import 'package:aesthetic_skin_tracker/utils/skin_analysis_service.dart';
import 'package:aesthetic_skin_tracker/widgets/gray_card_mark_dialog.dart';
import 'package:aesthetic_skin_tracker/widgets/image_crop_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 400 x 300 still, gray background, a magenta "card" at px (170..230,
/// 260..290) -- entirely below the face square (px 100..300 x 50..250).
Uint8List _still() {
  final image = img.Image(width: 400, height: 300);
  img.fill(image, color: img.ColorRgb8(120, 120, 120));
  img.fillRect(
    image,
    x1: 170,
    y1: 260,
    x2: 229,
    y2: 289,
    color: img.ColorRgb8(255, 0, 255),
  );
  return Uint8List.fromList(img.encodePng(image));
}

const _crop = NormalizedSquareCrop(left: 0.25, top: 50 / 300, size: 2 / 3);
const _cardBelowFace = (x: 170 / 400, y: 260 / 300, w: 60 / 400, h: 30 / 300);

void main() {
  group('grayCardPatchFromStill', () {
    test('cuts the card even when it lies below the face square', () {
      final patch = img.decodeImage(
        grayCardPatchFromStill(_still(), _cardBelowFace)!,
      )!;
      expect((patch.width, patch.height), (60, 30));
      for (final (x, y) in const [(0, 0), (30, 15), (59, 29)]) {
        final p = patch.getPixel(x, y);
        expect((p.r, p.g, p.b), (255, 0, 255), reason: '($x, $y)');
      }
    });

    test('a box with no pixels or an undecodable still gives null', () {
      expect(
        grayCardPatchFromStill(_still(), (x: 0.5, y: 0.5, w: 0.0, h: 0.1)),
        isNull,
      );
      expect(
        grayCardPatchFromStill(Uint8List.fromList([1, 2, 3]), _cardBelowFace),
        isNull,
      );
    });
  });

  group('GrayCardMarkDialog', () {
    Future<void> open(
      WidgetTester tester,
      void Function(GrayCardRegion?) onResult,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                onResult(
                  await showDialog<GrayCardRegion>(
                    context: context,
                    builder: (_) => GrayCardMarkDialog(
                      imageBytes: _still(),
                      stillWidth: 400,
                      stillHeight: 300,
                      uploadCrop: _crop,
                    ),
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
    }

    testWidgets('a box drawn entirely below the face square is accepted', (
      tester,
    ) async {
      GrayCardRegion? result;
      await open(tester, (r) => result = r);
      final rect = tester.getRect(
        find.byKey(const ValueKey('gray_card_mark_area')),
      );
      Offset at(double px, double py) =>
          rect.topLeft + Offset(rect.width * px / 400, rect.height * py / 300);

      final gesture = await tester.startGesture(at(172, 262));
      await gesture.moveTo(at(200, 275));
      await gesture.moveTo(at(228, 288));
      await gesture.up();
      await tester.pump();

      final use = tester.widget<FilledButton>(
        find.byKey(const ValueKey('gray_card_use')),
      );
      expect(use.onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('gray_card_use')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      // Fractions of the full still, not clipped to the face square.
      expect(result!.y, greaterThan(250 / 300));
      expect(result!.y + result!.h, lessThanOrEqualTo(1.0));
      expect(result!.x, closeTo(172 / 400, 0.01));
      expect(result!.w, closeTo(56 / 400, 0.01));
      final patch = img.decodeImage(
        grayCardPatchFromStill(_still(), result!)!,
      )!;
      final center = patch.getPixel(patch.width ~/ 2, patch.height ~/ 2);
      expect((center.r, center.g, center.b), (255, 0, 255));
    });

    testWidgets('tap places a box; Skip returns nothing', (tester) async {
      GrayCardRegion? result = (x: -1, y: -1, w: -1, h: -1);
      await open(tester, (r) => result = r);
      final rect = tester.getRect(
        find.byKey(const ValueKey('gray_card_mark_area')),
      );
      await tester.tapAt(
        rect.topLeft + Offset(rect.width * 0.05, rect.height * 0.05),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('gray_card_box')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('gray_card_skip')));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });

  group('upload', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<String> bodyOf({Uint8List? patch}) async {
      late String body;
      final client = MockClient.streaming((request, stream) async {
        body = String.fromCharCodes(await stream.toBytes());
        return http.StreamedResponse(
          Stream.value('{"status":"success"}'.codeUnits),
          200,
        );
      });
      await SkinAnalysisService.uploadSingleImageFile(
        image: XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'f.jpg'),
        uri: Uri.parse('https://example.test/api/skin/analyze-single'),
        grayCardPatch: patch,
        allowBackend: true,
        httpClient: client,
      );
      return body;
    }

    test('a marked card uploads its patch beside the frame', () async {
      final body = await bodyOf(patch: Uint8List.fromList([9, 9, 9]));
      expect(body, contains('name="gray_card_image"'));
      expect(body, contains('filename="gray_card.png"'));
    });

    test('an unmarked scan sends no patch', () async {
      expect(await bodyOf(), isNot(contains('gray_card_image')));
    });
  });

  group('wiring', () {
    test('camera marking is opt-in and returns per-frame patches', () {
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
      expect(source, contains('grayCardPatchFromStill('));
      expect(source, contains('grayCardPatches: grayCardPatches,'));
      expect(source, isNot(contains('grayCardRegionInUploadedFrame')));
    });

    test('AI scan sends each frame its patch and clears it otherwise', () {
      final source = File(
        'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
      ).readAsStringSync();
      expect(source, contains('_grayCardPatches = captured.grayCardPatches;'));
      expect(source, contains('? _grayCardPatches[frameNumber - 1]'));
      // One reset per place the region is cleared, plus the declaration.
      expect(
        '_grayCardPatches = const [];'.allMatches(source).length,
        '_grayCardRegion = null;'.allMatches(source).length + 1,
      );
    });
  });
}
