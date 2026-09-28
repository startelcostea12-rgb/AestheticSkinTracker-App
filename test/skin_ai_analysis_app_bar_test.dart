import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
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
}
