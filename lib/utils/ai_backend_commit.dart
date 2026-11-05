/// rawPayload key for the backend git commit that produced this scan's
/// analysis (see GET /health and analyze responses' `backend_commit`).
/// Logging/provenance only — never used for metric math.
const String aiBackendCommitKey = 'backend_commit';

/// Writes [commit] onto [payload] when it is a non-empty server value.
/// Ignores null/blank so older servers that omit the field leave the
/// export cell empty instead of storing a client-side placeholder.
void recordAiBackendCommit(Map<String, dynamic> payload, String? commit) {
  final trimmed = commit?.trim();
  if (trimmed == null || trimmed.isEmpty) return;
  payload[aiBackendCommitKey] = trimmed;
}

/// Prefers an analyze-response commit (`backend_commit` / `commit`), then
/// a previously stored payload value, then a /health fetch. Returns null
/// when none of those sources have a usable server commit.
String? resolveAiBackendCommit({
  Map<String, dynamic>? analyzeResponse,
  Map<String, dynamic>? existingPayload,
  String? healthCommit,
}) {
  for (final source in <Map<String, dynamic>?>[
    analyzeResponse,
    existingPayload,
  ]) {
    if (source == null) continue;
    for (final key in const [
      aiBackendCommitKey,
      'backendCommit',
      'git_commit',
      'gitCommit',
      'commit',
    ]) {
      final value = source[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
  }
  final health = healthCommit?.trim();
  if (health != null && health.isNotEmpty) return health;
  return null;
}
