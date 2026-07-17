// lib/utils/report_purchase.dart
//
// Hybrid monetization for Professional Reports.
//
// Model:
//   • Premium subscribers   → unlimited reports.
//   • Free users            → can purchase a single report (per-procedure)
//                             for a one-time fee.
//
// On Web (where RevenueCat is unavailable) the purchase flow falls back to
// a local-unlock simulation so the QA/dev experience still works end-to-end.
// On mobile, a real RevenueCat purchase call is attempted.

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:purchases_flutter/purchases_flutter.dart';

import 'app_prefs.dart';
import 'premium_access.dart';

class ReportPurchase {
  ReportPurchase._();

  /// Display price for the one-time Professional Report unlock.
  static const String priceDisplay = r'$16.99';

  /// SKU / RevenueCat product identifier for the one-time report unlock.
  /// Configure this in App Store Connect / Play Console / RevenueCat.
  static const String productId = 'professional_report_single';

  /// Pseudo-entitlement marker for premium-equivalent flows.
  static const String _unlockedSetKey = 'unlocked_report_procedure_ids';

  // ── Entitlement checks ─────────────────────────────────────────────────────

  /// True if the user can generate the Professional Report for [procedureId]
  /// without any further purchase — either because they are a premium
  /// subscriber, or because they have already bought this specific report.
  static Future<bool> canGenerateReport(String? procedureId) async {
    if (await PremiumAccess.isPremiumUser()) return true;
    return hasUnlockedReportFor(procedureId);
  }

  /// True if a one-time report has already been purchased for [procedureId].
  static Future<bool> hasUnlockedReportFor(String? procedureId) async {
    if (procedureId == null || procedureId.trim().isEmpty) return false;
    final ids = await _loadUnlockedIds();
    return ids.contains(procedureId.trim());
  }

  // ── Purchase flow ──────────────────────────────────────────────────────────

  /// Attempts to purchase the one-time Professional Report unlock for
  /// [procedureId]. Returns `true` on a successful purchase (or restore).
  ///
  /// On web, this is a local-unlock simulation since RevenueCat is not
  /// available — callers should still treat it as a successful unlock so
  /// QA / preview environments work end-to-end.
  static Future<bool> purchaseReport({required String procedureId}) async {
    if (procedureId.trim().isEmpty) return false;

    if (kIsWeb) {
      // Web fallback — no real IAP plumbing on this surface yet.
      await _markUnlocked(procedureId);
      debugPrint('[ReportPurchase] (web) simulated unlock for $procedureId');
      return true;
    }

    try {
      final products = await Purchases.getProducts(<String>[productId]);
      if (products.isEmpty) {
        debugPrint('[ReportPurchase] product not found: $productId');
        return false;
      }

      final result = await Purchases.purchase(
        PurchaseParams.storeProduct(products.first),
      );
      // Treat any non-error result as a successful purchase. The exact
      // entitlement payload depends on the RevenueCat dashboard config;
      // we persist the per-procedure unlock regardless.
      debugPrint(
        '[ReportPurchase] purchase succeeded: ${result.customerInfo.originalAppUserId}',
      );
      await _markUnlocked(procedureId);
      return true;
    } catch (e) {
      debugPrint('[ReportPurchase] purchase failed: $e');
      return false;
    }
  }

  /// Manual unlock — used by the paywall after a successful purchase or
  /// restore. Exposed for testing / dev override.
  static Future<void> unlockReportFor(String procedureId) =>
      _markUnlocked(procedureId);

  // ── Internals ──────────────────────────────────────────────────────────────

  static Future<Set<String>> _loadUnlockedIds() async {
    final raw = await AppPrefs.getString(_unlockedSetKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        return list.map((e) => e.toString()).toSet();
      }
    } catch (e) {
      debugPrint('[ReportPurchase] _loadUnlockedIds parse error: $e');
    }
    return <String>{};
  }

  static Future<void> _markUnlocked(String procedureId) async {
    final ids = await _loadUnlockedIds();
    ids.add(procedureId.trim());
    await AppPrefs.setString(_unlockedSetKey, jsonEncode(ids.toList()));
  }
}
