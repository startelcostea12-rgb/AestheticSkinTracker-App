/// Free vs Premium daily AI scan limit.
///
/// Free: [kFreeDailyAiScanLimit] AI scans per calendar day (device local
/// time; controlled and quick scans both count). Premium (subscription) and
/// users with a paid scan credit have no daily limit. When the limit is
/// reached, starting a new scan shows a short message and a Premium upsell
/// instead. Existing scans are never deleted or hidden.
///
/// This limit is separate from, and does not change, the upload gate
/// (UploadGate) and the lifetime free local-scan cap (FreeLocalScans). It
/// applies even while the upload testing bypass is on; testers can use the
/// Settings "Test Premium" toggle or TESTER_PREMIUM_UNLOCK to scan freely.
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../widgets/paywall_screen.dart';
import 'app_prefs.dart';
import 'upload_gate.dart';

/// AI scans a free user may complete per calendar day.
const int kFreeDailyAiScanLimit = 3;

class DailyAiScans {
  const DailyAiScans._();

  /// AppPrefs key: {"day": "yyyy-mm-dd", "count": n}.
  static const String usedKey = 'daily_ai_scans_used';

  static String dayKey(DateTime now) {
    final local = now.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    return '${local.year}-$mm-$dd';
  }

  /// AI scans completed today (0 on a new day).
  static Future<int> usedToday({DateTime? now}) async {
    final raw = await AppPrefs.getString(usedKey);
    if (raw == null || raw.isEmpty) return 0;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['day'] != dayKey(now ?? DateTime.now())) {
        return 0;
      }
      final count = decoded['count'];
      return count is int && count > 0 ? count : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Counts one completed AI scan for today.
  static Future<void> recordScan({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final count = await usedToday(now: at) + 1;
    await AppPrefs.setString(
      usedKey,
      jsonEncode({'day': dayKey(at), 'count': count}),
    );
  }

  /// Premium or a paid scan credit: no daily limit.
  static Future<bool> isUnlimited() => UploadGate.hasPaidAccess();

  /// True when a free user has used today's [kFreeDailyAiScanLimit] scans.
  static Future<bool> limitReached({DateTime? now}) async {
    if (await isUnlimited()) return false;
    return await usedToday(now: now) >= kFreeDailyAiScanLimit;
  }
}

class DailyScanLimitDialog {
  const DailyScanLimitDialog._();

  static const String title = 'Daily scan limit reached';
  static const String message =
      'Free accounts include $kFreeDailyAiScanLimit AI scans per day. Your '
      'saved scans stay as they are. Scan again tomorrow, or get unlimited '
      'scans with Premium.';
}

/// Shows the daily-limit message with a Premium upsell and returns true
/// when a free user has reached today's limit; the caller must then stop
/// without starting a scan. Premium users never see it.
Future<bool> showDailyScanLimitIfReached(BuildContext context) async {
  if (!await DailyAiScans.limitReached()) return false;
  if (!context.mounted) return true;
  final upgrade = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('daily_scan_limit_dialog'),
      title: const Text(DailyScanLimitDialog.title),
      content: const Text(DailyScanLimitDialog.message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          key: const ValueKey('daily_scan_limit_premium'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('See Premium'),
        ),
      ],
    ),
  );
  if (upgrade == true && context.mounted) {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PaywallScreen()));
  }
  return true;
}
