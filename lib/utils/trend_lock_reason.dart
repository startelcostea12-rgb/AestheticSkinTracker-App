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

/// Recognized `trend_lock_reason` values. Most match main.py's
/// `_trend_lock_reason` / `_body_trend_lock_reason`; `frame_range_overlap`
/// and `below_noise_floor` are the exceptions — both are applied entirely
/// client-side (by downgradeTrendForOverlappingFrameRanges and
/// downgradeTrendBelowMeasuredNoiseFloor respectively), after the backend's
/// own gates have already run (see each function's doc comment).
const Set<String> knownTrendLockReasons = {
  'capture_quality_mismatch',
  'path_mismatch',
  'resolution_mismatch',
  'capture_mode_mismatch',
  'scale_mismatch',
  'frame_range_overlap',
  'below_noise_floor',
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
    case 'frame_range_overlap':
      return 'Standalone entry — frame-to-frame variability was too high to confirm a real change';
    case 'below_noise_floor':
      return 'Standalone entry — the change is smaller than this metric\'s known measurement noise';
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
    case 'frame_range_overlap':
      return "This scan's and your baseline's own frame-to-frame readings overlapped too much to confirm a real change — capture noise could explain the difference on its own.";
    case 'below_noise_floor':
      return "This metric's measured change is smaller than its known scan-to-scan measurement noise, so it can't be confirmed as a real change yet.";
    default:
      return null;
  }
}
