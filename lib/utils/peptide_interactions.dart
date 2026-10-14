/// Peptide / actives interaction rules, shared by the peptide tracker and
/// the home recommendation card. Moved unchanged from
/// peptide_tracker_screen.dart.
library;

/// Known peptide / actives interactions surfaced as gentle advisory notes.
///
/// Each entry pairs two ingredient names (or simple substrings) with a
/// short, user-facing reminder. Matching is case-insensitive and uses
/// `String.contains` on the lowercased peptide name so both library names
/// and free-typed names will match (e.g. "GHK-Cu" matches "GHK" / "Copper").
class _PeptideInteractionRule {
  final String a;
  final String b;
  final String message;
  const _PeptideInteractionRule(this.a, this.b, this.message);
}

const List<_PeptideInteractionRule> _kPeptideInteractions = [
  _PeptideInteractionRule(
    'ghk-cu',
    'vitamin c',
    'GHK-Cu and Vitamin C (ascorbic acid) can deactivate each other — apply at different times of day.',
  ),
  _PeptideInteractionRule(
    'ghk-cu',
    'retinol',
    'GHK-Cu and retinoids may increase sensitivity — monitor for redness, alternate nights if irritated.',
  ),
  _PeptideInteractionRule(
    'ghk-cu',
    'aha',
    'GHK-Cu and AHAs/BHAs can lower copper-peptide stability and increase sensitivity — separate by ≥30 min.',
  ),
  _PeptideInteractionRule(
    'ahk-cu',
    'vitamin c',
    'Copper peptides (AHK-Cu) and ascorbic acid can neutralize each other — use AM/PM split.',
  ),
  _PeptideInteractionRule(
    'argireline',
    'retinol',
    'Argireline + retinoids may amplify dryness; introduce gradually and pair with a barrier moisturizer.',
  ),
  _PeptideInteractionRule(
    'matrixyl',
    'retinol',
    'Matrixyl + retinoids: watch for irritation if combined; consider alternating evenings.',
  ),
  _PeptideInteractionRule(
    'egf',
    'retinol',
    'EGF and high-strength retinoids can compete — monitor skin reaction and reduce frequency if needed.',
  ),
  _PeptideInteractionRule(
    'snap-8',
    'argireline',
    'SNAP-8 + Argireline target the same SNARE pathway — combining adds limited benefit but can over-relax expression lines.',
  ),
];

/// Returns a deduplicated list of interaction warnings for any pair within
/// the given peptide names. Comparison is case-insensitive and uses
/// substring matching so user-entered variants still match.
List<String> peptideInteractionWarnings(Iterable<String> names) {
  final lowered = names
      .map((n) => n.trim().toLowerCase())
      .where((n) => n.isNotEmpty)
      .toSet()
      .toList();
  final warnings = <String>{};
  for (final rule in _kPeptideInteractions) {
    final hasA = lowered.any((n) => n.contains(rule.a));
    final hasB = lowered.any((n) => n.contains(rule.b));
    if (hasA && hasB) warnings.add(rule.message);
  }
  return warnings.toList();
}
