import 'package:aesthetic_skin_tracker/utils/premium_access.dart';
import 'package:aesthetic_skin_tracker/widgets/paywall_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MethodChannel _purchasesChannel = MethodChannel('purchases_flutter');

Map<String, dynamic> _offerings({required bool withAnnualPackage}) {
  if (!withAnnualPackage) {
    return <String, dynamic>{'all': <String, dynamic>{}, 'current': null};
  }

  const presentedOfferingContext = <String, dynamic>{
    'offeringIdentifier': 'default',
    'placementIdentifier': null,
    'targetingContext': null,
  };
  const annualPackage = <String, dynamic>{
    'identifier': 'annual',
    'packageType': 'ANNUAL',
    'product': <String, dynamic>{
      'identifier': 'premium_annual',
      'description': 'Premium annual subscription',
      'title': 'Premium annual',
      'price': 129.0,
      'priceString': r'$129.00',
      'currencyCode': 'USD',
      'productCategory': 'SUBSCRIPTION',
    },
    'presentedOfferingContext': presentedOfferingContext,
  };
  const offering = <String, dynamic>{
    'identifier': 'default',
    'serverDescription': 'Default offering',
    'metadata': <String, dynamic>{},
    'availablePackages': <dynamic>[annualPackage],
    'annual': annualPackage,
  };

  return <String, dynamic>{
    'all': <String, dynamic>{'default': offering},
    'current': offering,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late bool originalRevenueCatConfigured;
  late bool withAnnualPackage;
  final methodCalls = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    originalRevenueCatConfigured = PremiumAccess.revenueCatConfigured;
    PremiumAccess.revenueCatConfigured = true;
    PremiumAccess.debugTesterPremiumUnlockOverride = false;
    withAnnualPackage = false;
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_purchasesChannel, (call) async {
          methodCalls.add(call.method);
          if (call.method == 'getOfferings') {
            return _offerings(withAnnualPackage: withAnnualPackage);
          }
          if (call.method == 'purchasePackage') {
            throw PlatformException(code: 'mock_purchase_failure');
          }
          throw PlatformException(code: 'unexpected_method');
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_purchasesChannel, null);
    PremiumAccess.revenueCatConfigured = originalRevenueCatConfigured;
    PremiumAccess.debugTesterPremiumUnlockOverride = null;
  });

  testWidgets('mobile paywall without a package does not unlock Premium', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PaywallScreen()));
    await tester.pumpAndSettle();

    final purchaseButton = find.textContaining('Start Premium');
    await tester.ensureVisible(purchaseButton);
    await tester.tap(purchaseButton);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('premium_unlocked'), isNull);
    expect(methodCalls, contains('getOfferings'));
    expect(methodCalls, isNot(contains('purchasePackage')));
    expect(
      find.text(
        'Live pricing is temporarily unavailable. You can still continue with listed plan pricing.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('mobile paywall with a package invokes RevenueCat purchase', (
    tester,
  ) async {
    withAnnualPackage = true;
    await tester.pumpWidget(const MaterialApp(home: PaywallScreen()));
    await tester.pumpAndSettle();

    final purchaseButton = find.textContaining(r'Start Premium · $129.00');
    expect(purchaseButton, findsOneWidget);
    await tester.ensureVisible(purchaseButton);
    await tester.tap(purchaseButton);
    await tester.pumpAndSettle();

    expect(methodCalls, contains('purchasePackage'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('premium_unlocked'), isNull);
  });
}
