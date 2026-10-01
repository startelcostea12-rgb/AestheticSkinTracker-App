import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final width in const <double>[320, 375, 390]) {
    testWidgets(
      'Skin Scan AppBar fits at ${width.toInt()}px and exposes debug exports',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          const MaterialApp(home: SkinAiAnalysisScreen()),
        );
        await tester.pump();

        expect(find.text('Skin Scan'), findsOneWidget);
        expect(find.byTooltip('Debug exports'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip('Debug exports'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text('Export Burst Log'), findsOneWidget);
        expect(find.text('Export Scan Data'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('face photo upload needs its own explicit acknowledgment', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({AppPrefs.aiCoachConsentKey: true});
    await tester.pumpWidget(const MaterialApp(home: SkinAiAnalysisScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final review = find.text('Review face photo upload');
    await tester.scrollUntilVisible(review, 300);
    await tester.drag(find.byType(ListView).first, const Offset(0, -200));
    await tester.pump();
    await tester.tap(review);
    await tester.pump();
    expect(find.text('Face photo upload'), findsOneWidget);
    expect(find.textContaining('leaves this phone'), findsOneWidget);
    expect(find.textContaining('analysis server'), findsWidgets);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.text('Photo upload acknowledged'), findsNothing);

    await tester.tap(review);
    await tester.pump();
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(find.text('Photo upload acknowledged'), findsNothing);

    await tester.tap(review);
    await tester.pump();
    await tester.tap(find.text('I Understand and Continue'));
    await tester.pump();
    expect(find.text('Photo upload acknowledged'), findsOneWidget);
  });
}
