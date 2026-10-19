import 'dart:io';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the hint text is shown and fits a 320-wide phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: BaselinePositionHint(),
          ),
        ),
      ),
    );
    expect(
      find.text(
        'Keep your chin at the same height and distance as the baseline.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test('the AI scan camera shows the hint without gating capture', () {
    final source = File(
      'lib/features/skin_tracker/presentation/screens/camera_screen.dart',
    ).readAsStringSync();
    final hint = source.indexOf('child: BaselinePositionHint(),');
    expect(hint, isNonNegative);
    expect(
      source.substring(hint - 200, hint),
      contains('if (_isAiSkinAnalysisFacialFlow)'),
    );
    // Text only: the capture-readiness gate never mentions the hint.
    expect(
      'BaselinePositionHint'.allMatches(source).length,
      3, // class, its constructor, and the one usage
    );
  });
}
