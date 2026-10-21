import 'dart:io';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/widgets/consistent_setup_guide.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A button standing in for "start a Front scan".
Future<List<String>> _pumpStartButton(
  WidgetTester tester, {
  double width = 375,
}) async {
  final started = <String>[];
  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                await showConsistentSetupGuideIfFirstTime(context);
                started.add('camera');
              },
              child: const Text('Start scan'),
            ),
          ),
        ),
      ),
    ),
  );
  return started;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('five points', () {
    expect(consistentSetupPoints, hasLength(5));
    expect(consistentSetupPoints.first.text, contains('gray card'));
  });

  testWidgets('first scan shows the guide; Got it closes it and the scan '
      'continues', (tester) async {
    final started = await _pumpStartButton(tester);
    await tester.tap(find.text('Start scan'));
    await tester.pumpAndSettle();
    expect(find.text(consistentSetupGuideTitle), findsOneWidget);
    for (final point in consistentSetupPoints) {
      expect(find.text(point.text), findsOneWidget, reason: point.text);
    }
    expect(started, isEmpty, reason: 'waits for Got it');
    await tester.tap(
      find.byKey(const ValueKey('consistent_setup_guide_got_it')),
    );
    await tester.pumpAndSettle();
    expect(find.text(consistentSetupGuideTitle), findsNothing);
    expect(started, ['camera']);
    expect(await shouldShowConsistentSetupGuide(), isFalse);
  });

  testWidgets('later scans do not show it again', (tester) async {
    await markConsistentSetupGuideSeen();
    final started = await _pumpStartButton(tester);
    await tester.tap(find.text('Start scan'));
    await tester.pumpAndSettle();
    expect(find.text(consistentSetupGuideTitle), findsNothing);
    expect(started, ['camera']);
  });

  testWidgets('fits at 320px', (tester) async {
    await _pumpStartButton(tester, width: 320);
    await tester.tap(find.text('Start scan'));
    await tester.pumpAndSettle();
    expect(find.text(consistentSetupGuideTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the ⋮ menu reopens it anytime', (tester) async {
    await markConsistentSetupGuideSeen();
    await tester.binding.setSurfaceSize(const Size(375, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: SkinAiAnalysisScreen()));
    await tester.pump();
    await tester.tap(find.byTooltip('Debug exports'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Setup Guide'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(consistentSetupGuideTitle), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('consistent_setup_guide_got_it')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(consistentSetupGuideTitle), findsNothing);
  });

  test('a face scan from the camera shows it first, after the free-scan '
      'check', () {
    final source = File(
      'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> _pickFromCamera() async {');
    final body = source.substring(start, start + 600);
    expect(
      body.indexOf('openPaywallIfFreeScanCapReached'),
      lessThan(body.indexOf('showConsistentSetupGuideIfFirstTime(context)')),
    );
    expect(body, contains('if (!_isBodyProcedure) {'));
  });
}
