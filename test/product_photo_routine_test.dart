import 'package:aesthetic_skin_tracker/screens/home_screen.dart';
import 'package:aesthetic_skin_tracker/screens/product_photo_routine_screen.dart';
import 'package:aesthetic_skin_tracker/screens/routines_screen.dart';
import 'package:aesthetic_skin_tracker/services/ai_llm_service.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:aesthetic_skin_tracker/utils/product_routine_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _aiReply = '''Products:
- CeraVe Hydrating Cleanser
- La Roche-Posay Anthelios SPF 50
- The Ordinary Retinol 0.5%

Morning routine:
1. CeraVe Hydrating Cleanser - gentle cleanse
2. La Roche-Posay Anthelios SPF 50 - sun protection

Evening routine:
1. CeraVe Hydrating Cleanser - remove the day
2. The Ordinary Retinol 0.5% - renewal
''';

Widget _screen({
  ProductPhotoReader? readPhoto,
  ProductPhotoPicker? pickPhoto,
}) => MaterialApp(
  home: ProductPhotoRoutineScreen(
    pickPhoto: pickPhoto ?? (_) async => XFile('shelf.jpg'),
    readPhoto: readPhoto ?? (_) async => _aiReply,
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('product routine builder', () {
    test('reads products and morning / evening steps from an AI reply', () {
      expect(extractDetectedProducts(_aiReply), [
        'CeraVe Hydrating Cleanser',
        'La Roche-Posay Anthelios SPF 50',
        'The Ordinary Retinol 0.5%',
      ]);
      final steps = extractAmPmRoutineSteps(_aiReply);
      expect(steps.morning, [
        'CeraVe Hydrating Cleanser - gentle cleanse',
        'La Roche-Posay Anthelios SPF 50 - sun protection',
      ]);
      expect(steps.evening, [
        'CeraVe Hydrating Cleanser - remove the day',
        'The Ordinary Retinol 0.5% - renewal',
      ]);
    });

    test('typed product names split into morning and night', () {
      final steps = buildAmPmStepsFromProductNames([
        'Gentle cleanser',
        'Retinol serum',
        'SPF 50 sunscreen',
        'Night cream',
        '  ',
      ]);
      expect(steps.morning, ['Gentle cleanser', 'SPF 50 sunscreen']);
      expect(steps.evening, ['Retinol serum', 'Night cream']);
    });

    test('night rule matches the home screen product classification', () {
      expect(isNightRoutineProduct(name: 'Clay mask'), isTrue);
      expect(
        isNightRoutineProduct(name: 'Serum', purpose: 'treatment'),
        isTrue,
      );
      expect(
        isNightRoutineProduct(name: 'Fluid', purpose: 'sunscreen treatment'),
        isFalse,
      );
      expect(
        isNightRoutineProduct(name: 'Toner', purpose: 'hydration'),
        isFalse,
      );
    });
  });

  testWidgets('photo -> AI routine is shown and saved for Routines', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_screen());
    await tester.tap(find.byKey(const ValueKey('product_photo_pick_button')));
    await tester.pumpAndSettle();

    expect(find.text('• The Ordinary Retinol 0.5%'), findsOneWidget);
    expect(
      find.text('1. CeraVe Hydrating Cleanser - gentle cleanse'),
      findsOneWidget,
    );
    expect(find.text('2. The Ordinary Retinol 0.5% - renewal'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('product_routine_save_button')),
    );
    await tester.tap(find.byKey(const ValueKey('product_routine_save_button')));
    await tester.pumpAndSettle();

    final saved = await AppPrefs.getActiveAiRoutine();
    expect(saved, isNotNull);
    expect(saved!['source'], 'product_photo');
    expect(saved['morningSteps'], hasLength(2));
    expect(saved['eveningSteps'], [
      'CeraVe Hydrating Cleanser - remove the day',
      'The Ordinary Retinol 0.5% - renewal',
    ]);
    expect(saved['detectedProducts'], hasLength(3));

    await tester.pumpWidget(const MaterialApp(home: RoutinesScreen()));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('The Ordinary Retinol 0.5% - renewal'),
      findsOneWidget,
    );
  });

  testWidgets(
    'without AI photo reading, typed products still build a routine',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _screen(
          readPhoto: (_) async => throw const AiLlmConfigurationException(
            'GEMINI_API_KEY not configured.',
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('product_photo_pick_button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('product_photo_message')),
        findsOneWidget,
      );
      expect(find.textContaining("isn't set up"), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('product_list_field')),
        'Gentle cleanser\nRetinol serum',
      );
      await tester.tap(find.byKey(const ValueKey('product_list_build_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('product_routine_save_button')),
      );
      await tester.tap(
        find.byKey(const ValueKey('product_routine_save_button')),
      );
      await tester.pumpAndSettle();

      final saved = await AppPrefs.getActiveAiRoutine();
      expect(saved!['source'], 'product_list');
      expect(saved['morningSteps'], ['Gentle cleanser']);
      expect(saved['eveningSteps'], ['Retinol serum']);
    },
  );

  testWidgets('home has the product-photo entry and it opens the flow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    final entry = find.byKey(
      const ValueKey('home_product_photo_routine_button'),
    );
    expect(entry, findsOneWidget);
    expect(find.text('Photo products for AI routine'), findsOneWidget);

    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(ProductPhotoRoutineScreen), findsOneWidget);
  });
}
