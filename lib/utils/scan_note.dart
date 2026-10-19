/// Optional free-text note saved with a scan (rawPayload `scan_note`),
/// exported in the scan-data CSV and the comparison PDF. Empty notes are
/// never stored.
library;

import '../models/scan_history.dart';
import 'app_prefs.dart';

const String scanNoteKey = 'scan_note';

/// The scan's note, or null when none was saved.
String? scanNoteOf(ScanHistoryEntry scan) {
  final note = scan.rawPayload?[scanNoteKey]?.toString().trim();
  return note == null || note.isEmpty ? null : note;
}

/// Saves [note] on the saved scan [scanId] (in its rawPayload, so it is
/// persisted with the scan). A blank note removes any saved one. False when
/// the scan isn't found.
Future<bool> saveScanNote({required String scanId, required String note}) {
  final trimmed = note.trim();
  return AppPrefs.patchScanRawPayload(scanId, (rawPayload) {
    if (trimmed.isEmpty) {
      rawPayload.remove(scanNoteKey);
    } else {
      rawPayload[scanNoteKey] = trimmed;
    }
    return rawPayload;
  });
}
