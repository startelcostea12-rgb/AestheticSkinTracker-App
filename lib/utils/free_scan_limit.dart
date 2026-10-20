/// Free vs Premium AI scan limit: a free user can complete
/// [kFreeAiScanLimit] AI scan in total (controlled or quick). The next
/// attempt opens the paywall instead of scanning.
///
/// Premium (subscription or the Test Premium toggle / TESTER_PREMIUM_UNLOCK)
/// and paid scan credits are unlimited and are never counted. The limit
/// applies even while the upload testing bypass is on.
///
/// The free scan is a full backend scan with full results: when the upload
/// gate would otherwise block it, the AI scan screen opens a one-scan
/// upload pass (UploadGate.beginFreeAiScanUpload) for that analysis only.
/// Existing scans are never hidden or deleted. Nothing else (logs, routine,
/// product lookup, peptides) is counted or limited here.
library;

import 'app_prefs.dart';
import 'upload_gate.dart';

/// AI scans a free user can complete in total.
const int kFreeAiScanLimit = 1;

class FreeAiScans {
  const FreeAiScans._();

  /// Completed free AI scans, stored as an integer string in AppPrefs.
  static const String usedKey = 'free_ai_scans_used';

  static Future<int> used() async {
    final raw = await AppPrefs.getString(usedKey);
    final value = int.tryParse((raw ?? '').trim()) ?? 0;
    return value < 0 ? 0 : value;
  }

  static Future<void> setUsed(int count) =>
      AppPrefs.setString(usedKey, '${count < 0 ? 0 : count}');

  /// Premium or a paid scan credit: no limit.
  static Future<bool> isUnlimited() => UploadGate.hasPaidAccess();

  /// A free user who has not used the free scan yet.
  static Future<bool> freeScanAvailable() async {
    if (await isUnlimited()) return false;
    return await used() < kFreeAiScanLimit;
  }

  /// A free user who has used the free scan.
  static Future<bool> limitReached() async {
    if (await isUnlimited()) return false;
    return await used() >= kFreeAiScanLimit;
  }

  /// Counts one completed AI scan for a free user (Premium is not counted).
  static Future<void> recordScan() async {
    if (await isUnlimited()) return;
    await setUsed(await used() + 1);
  }
}
