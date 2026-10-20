import 'dart:convert';

import 'package:aesthetic_skin_tracker/screens/product_lookup_detail_screen.dart';
import 'package:aesthetic_skin_tracker/screens/product_lookup_screen.dart';
import 'package:aesthetic_skin_tracker/screens/routines_screen.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:aesthetic_skin_tracker/utils/barcode_reader.dart';
import 'package:aesthetic_skin_tracker/utils/product_lookup.dart';
import 'package:aesthetic_skin_tracker/utils/skincare_style_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _routine() => <String, dynamic>{
  'id': 'r1',
  'source': 'manual',
  'generatedAt': '2026-10-01T09:00:00.000',
  'morningSteps': ['Cleanser'],
  'eveningSteps': ['Night cream'],
  'detectedProducts': <String>[],
  'notes': 'patch tested',
};

Future<void> _pumpLookup(
  WidgetTester tester, {
  Future<BarcodeReadResult> Function()? readBarcode,
}) async {
  await tester.binding.setSurfaceSize(const Size(375, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: readBarcode == null
          ? const ProductLookupScreen()
          : ProductLookupScreen(readBarcode: readBarcode),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('catalog and search', () {
    test('covers every curated style product once, each with a brand', () {
      final styleCount = skincareStyleCatalog.values.fold<int>(
        0,
        (sum, list) => sum + list.length,
      );
      expect(localProductCatalog, hasLength(styleCount));
      for (final product in localProductCatalog) {
        expect(product.brand, isNotNull, reason: product.name);
        // No ingredient data is invented for the local catalog.
        expect(product.hasIngredients, isFalse, reason: product.name);
      }
    });

    test('search returns a product by name, brand or partial words', () {
      expect(
        searchProducts('snail mucin').map((p) => p.name),
        contains('COSRX Advanced Snail 96 Mucin Power Essence'),
      );
      expect(
        searchProducts('cerave').map((p) => p.name),
        containsAll(['CeraVe Moisturizing Cream', 'CeraVe Hydrating Cleanser']),
      );
      // Straight apostrophe finds the curly one in the catalog.
      expect(searchProducts("paula's bha"), hasLength(1));
      expect(searchProducts('   '), isEmpty);
      expect(searchProducts('zzz-not-a-product'), isEmpty);
    });

    test('barcode lookup reports not found for the local catalog', () {
      expect(productForBarcode('0123456789012'), isNull);
      expect(productForBarcode(''), isNull);
      const custom = LookupProduct(name: 'X', barcode: '111');
      expect(productForBarcode('111', catalog: const [custom]), same(custom));
    });
  });

  group('saved and routine', () {
    test('save for later is stored once and can be removed', () async {
      await saveProductForLater('CeraVe Moisturizing Cream');
      await saveProductForLater('CeraVe Moisturizing Cream');
      expect(await loadSavedProducts(), ['CeraVe Moisturizing Cream']);
      await removeSavedProduct('CeraVe Moisturizing Cream');
      expect(await loadSavedProducts(), isEmpty);
    });

    test('add to routine appends and keeps every other field', () async {
      expect(
        await addProductToActiveRoutine('Serum', RoutinePeriod.morning),
        isFalse,
        reason: 'no routine yet',
      );
      await AppPrefs.saveActiveAiRoutine(_routine());
      expect(
        await addProductToActiveRoutine('Serum', RoutinePeriod.morning),
        isTrue,
      );
      expect(
        await addProductToActiveRoutine('Serum', RoutinePeriod.morning),
        isFalse,
        reason: 'already there',
      );
      final saved = (await AppPrefs.getActiveAiRoutine())!;
      expect(saved['morningSteps'], ['Cleanser', 'Serum']);
      expect(saved['eveningSteps'], ['Night cream']);
      for (final key in ['id', 'source', 'generatedAt', 'notes']) {
        expect(saved[key], _routine()[key], reason: key);
      }
    });
  });

  group('screens', () {
    testWidgets('search shows results and opens the detail screen', (
      tester,
    ) async {
      await _pumpLookup(tester);
      await tester.enterText(
        find.byKey(const ValueKey('product_search_field')),
        'vanicream',
      );
      await tester.pumpAndSettle();
      expect(find.text('Vanicream Moisturizing Cream'), findsOneWidget);
      await tester.tap(find.text('Vanicream Moisturizing Cream'));
      await tester.pumpAndSettle();
      expect(find.byType(ProductLookupDetailScreen), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('product_detail_name')))
            .data,
        'Vanicream Moisturizing Cream',
      );
      expect(find.text('Brand: Vanicream'), findsOneWidget);
    });

    testWidgets('no matches says so', (tester) async {
      await _pumpLookup(tester);
      await tester.enterText(
        find.byKey(const ValueKey('product_search_field')),
        'zzz',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('product_search_empty')),
        findsOneWidget,
      );
    });

    testWidgets('barcode path: a decoded code not in the list shows not '
        'found', (tester) async {
      var calls = 0;
      await _pumpLookup(
        tester,
        readBarcode: () async {
          calls++;
          return const BarcodeReadResult(
            BarcodeReadStatus.found,
            '3337875597197',
          );
        },
      );
      await tester.tap(
        find.byKey(const ValueKey('product_scan_barcode_button')),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      final message = tester
          .widget<Text>(find.byKey(const ValueKey('product_barcode_message')))
          .data!;
      expect(message, contains('Product not found for barcode 3337875597197'));
      expect(find.byType(ProductLookupDetailScreen), findsNothing);
    });

    testWidgets('barcode path: no barcode, unsupported and cancel', (
      tester,
    ) async {
      var next = BarcodeReadStatus.noBarcode;
      await _pumpLookup(
        tester,
        readBarcode: () async => BarcodeReadResult(next),
      );
      final button = find.byKey(const ValueKey('product_scan_barcode_button'));
      final message = find.byKey(const ValueKey('product_barcode_message'));

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(message).data,
        contains('No barcode was found'),
      );

      next = BarcodeReadStatus.unsupported;
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(message).data, contains('isn’t available'));

      // Cancelling leaves the screen as it was.
      next = BarcodeReadStatus.cancelled;
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(message).data, contains('isn’t available'));
    });

    testWidgets('detail shows the name and the no-ingredient note without '
        'crashing; only Save for later without a routine', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: ProductLookupDetailScreen(
            product: LookupProduct(name: 'Mystery Balm'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Mystery Balm'), findsOneWidget);
      expect(find.text('Brand not listed'), findsOneWidget);
      expect(
        find.text(ProductLookupDetailScreen.noIngredientsText),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('product_add_to_routine')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('product_save_for_later')));
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsOneWidget);
      expect(await loadSavedProducts(), ['Mystery Balm']);
    });

    testWidgets('detail lists ingredients when the source has them', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ProductLookupDetailScreen(
            product: LookupProduct(
              name: 'Test Serum',
              brand: 'Lab',
              ingredients: ['Niacinamide', 'Glycerin'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('• Niacinamide'), findsOneWidget);
      expect(find.text('• Glycerin'), findsOneWidget);
      expect(
        find.text(ProductLookupDetailScreen.noIngredientsText),
        findsNothing,
      );
    });

    testWidgets('add to routine from the detail screen', (tester) async {
      SharedPreferences.setMockInitialValues({
        AppPrefs.activeAiRoutineKey: jsonEncode(_routine()),
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: ProductLookupDetailScreen(
            product: LookupProduct(name: 'CeraVe Hydrating Cleanser'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('product_add_to_routine')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('product_add_evening')));
      await tester.pumpAndSettle();
      expect(find.text('Added to your evening routine.'), findsOneWidget);
      final saved = (await AppPrefs.getActiveAiRoutine())!;
      expect(saved['eveningSteps'], [
        'Night cream',
        'CeraVe Hydrating Cleanser',
      ]);
      expect(saved['morningSteps'], ['Cleanser']);
    });

    testWidgets('saved products are listed on the lookup screen', (
      tester,
    ) async {
      await saveProductForLater('Cetaphil Gentle Skin Cleanser');
      await _pumpLookup(tester);
      expect(find.text('Saved for later'), findsOneWidget);
      expect(find.text('Cetaphil Gentle Skin Cleanser'), findsOneWidget);
    });

    testWidgets('routines screen opens the lookup', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RoutinesScreen()));
      await tester.pumpAndSettle();
      final entry = find.byKey(
        const ValueKey('routines_product_lookup_button'),
      );
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(ProductLookupScreen), findsOneWidget);
    });
  });
}
