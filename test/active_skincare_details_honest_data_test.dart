// Regression test for the Priority-1 fabricated-data fix in
// active_skincare_details_screen.dart: when real scan metric data (or a
// trustworthy per-scan skin age) is missing, the screen must show honest
// "not enough data" messaging, never a formula-generated fake number.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aesthetic_skin_tracker/models/product_tracker.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/screens/active_skincare_details_screen.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';

TrackedProduct _product() => TrackedProduct(
  id: 'prod_1',
  name: 'Test Serum',
  brand: 'Test Brand',
  keyIngredients: 'Niacinamide',
  startDate: DateTime(2026, 1, 1),
);

ScanHistoryEntry _scan({
  required String id,
  required DateTime timestamp,
  required double estimatedSkinAge,
  Map<String, double> metrics = const {},
}) {
  return ScanHistoryEntry(
    id: id,
    timestamp: timestamp,
    estimatedSkinAge: estimatedSkinAge,
    metrics: metrics,
    productName: 'Test Serum',
    captureQuality: 'normal',
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'shows honest not-enough-data messaging instead of fabricated numbers when scans have no real metrics',
    (tester) async {
      await AppPrefs.addScanEntry(
        _scan(id: 's1', timestamp: DateTime(2026, 1, 5), estimatedSkinAge: 0),
      );
      await AppPrefs.addScanEntry(
        _scan(id: 's2', timestamp: DateTime(2026, 1, 20), estimatedSkinAge: 0),
      );

      await tester.pumpWidget(
        MaterialApp(home: ActiveSkincareDetailsScreen(product: _product())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Not enough data yet to estimate skin age.'), findsOneWidget);
      expect(find.text('Not enough data yet'), findsOneWidget);
      expect(
        find.text('Not enough recorded metric data yet to show a comparison.'),
        findsOneWidget,
      );
      expect(
        find.text('Not enough scan data yet to recommend a next procedure.'),
        findsOneWidget,
      );

      // The old fabricated values must never appear.
      expect(find.text('65%'), findsNothing);
      expect(find.text('34 years'), findsNothing);
    },
  );

  testWidgets(
    'shows the real recorded skin age and metrics when scans have trustworthy data',
    (tester) async {
      await AppPrefs.addScanEntry(
        _scan(
          id: 's1',
          timestamp: DateTime(2026, 1, 5),
          estimatedSkinAge: 36,
          metrics: const {'redness': 6.0, 'texture': 6.0},
        ),
      );
      await AppPrefs.addScanEntry(
        _scan(
          id: 's2',
          timestamp: DateTime(2026, 1, 20),
          estimatedSkinAge: 30,
          metrics: const {'redness': 3.0, 'texture': 3.0},
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: ActiveSkincareDetailsScreen(product: _product())),
      );
      await tester.pumpAndSettle();

      // The real, latest scan's own estimatedSkinAge is shown verbatim.
      expect(find.text('30 years'), findsOneWidget);
      expect(find.text('Not enough data yet to estimate skin age.'), findsNothing);
    },
  );
}
