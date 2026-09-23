// lib/utils/premium_access.dart
//
// Premium subscription gating + dev / testing override.
//
// Tier model:
//   • Free     — limited scans, basic tracking, one-time report unlocks.
//   • Premium  — $14.99 / month or $129 / year. Unlimited scans, unlimited
//                Professional Reports, AI Recovery Coach, full insights.
//
// In addition to the real RevenueCat-backed entitlement, this layer supports
// a local-only "testing mode" so the team can flip Premium on/off without
// running through a real purchase. Testing toggles are available on web,
// in debug builds, and any time the user has explicitly enabled testing
// mode from the Settings screen.

import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, visibleForTesting;
import 'package:purchases_flutter/purchases_flutter.dart';

import 'app_prefs.dart';

/// Subscription tier identifiers.
enum SubscriptionTier { free, premium }

/// Catalog of subscription products + display copy. The price strings here
/// are the "marketing" prices used on the paywall — the real price comes
/// from the store via RevenueCat at runtime when available.
class PremiumPlans {
  PremiumPlans._();

  static const String monthlyPriceDisplay = r'$14.99';
  static const String annualPriceDisplay = r'$129';
  static const String annualMonthlyEquivalent = r'$10.75';
  static const String oneTimeReportPriceDisplay = r'$16.99';

  /// RevenueCat / store product identifiers. Configure these in the
  /// RevenueCat dashboard before shipping.
  static const String monthlyProductId = 'premium_monthly';
  static const String annualProductId = 'premium_annual';

  /// RevenueCat entitlement key. Configure to match the dashboard.
  static const String entitlementId = 'premium';

  static const List<String> premiumValueLines = [
    'Unlimited skin scans & deltas',
    'Unlimited Professional Reports',
    'Full AI Recovery Coach & personalized plans',
    'Advanced metrics, insights & Recovery Timeline',
    'Provider Directory — full access',
    'Smart recovery reminders & milestones',
  ];

  static const List<String> freeValueLines = [
    '3 skin scans per month',
    'Basic skin metrics',
    'One-time Professional Report purchases',
    'Limited provider directory',
  ];
}

/// Central source-of-truth for "is the current user Premium?".
class PremiumAccess {
  PremiumAccess._();

  // Storage keys -------------------------------------------------------------

  /// Cached "real" entitlement from RevenueCat. Persisted so the UI can be
  /// instantly responsive on cold start before the network check completes.
  static const String _premiumUnlockedKey = 'premium_unlocked';

  /// Local-only override that grants Premium for development / QA. Never
  /// affects the real store entitlement.
  static const String _testingPremiumKey = 'premium_testing_override';

  /// User-controlled flag that exposes the testing UI on production builds.
  /// Off by default — flipping it on lets the Settings screen show the
  /// "Test Premium" toggle even in release.
  static const String _testingModeKey = 'premium_testing_mode_enabled';

  /// Build-time override for testers/reviewers: pass
  /// `--dart-define=TESTER_PREMIUM_UNLOCK=true` to grant Premium in every
  /// build without touching persisted prefs or the store. Off by default.
  static const bool _testerPremiumUnlockFlag =
      String.fromEnvironment('TESTER_PREMIUM_UNLOCK') == 'true';

  /// Test-only override so both states of [_testerPremiumUnlockFlag] are
  /// reachable in a single `flutter test` run. Null in production, where
  /// [testerPremiumUnlockEnabled] always reflects the real compile-time flag.
  @visibleForTesting
  static bool? debugTesterPremiumUnlockOverride;

  /// Resolved value of the TESTER_PREMIUM_UNLOCK build flag.
  static bool get testerPremiumUnlockEnabled =>
      debugTesterPremiumUnlockOverride ?? _testerPremiumUnlockFlag;

  // Entitlement checks -------------------------------------------------------

  /// True if the user should see all Premium features. Honors:
  ///   1. Build-time TESTER_PREMIUM_UNLOCK flag (always wins when set).
  ///   2. Local testing override.
  ///   3. Cached real entitlement.
  ///   4. Live RevenueCat lookup (mobile only).
  static Future<bool> isPremiumUser() async {
    if (testerPremiumUnlockEnabled) return true;
    if (await isTestingPremiumActive()) return true;

    final cached = await AppPrefs.getString(_premiumUnlockedKey);
    if ((cached ?? '').toLowerCase() == 'true') return true;

    if (kIsWeb) return false;

    try {
      final customerInfo = await Purchases.getCustomerInfo();
      final hasEntitlement = customerInfo.entitlements.active.isNotEmpty;
      if (hasEntitlement) await setPremiumUnlocked(true);
      return hasEntitlement;
    } catch (_) {
      return false;
    }
  }

  /// Current resolved tier (convenience wrapper for [isPremiumUser]).
  static Future<SubscriptionTier> currentTier() async {
    return await isPremiumUser()
        ? SubscriptionTier.premium
        : SubscriptionTier.free;
  }

  /// Persists the "real" entitlement cache. Called after a successful
  /// purchase or restore.
  static Future<void> setPremiumUnlocked(bool value) async {
    await AppPrefs.setString(_premiumUnlockedKey, value ? 'true' : 'false');
  }

  // Testing mode -------------------------------------------------------------

  /// True when the testing affordances (Test Premium / Reset to Free) should
  /// be visible to the user. Always on in debug + web, or when
  /// TESTER_PREMIUM_UNLOCK is set; opt-in elsewhere.
  static Future<bool> isTestingModeAvailable() async {
    if (kDebugMode || kIsWeb || testerPremiumUnlockEnabled) return true;
    final raw = await AppPrefs.getString(_testingModeKey);
    return (raw ?? '').toLowerCase() == 'true';
  }

  /// Force-enable the testing UI even outside debug / web.
  static Future<void> setTestingModeEnabled(bool value) async {
    await AppPrefs.setString(_testingModeKey, value ? 'true' : 'false');
  }

  /// True when the local testing override is currently granting Premium.
  static Future<bool> isTestingPremiumActive() async {
    final raw = await AppPrefs.getString(_testingPremiumKey);
    return (raw ?? '').toLowerCase() == 'true';
  }

  /// Flip the local testing override. Does **not** touch the real store
  /// entitlement cache, so disabling it cleanly reverts to whatever the
  /// real subscription says.
  static Future<void> setTestingPremium(bool value) async {
    await AppPrefs.setString(_testingPremiumKey, value ? 'true' : 'false');
  }

  /// Clears every premium flag — both real cache and testing override.
  /// Useful for resetting back to a clean "Free" state during QA.
  static Future<void> resetAllPremium() async {
    await setTestingPremium(false);
    await setPremiumUnlocked(false);
  }
}
