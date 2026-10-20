/// Which AI scan path produced a scan: the controlled multi-frame scan (the
/// default, recommended for tracking) or the single-photo quick scan.
/// Stored in the scan's rawPayload; scans saved before this existed (and
/// gallery uploads) carry no mode.
library;

import '../models/scan_history.dart';

const String aiScanModeKey = 'ai_scan_mode';
const String aiScanModeControlled = 'controlled';
const String aiScanModeQuick = 'quick';

String? aiScanModeOfPayload(Map<String, dynamic>? payload) {
  final mode = payload?[aiScanModeKey]?.toString().trim();
  return mode == null || mode.isEmpty ? null : mode;
}

bool isQuickAiScan(ScanHistoryEntry scan) =>
    aiScanModeOfPayload(scan.rawPayload) == aiScanModeQuick;

/// "Quick scan" / "Controlled scan", or null when no mode was recorded.
String? aiScanModeLabel(ScanHistoryEntry scan) =>
    switch (aiScanModeOfPayload(scan.rawPayload)) {
      aiScanModeQuick => 'Quick scan',
      aiScanModeControlled => 'Controlled scan',
      _ => null,
    };
