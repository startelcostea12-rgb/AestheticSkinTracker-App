import 'dart:io';

import 'package:aesthetic_skin_tracker/models/product_tracker.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:aesthetic_skin_tracker/widgets/removable_tracked_product.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

TrackedProduct _product(String id, String name) => TrackedProduct(
  id: id,
  name: name,
  brand: 'Brand',
  keyIngredients: '',
  startDate: DateTime(2026, 9, 1),
);

/// A list of tracked products like Home's "Your Active Skincare".
class _List extends StatefulWidget {
  const _List(this.products);
  final List<TrackedProduct> products;
  @override
  State<_List> createState() => _ListState();
}

class _ListState extends State<_List> {
  late List<TrackedProduct> products = List.of(widget.products);
  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListView(
      children: [
        for (final product in products)
          RemovableTrackedProduct(
            product: product,
            onRemoved: () => setState(
              () => products = [
                for (final p in products)
                  if (p.id != product.id) p,
              ],
            ),
            child: ListTile(title: Text(product.name)),
          ),
      ],
    ),
  );
}

Future<void> _seed() async {
  await AppPrefs.addTrackedProduct(_product('p1', 'Niacinamide Serum'));
  await AppPrefs.addTrackedProduct(_product('p2', 'Barrier Cream'));
  await AppPrefs.addScanEntry(
    ScanHistoryEntry(
      id: 'scan-1',
      timestamp: DateTime(2026, 9, 10),
      estimatedSkinAge: 0,
      metrics: const {'redness': 20.0},
      productName: 'Niacinamide Serum',
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('swipe + confirm removes only that product; scans stay', (
    tester,
  ) async {
    await tester.runAsync(_seed);
    final products = await tester.runAsync(AppPrefs.getTrackedProducts);
    await tester.pumpWidget(MaterialApp(home: _List(products!)));

    await tester.drag(find.text('Niacinamide Serum'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Remove Niacinamide Serum?'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('tracked_product_remove_confirm')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Niacinamide Serum'), findsNothing);
    expect(find.text('Barrier Cream'), findsOneWidget);
    expect(find.text('Niacinamide Serum removed.'), findsOneWidget);

    final remaining = await tester.runAsync(AppPrefs.getTrackedProducts);
    expect([for (final p in remaining!) p.id], ['p2']);
    // Past scans for the removed product are untouched.
    final scans = await tester.runAsync(
      () => AppPrefs.getScanEntriesForProduct('Niacinamide Serum'),
    );
    expect([for (final s in scans!) s.id], ['scan-1']);
  });

  testWidgets('cancel keeps the product', (tester) async {
    await tester.runAsync(_seed);
    final products = await tester.runAsync(AppPrefs.getTrackedProducts);
    await tester.pumpWidget(MaterialApp(home: _List(products!)));

    await tester.drag(find.text('Barrier Cream'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Barrier Cream'), findsOneWidget);
    final remaining = await tester.runAsync(AppPrefs.getTrackedProducts);
    expect(remaining!.length, 2);
  });

  test('wiring: Home list and the details screen offer removal', () {
    final home = File('lib/screens/home_screen.dart').readAsStringSync();
    expect(home, contains('(product) => RemovableTrackedProduct('));
    final details = File(
      'lib/screens/active_skincare_details_screen.dart',
    ).readAsStringSync();
    expect(details, contains('confirmAndRemoveTrackedProduct('));
    expect(details, contains("Text('Remove from my skincare')"));
  });
}
