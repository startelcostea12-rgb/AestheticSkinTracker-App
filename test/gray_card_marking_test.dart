import 'dart:io';
import 'dart:typed_data';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/utils/gray_card_region.dart';
import 'package:aesthetic_skin_tracker/utils/skin_analysis_service.dart';
import 'package:aesthetic_skin_tracker/widgets/gray_card_target_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

const double _previewAspect =
    300 / 340; // camera_screen _facePreviewAspectRatio

/// A 3:4 portrait still (600 x 800) with a magenta card placed exactly where
/// the fixed preview target maps to.
Uint8List _stillWithCardInTarget() {
  final still = img.Image(width: 600, height: 800);
  img.fill(still, color: img.ColorRgb8(120, 120, 120));
  final r = grayCardTargetInStill(
    stillWidth: 600,
    stillHeight: 800,
    previewAspect: _previewAspect,
  );
  img.fillRect(
    still,
    x1: (r.x * 600).round(),
    y1: (r.y * 800).round(),
    x2: ((r.x + r.w) * 600).round() - 1,
    y2: ((r.y + r.h) * 800).round() - 1,
    color: img.ColorRgb8(255, 0, 255),
  );
  return Uint8List.fromList(img.encodePng(still));
}

void main() {
  group('fixed under-chin target', () {
    test('sits below the face oval and is horizontally centred', () {
      const t = grayCardPreviewTarget;
      expect(t.y, greaterThan(0.66)); // face oval ends at 66% of the preview
      expect(t.y + t.h, lessThanOrEqualTo(1.0));
      expect(t.x + t.w / 2, closeTo(0.5, 1e-9)); // mirror-invariant
    });

    test('maps into the full still through the preview cover crop', () {
      // Portrait 3:4 still is taller than the 300:340 preview, so the
      // preview shows the full width and the centred 85% of the height.
      final r = grayCardTargetInStill(
        stillWidth: 600,
        stillHeight: 800,
        previewAspect: _previewAspect,
      );
      const visibleH = (600 / 800) / _previewAspect;
      expect(r.x, closeTo(0.32, 1e-9));
      expect(r.w, closeTo(0.36, 1e-9));
      expect(r.y, closeTo((1 - visibleH) / 2 + 0.70 * visibleH, 1e-9));
      expect(r.h, closeTo(0.15 * visibleH, 1e-9));

      // A landscape still is wider: full height, centred width window.
      final l = grayCardTargetInStill(
        stillWidth: 1600,
        stillHeight: 900,
        previewAspect: _previewAspect,
      );
      const visibleW = _previewAspect / (1600 / 900);
      expect(l.y, closeTo(0.70, 1e-9));
      expect(l.x + l.w / 2, closeTo(0.5, 1e-9));
      expect(l.w, closeTo(0.36 * visibleW, 1e-9));
    });

    test('the patch cut at capture is the card in the target', () {
      final region = grayCardTargetInStill(
        stillWidth: 600,
        stillHeight: 800,
        previewAspect: _previewAspect,
      );
      final patch = img.decodeImage(
        grayCardPatchFromStill(_stillWithCardInTarget(), region)!,
      )!;
      for (final (x, y) in [
        (1, 1),
        (patch.width ~/ 2, patch.height ~/ 2),
        (patch.width - 2, patch.height - 2),
      ]) {
        final p = patch.getPixel(x, y);
        expect((p.r, p.g, p.b), (255, 0, 255), reason: '($x, $y)');
      }
    });

    test('undecodable still or empty box gives no patch', () {
      expect(
        grayCardPatchFromStill(
          Uint8List.fromList([1, 2, 3]),
          grayCardPreviewTarget,
        ),
        isNull,
      );
      expect(
        grayCardPatchFromStill(_stillWithCardInTarget(), (
          x: 0.5,
          y: 0.5,
          w: 0.0,
          h: 0.1,
        )),
        isNull,
      );
    });

    testWidgets('the overlay draws the labelled target under the face', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 340,
                child: Stack(children: [GrayCardTargetOverlay()]),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Place gray card here'), findsOneWidget);
      final stack = tester.getRect(find.byType(Stack).first);
      final target = tester.getRect(
        find.byKey(const ValueKey('gray_card_target')),
      );
      expect(target.top - stack.top, closeTo(0.70 * 340, 0.5));
      expect(target.left - stack.left, closeTo(0.32 * 300, 0.5));
      expect(target.height, closeTo(0.15 * 340, 0.5));
      expect(target.center.dx - stack.left, closeTo(150, 0.5));
    });
  });

  group('upload', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<String> bodyOf({
      Uint8List? patch,
      Map<String, String>? fields,
    }) async {
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
        fields: fields ?? const {},
        grayCardPatch: patch,
        allowBackend: true,
        httpClient: client,
      );
      return body;
    }

    test(
      'switch on: the target patch and region go with the frame, no drag',
      () async {
        final region = grayCardTargetInStill(
          stillWidth: 600,
          stillHeight: 800,
          previewAspect: _previewAspect,
        );
        final body = await bodyOf(
          patch: grayCardPatchFromStill(_stillWithCardInTarget(), region),
          fields: buildAiSkinAnalysisBackendFields(
            focusArea: 'Full face',
            grayCardRegion: region,
          ),
        );
        expect(body, contains('name="gray_card_image"'));
        expect(body, contains('name="gray_card_still_region"'));
      },
    );

    test('switch off: no gray-card region or patch is sent', () async {
      final body = await bodyOf(
        fields: buildAiSkinAnalysisBackendFields(focusArea: 'Full face'),
      );
      expect(body, isNot(contains('gray_card_image')));
      expect(body, isNot(contains('gray_card_still_region')));
      expect(body, isNot(contains('gray_card_region')));
    });
  });

  group('wiring', () {
    final camera = File(
      'lib/features/skin_tracker/presentation/screens/camera_screen.dart',
    ).readAsStringSync();

    test('no freehand drawing remains', () {
      expect(
        File('lib/widgets/gray_card_mark_dialog.dart').existsSync(),
        isFalse,
      );
      expect(camera, isNot(contains('GrayCardMarkDialog')));
      expect(camera, isNot(contains('showDialog<GrayCardRegion>')));
    });

    test('switch on: target shown on the face preview, sampled at capture', () {
      expect(const CameraScreen().markGrayCardAfterCapture, isFalse);
      expect(
        camera,
        contains(
          'if (widget.markGrayCardAfterCapture && !_isBodyGuide)\n'
          '                  const GrayCardTargetOverlay(),',
        ),
      );
      final capture = camera.indexOf('grayCardRegion = grayCardTargetInStill(');
      expect(capture, isNonNegative);
      expect(
        camera.substring(capture, capture + 200),
        contains('previewAspect: _facePreviewAspectRatio'),
      );
      expect(camera, contains('grayCardPatches: grayCardPatches,'));
    });

    test('AI scan sends each frame its patch and clears it otherwise', () {
      final source = File(
        'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
      ).readAsStringSync();
      expect(source, contains('markGrayCardAfterCapture: _markGrayCard,'));
      expect(source, contains('_grayCardPatches = captured.grayCardPatches;'));
      expect(source, contains('? _grayCardPatches[frameNumber - 1]'));
      expect(
        '_grayCardPatches = const [];'.allMatches(source).length,
        '_grayCardRegion = null;'.allMatches(source).length + 1,
      );
    });
  });
}
