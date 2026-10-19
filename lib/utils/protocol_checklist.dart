/// Capture protocol checklist shown on the camera the first time it opens
/// after a Front baseline reset (AppPrefs.clearAiBaselineScanId leaves a
/// resetAt marker while no new baseline is set). Dismissal is remembered for
/// that reset, so it does not reappear until the next one. Never gates
/// capture.
library;

import '../models/scan_history.dart';
import 'app_prefs.dart';

const List<String> protocolChecklistItems = <String>[
  'Gray card in first frame',
  'Lamp on',
  'Blinds closed',
  'Chin at same height',
];

/// Stores the resetAt of the Front baseline reset whose checklist was
/// dismissed.
const String protocolChecklistDismissedKey =
    'protocol_checklist_dismissed_reset_at';

/// The pending Front baseline reset's marker (its resetAt, UTC ISO-8601) for
/// the AI scan's facial Front key, or null when no reset is pending.
Future<String?> frontBaselineResetToken({
  required String? procedureId,
  required String? focusArea,
}) async {
  final state = await AppPrefs.getAiBaselineRegistryState(
    ScanHistoryEntry.resolveAiBaselineKey(
      procedureId: procedureId,
      focusArea: focusArea,
      poseTemplate: 'Front',
      guideType: 'facial',
    ),
  );
  final resetAt = state.resetAt;
  if (!state.isResetPending || resetAt == null) return null;
  return resetAt.toUtc().toIso8601String();
}

Future<bool> shouldShowProtocolChecklist(String? resetToken) async {
  if (resetToken == null) return false;
  return await AppPrefs.getString(protocolChecklistDismissedKey) != resetToken;
}

Future<void> dismissProtocolChecklist(String resetToken) =>
    AppPrefs.setString(protocolChecklistDismissedKey, resetToken);
