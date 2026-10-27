import 'dart:io';
import 'dart:typed_data';

import 'package:aesthetic_skin_tracker/widgets/gray_card_sample_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

final Uint8List _patch = Uint8List.fromList(
  img.encodePng(
    img.Image(width: 40, height: 12)..clear(img.ColorRgb8(128, 128, 128)),
  ),
);

Future<void> _pump(WidgetTester tester, Map<String, dynamic> quality) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [GrayCardSampleCard(patch: _patch, imageQuality: quality)],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('used card: shows the sampled crop and offset', (tester) async {
    await _pump(tester, {
      'gray_card_marked': true,
      'gray_card_correction_applied': true,
      'gray_card_chroma_offset': 4.26,
    });
    expect(
      find.byKey(const ValueKey('gray_card_sample_image')),
      findsOneWidget,
    );
    expect(find.text('Gray card used'), findsOneWidget);
    expect(find.textContaining('not skin'), findsOneWidget);
    expect(find.text('Colour offset 4.3 (limit 12)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card rejected for disagreeing with the scene', (tester) async {
    await _pump(tester, {
      'gray_card_marked': true,
      'gray_card_correction_applied': false,
      'gray_card_reason': 'disagrees_with_scene',
      'gray_card_chroma_offset': 8.5,
    });
    expect(find.text('Gray card rejected'), findsOneWidget);
    expect(
      find.textContaining("didn't match the rest of the scene"),
      findsOneWidget,
    );
    expect(
      find.textContaining('Automatic colour balance was used'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('skin in the box: too colourful', (tester) async {
    await _pump(tester, {
      'gray_card_marked': true,
      'gray_card_correction_applied': false,
      'gray_card_reason': 'implausible_card_color',
      'gray_card_chroma_offset': 19.2,
    });
    expect(find.text('Gray card rejected'), findsOneWidget);
    expect(find.textContaining('often skin in the box'), findsOneWidget);
    expect(find.text('Colour offset 19.2 (limit 12)'), findsOneWidget);
  });

  testWidgets(
    'partial burst explains the card was not steady without claiming no card was used',
    (tester) async {
      await _pump(tester, {
        'gray_card_marked': true,
        'gray_card_status': 'partial',
        'gray_card_correction_applied': false,
        'gray_card_reason': 'implausible_card_color',
        'gray_card_message':
            'The gray card was not steady across the burst. Please retake with the card held steady.',
      });
      expect(find.text('Gray card partially used'), findsOneWidget);
      expect(
        find.textContaining('not steady across the burst'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Automatic colour balance was used'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final scenario in const [
    (status: 'partial', label: 'Gray card partially used'),
    (status: 'not_applied', label: 'Gray card not applied'),
    (status: 'rejected', label: 'Gray card rejected'),
  ]) {
    testWidgets(
      '${scenario.status} never displays fully used despite a stale flag',
      (tester) async {
        await _pump(tester, {
          'gray_card_marked': true,
          'gray_card_status': scenario.status,
          'gray_card_correction_applied': true,
        });
        expect(find.text(scenario.label), findsOneWidget);
        expect(find.text('Gray card used'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('every backend rejection reason has wording', () {
    for (final reason in [
      'disagrees_with_scene',
      'implausible_card_color',
      'implausible_exposure',
      'insufficient_region_pixels',
      'empty_region',
      'region_out_of_bounds',
    ]) {
      expect(grayCardIgnoredReasonText(reason), isNotNull, reason: reason);
    }
  });

  test('wiring: results show the first sampled patch for a marked scan', () {
    final screen = File(
      'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
    ).readAsStringSync();
    expect(screen, contains("quality['gray_card_marked'] != true"));
    expect(screen, contains('patch: _grayCardPatches.first'));
    expect(screen, contains('if (_grayCardSampleCard() case final card?)'));
  });
}
