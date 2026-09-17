/// Shared, user-facing copy for `trend_lock_reason(s)` — the backend field
/// that explains WHY a metric's `trend_status` was forced to "stable" by one
/// of the capture-provenance honesty gates (capture quality, extraction
/// path, source resolution, capture mode, or scale reference), as opposed to
/// a genuine small delta that happens to fall inside the honesty band.
///
/// This is purely presentational: it never changes what counts as "stable"
/// (that decision is made entirely on the backend by the existing honesty
/// gates) — it only decides how a locked "stable" is *worded* once the
/// backend has already made that call. A null/unrecognized reason means the
/// "stable" is genuine, and callers should keep their existing
/// "steady"/"stable" language unchanged.
library;

/// Recognized `trend_lock_reason` values, matching main.py's
/// `_trend_lock_reason` / `_body_trend_lock_reason`.
const Set<String> knownTrendLockReasons = {
  'capture_quality_mismatch',
  'path_mismatch',
  'resolution_mismatch',
  'capture_mode_mismatch',
  'scale_mismatch',
};

/// Very short (headline/badge-safe) replacement for a bare "Stable" label
/// when the lock was caused by a mismatch gate — deliberately terse so it
/// never overflows a tight, large-font headline slot. Pair it with
/// [trendLockReasonShortLabel] or [trendLockReasonDetail] for the
/// supporting sentence that explains *why*. Returns null for a genuine
/// stable, same as the other helpers here.
String? trendLockReasonHeadline(String? reason) {
  return knownTrendLockReasons.contains(reason) ? 'Standalone entry' : null;
}

/// Short, single-line replacement for a bare "stable"/"steady" label when
/// the lock was caused by a mismatch gate. Returns null for a genuine
/// stable (reason is null or not recognized) — callers keep their existing
/// copy in that case.
String? trendLockReasonShortLabel(String? reason) {
  switch (reason) {
    case 'capture_quality_mismatch':
      return 'Standalone entry — lighting/capture conditions differed from your last scan';
    case 'path_mismatch':
      return 'Standalone entry — a different analysis method was used than your last scan';
    case 'resolution_mismatch':
      return 'Standalone entry — photo resolution differed too much from your last scan to compare';
    case 'capture_mode_mismatch':
      return 'Standalone entry — capture setup (mirror/assisted/timer) differed from your last scan';
    case 'scale_mismatch':
      return 'Standalone entry — framing/distance differed too much from your last scan to compare';
    default:
      return null;
  }
}

/// Longer supporting-detail variant for surfaces that show a headline plus a
/// sentence of context (e.g. the body silhouette trend section). Returns
/// null for a genuine stable, same as [trendLockReasonShortLabel].
String? trendLockReasonDetail(String? reason) {
  switch (reason) {
    case 'capture_quality_mismatch':
      return "This scan's lighting or capture conditions differed from your baseline, so a real change can't be measured yet — comparison resumes once conditions match again.";
    case 'path_mismatch':
      return 'This scan was analyzed using a different method than your baseline, so the two are not directly comparable.';
    case 'resolution_mismatch':
      return "This photo's resolution differs too much from your baseline photo to compare reliably.";
    case 'capture_mode_mismatch':
      return 'This scan used a different capture setup (mirror/assisted/timer) than your baseline, so it is not directly comparable.';
    case 'scale_mismatch':
      return 'Framing or distance differed too much from your baseline capture to compare reliably.';
    default:
      return null;
  }
}
