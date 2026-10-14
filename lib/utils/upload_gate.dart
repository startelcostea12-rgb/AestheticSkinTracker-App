/// Paid gate for every path that sends a photo off the device: the backend
/// skin analysis endpoints (lib/utils/skin_analysis_service.dart) and AI
/// product-photo reading (AiLlmService.analyzeSkinWithImage). Local work —
/// face check, Bv/ISO logging, lighting and cheek locks, on-device models,
/// and "From your logs" notes — never goes through this gate.
///
/// A photo may leave the device when the user has an active subscription
/// (PremiumAccess.isPremiumUser) or at least one paid scan credit.
///
/// TESTING BYPASS: [kUploadGateBypass] currently defaults to true so scans
/// still go through while testing. To enforce the gate, change the
/// `defaultValue` below to false (or build with
/// `--dart-define=UPLOAD_GATE_BYPASS=false`). The real check stays in place
/// underneath; the bypass only short-circuits it.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'app_prefs.dart';
import 'premium_access.dart';

const bool kUploadGateBypass = bool.fromEnvironment(
  'UPLOAD_GATE_BYPASS',
  defaultValue: true,
);

class UploadGateBlockedException implements Exception {
  const UploadGateBlockedException([this.message = UploadGate.blockedMessage]);

  final String message;

  @override
  String toString() => message;
}

class UploadGate {
  const UploadGate._();

  /// Remaining paid scan credits, stored as an integer string. Nothing
  /// grants credits yet, so without a subscription this is 0.
  static const String scanCreditsKey = 'paid_scan_credits';

  static const String blockedMessage =
      'Your on-device check is done and nothing was uploaded. Full AI '
      'analysis needs Premium or a scan credit.';

  /// Test-only override of [kUploadGateBypass]; null in production.
  @visibleForTesting
  static bool? debugBypassOverride;

  static bool get bypassEnabled => debugBypassOverride ?? kUploadGateBypass;

  static Future<int> remainingScanCredits() async {
    final raw = await AppPrefs.getString(scanCreditsKey);
    final value = int.tryParse((raw ?? '').trim()) ?? 0;
    return value < 0 ? 0 : value;
  }

  static Future<void> setScanCredits(int credits) =>
      AppPrefs.setString(scanCreditsKey, '${credits < 0 ? 0 : credits}');

  /// The real check: an active subscription or a remaining scan credit.
  static Future<bool> hasPaidAccess() async {
    if (await PremiumAccess.isPremiumUser()) return true;
    return await remainingScanCredits() > 0;
  }

  /// Whether a photo may be uploaded now ([bypassEnabled] short-circuits
  /// the real check while testing).
  static Future<bool> canUpload() async {
    if (bypassEnabled) return true;
    return hasPaidAccess();
  }

  /// Throws [UploadGateBlockedException] when [canUpload] is false. Called
  /// immediately before any photo is sent.
  static Future<void> ensureCanUpload() async {
    if (!await canUpload()) throw const UploadGateBlockedException();
  }

  /// Uses one credit after a completed backend scan. A subscription (or the
  /// testing bypass) does not use credits.
  static Future<void> recordCompletedBackendScan() async {
    if (bypassEnabled) return;
    if (await PremiumAccess.isPremiumUser()) return;
    final remaining = await remainingScanCredits();
    if (remaining > 0) await setScanCredits(remaining - 1);
  }
}
