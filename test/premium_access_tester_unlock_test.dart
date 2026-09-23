import 'package:aesthetic_skin_tracker/utils/premium_access.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PremiumAccess.debugTesterPremiumUnlockOverride = null;
  });

  tearDown(() {
    PremiumAccess.debugTesterPremiumUnlockOverride = null;
  });

  group('TESTER_PREMIUM_UNLOCK flag', () {
    test('is off by default so nothing changes without the build flag', () {
      expect(PremiumAccess.testerPremiumUnlockEnabled, isFalse);
    });

    test(
      'isPremiumUser() stays false with no cache/testing override when flag is off',
      () async {
        PremiumAccess.debugTesterPremiumUnlockOverride = false;
        expect(await PremiumAccess.isPremiumUser(), isFalse);
      },
    );

    test(
      'isPremiumUser() returns true immediately when flag is on, bypassing '
      'the cached flag and RevenueCat lookup',
      () async {
        PremiumAccess.debugTesterPremiumUnlockOverride = true;
        expect(await PremiumAccess.isPremiumUser(), isTrue);
      },
    );

    test(
      'isTestingModeAvailable() is true when the flag is on',
      () async {
        PremiumAccess.debugTesterPremiumUnlockOverride = true;
        expect(await PremiumAccess.isTestingModeAvailable(), isTrue);
      },
    );
  });
}
