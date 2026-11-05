/// rawPayload keys for capture-time head pose (degrees). Logging/export
/// only — never used as a post-capture reject gate.
const String aiHeadYawKey = 'head_yaw';
const String aiHeadPitchKey = 'head_pitch';
const String aiHeadRollKey = 'head_roll';

void recordAiHeadAngle(
  Map<String, dynamic> payload, {
  double? yaw,
  double? pitch,
  double? roll,
}) {
  if (yaw != null && yaw.isFinite) payload[aiHeadYawKey] = yaw;
  if (pitch != null && pitch.isFinite) payload[aiHeadPitchKey] = pitch;
  if (roll != null && roll.isFinite) payload[aiHeadRollKey] = roll;
}
