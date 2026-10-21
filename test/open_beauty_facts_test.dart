import 'dart:async';
import 'dart:convert';

import 'package:aesthetic_skin_tracker/screens/product_lookup_detail_screen.dart';
import 'package:aesthetic_skin_tracker/screens/product_lookup_screen.dart';
import 'package:aesthetic_skin_tracker/utils/barcode_reader.dart';
import 'package:aesthetic_skin_tracker/utils/open_beauty_facts.dart';
import 'package:aesthetic_skin_tracker/utils/product_lookup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _barcode = '3337875597197';

final _obfProduct = <String, dynamic>{
  'code': _barcode,
  'product_name': 'Toleriane Sensitive Fluid',
  'brands': 'La Roche-Posay',
  'ingredients': [
    {'id': 'en:aqua', 'text': 'Aqua'},
    {'id': 'en:glycerin', 'text': 'Glycerin'},
    {'id': 'en:squalane', 'text': 'Squalane'},
  ],
};

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// A mock Open Beauty Facts that answers [_barcode] and a "toleriane"
/// search, 404s other barcodes, and returns no search results otherwise.
OpenBeautyFactsClient _mockClient({List<Uri>? requests}) =>
    OpenBeautyFactsClient(
      client: MockClient((request) async {
        requests?.add(request.url);
        final path = request.url.path;
        if (path.startsWith('/api/v2/product/')) {
          if (path.endsWith('/$_barcode.json')) {
            return _json({'status': 1, 'product': _obfProduct});
          }
          return _json({'status': 0, 'status_verbose': 'not found'}, 404);
        }
        if (path == '/cgi/search.pl') {
          final terms = request.url.queryParameters['search_terms'] ?? '';
          return _json({
            'count': 1,
            'products': [
              if (terms.toLowerCase().contains('toleriane')) _obfProduct,
            ],
          });
        }
        return http.Response('', 500);
      }),
    );

OpenBeautyFactsClient _offlineClient() => OpenBeautyFactsClient(
  client: MockClient((_) async => throw http.ClientException('offline')),
);

Future<void> _pumpLookup(
  WidgetTester tester,
  OpenBeautyFactsClient client, {
  Future<BarcodeReadResult> Function()? readBarcode,
}) async {
  await tester.binding.setSurfaceSize(const Size(375, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: ProductLookupScreen(
        client: client,
        readBarcode:
            readBarcode ??
            () async => const BarcodeReadResult(BarcodeReadStatus.cancelled),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _submitSearch(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byKey(const ValueKey('product_search_field')),
    text,
  );
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('client', () {
    test('barcode lookup maps name, brand, barcode and ingredients', () async {
      final requests = <Uri>[];
      final product = await _mockClient(
        requests: requests,
      ).productByBarcode(_barcode);
      expect(product!.name, 'Toleriane Sensitive Fluid');
      expect(product.brand, 'La Roche-Posay');
      expect(product.barcode, _barcode);
      expect(product.ingredients, ['Aqua', 'Glycerin', 'Squalane']);
      expect(product.source, LookupSource.openBeautyFacts);
      expect(requests.single.host, 'world.openbeautyfacts.org');
      expect(requests.single.path, '/api/v2/product/$_barcode.json');
    });

    test(
      'unknown barcode is null; non-numeric codes make no request',
      () async {
        final requests = <Uri>[];
        final client = _mockClient(requests: requests);
        expect(await client.productByBarcode('0000000000000'), isNull);
        expect(await client.productByBarcode('not-a-code'), isNull);
        expect(requests, hasLength(1));
      },
    );

    test('name search passes the terms and a result limit', () async {
      final requests = <Uri>[];
      final results = await _mockClient(
        requests: requests,
      ).searchByName('toleriane', limit: 5);
      expect(results.map((p) => p.name), ['Toleriane Sensitive Fluid']);
      final query = requests.single.queryParameters;
      expect(query['search_terms'], 'toleriane');
      expect(query['page_size'], '5');
    });

    test('failures throw OpenBeautyFactsUnavailable', () async {
      await expectLater(
        _offlineClient().productByBarcode(_barcode),
        throwsA(isA<OpenBeautyFactsUnavailable>()),
      );
      final serverError = OpenBeautyFactsClient(
        client: MockClient((_) async => http.Response('busy', 503)),
      );
      await expectLater(
        serverError.searchByName('x'),
        throwsA(isA<OpenBeautyFactsUnavailable>()),
      );
      final slow = OpenBeautyFactsClient(
        timeout: const Duration(milliseconds: 10),
        client: MockClient((_) => Completer<http.Response>().future),
      );
      await expectLater(
        slow.productByBarcode(_barcode),
        throwsA(isA<OpenBeautyFactsUnavailable>()),
      );
    });

    test('ingredients: text is split on top-level commas; none means null, '
        'never guessed', () {
      expect(
        ingredientsFromOpenBeautyFacts({
          'ingredients_text': 'Aqua, Parfum (Fragrance, Linalool), _Glycerin_.',
        }),
        ['Aqua', 'Parfum (Fragrance, Linalool)', 'Glycerin'],
      );
      expect(ingredientsFromOpenBeautyFacts({'ingredients_text': ' '}), isNull);
      expect(ingredientsFromOpenBeautyFacts(const {}), isNull);
      final unnamed = productFromOpenBeautyFacts(const {'code': '123456'});
      expect(unnamed, isNull, reason: 'search results need a name');
    });

    test('fallbacks: offline or no match uses the local catalog', () async {
      final offlineSearch = await lookupByName('cerave', _offlineClient());
      expect(offlineSearch.unreachable, isTrue);
      expect(
        offlineSearch.products.map((p) => p.name),
        contains('CeraVe Moisturizing Cream'),
      );
      expect(offlineSearch.fromOpenBeautyFacts, isFalse);

      final noMatch = await lookupByName('cerave', _mockClient());
      expect(noMatch.unreachable, isFalse);
      expect(noMatch.products, isNotEmpty);
      expect(noMatch.products.first.source, LookupSource.local);

      final offlineBarcode = await lookupBarcode(_barcode, _offlineClient());
      expect(offlineBarcode.unreachable, isTrue);
      expect(offlineBarcode.products, isEmpty);
    });
  });

  group('screens', () {
    testWidgets('barcode scan opens the Open Beauty Facts product with its '
        'ingredients', (tester) async {
      await _pumpLookup(
        tester,
        _mockClient(),
        readBarcode: () async =>
            const BarcodeReadResult(BarcodeReadStatus.found, _barcode),
      );
      await tester.tap(
        find.byKey(const ValueKey('product_scan_barcode_button')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProductLookupDetailScreen), findsOneWidget);
      expect(find.text('Toleriane Sensitive Fluid'), findsOneWidget);
      expect(find.text('Brand: La Roche-Posay'), findsOneWidget);
      expect(find.text('Barcode: $_barcode'), findsOneWidget);
      for (final ingredient in ['Aqua', 'Glycerin', 'Squalane']) {
        expect(find.text('• $ingredient'), findsOneWidget);
      }
      expect(
        find.text(ProductLookupDetailScreen.noIngredientsText),
        findsNothing,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('product_detail_source')))
            .data,
        contains('Open Beauty Facts'),
      );
    });

    testWidgets('shows a loading state while the lookup runs', (tester) async {
      final response = Completer<http.Response>();
      await _pumpLookup(
        tester,
        OpenBeautyFactsClient(client: MockClient((_) => response.future)),
      );
      await tester.enterText(
        find.byKey(const ValueKey('product_search_field')),
        'toleriane',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('product_lookup_loading')),
        findsOneWidget,
      );
      response.complete(
        _json({
          'products': [_obfProduct],
        }),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('product_lookup_loading')),
        findsNothing,
      );
      expect(find.text('Toleriane Sensitive Fluid'), findsOneWidget);
    });

    testWidgets('name search returns Open Beauty Facts results', (
      tester,
    ) async {
      await _pumpLookup(tester, _mockClient());
      await _submitSearch(tester, 'toleriane');
      expect(find.text('Toleriane Sensitive Fluid'), findsOneWidget);
      expect(find.text('La Roche-Posay · Open Beauty Facts'), findsOneWidget);
      expect(find.byKey(const ValueKey('product_search_notice')), findsNothing);
    });

    testWidgets('network failure falls back to the local catalog with a '
        'clear message', (tester) async {
      await _pumpLookup(tester, _offlineClient());
      await _submitSearch(tester, 'vanicream');
      expect(find.text('Vanicream Moisturizing Cream'), findsOneWidget);
      // Two Vanicream products in the built-in list (cream and cleanser).
      expect(find.text('Vanicream Gentle Facial Cleanser'), findsOneWidget);
      expect(find.text('Vanicream · Built-in list'), findsNWidgets(2));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('product_search_notice')))
            .data,
        startsWith(ProductLookupScreen.unreachableText),
      );
    });

    testWidgets('offline barcode scan explains the service is unreachable', (
      tester,
    ) async {
      await _pumpLookup(
        tester,
        _offlineClient(),
        readBarcode: () async =>
            const BarcodeReadResult(BarcodeReadStatus.found, _barcode),
      );
      await tester.tap(
        find.byKey(const ValueKey('product_scan_barcode_button')),
      );
      await tester.pumpAndSettle();
      final message = tester
          .widget<Text>(find.byKey(const ValueKey('product_barcode_message')))
          .data!;
      expect(message, contains('Product not found for barcode $_barcode'));
      expect(message, contains(ProductLookupScreen.unreachableText));
    });

    testWidgets('an Open Beauty Facts product without ingredients shows the '
        'existing empty message', (tester) async {
      final noIngredients = {..._obfProduct}..remove('ingredients');
      await _pumpLookup(
        tester,
        OpenBeautyFactsClient(
          client: MockClient(
            (_) async => _json({
              'products': [noIngredients],
            }),
          ),
        ),
      );
      await _submitSearch(tester, 'toleriane');
      await tester.tap(find.text('Toleriane Sensitive Fluid'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text(ProductLookupDetailScreen.noIngredientsText),
        findsOneWidget,
      );
    });

    testWidgets('a saved Open Beauty Facts product reopens from saved data', (
      tester,
    ) async {
      final product = productFromOpenBeautyFacts(_obfProduct)!;
      await saveLookupProductForLater(product);
      expect(await loadSavedProducts(), ['Toleriane Sensitive Fluid']);
      await _pumpLookup(tester, _offlineClient());
      await tester.tap(find.text('Toleriane Sensitive Fluid'));
      await tester.pumpAndSettle();
      expect(find.text('• Squalane'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
    });
  });
}
