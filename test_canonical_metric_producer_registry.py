"""Permanent regression test enforcing the single-canonical-producer rule
for main.py's metric scoring engine.

Background: an audit (2026-09-21) found that _compute_zone_based_metrics
independently recomputes localized_redness, pore_visibility,
sebum_excess_oil_gloss, diffuse_flushing_erythema, pore_visibility_detected,
and a legacy-misnamed glabellar_11_lines_depth, none of which are ever read
by candidate_values in analyze_skin_patch - they are dead, silently shadowed
by a different producer function. A near-identical pattern exists at the
top level with calibrated_redness_score / calibrated_smoothness_score /
acne_activity_score / raw_pore_density, which duplicate canonical metrics
with an entirely separate, ungated formula.

This test does not re-run the pipeline; it statically inspects the
candidate_values dict literal in main.py's source so any change to which
dict a canonical metric is sourced from - even one that doesn't change
current test fixture values - is caught and requires a deliberate update
here, preventing a second competing producer from being silently
introduced again.
"""
from __future__ import annotations

import re
from pathlib import Path

MAIN_PY = Path(__file__).resolve().parent / "main.py"

# The one true producer for each canonical metric, as of the 2026-09-21
# audit. Update this mapping (and CANONICAL_METRIC_ORDER's registry comment
# in main.py) in the same change whenever a producer intentionally changes.
EXPECTED_PRODUCERS = {
    "localized_redness": "canonical_metric_matrix",
    "texture_smoothness": "canonical_metric_matrix",
    "pigment_load": "canonical_metric_matrix",
    "pore_visibility": "canonical_metric_matrix",
    "wrinkle_load": "canonical_metric_matrix",
    "breakout_activity": "canonical_metric_matrix",
    "sebum_excess_oil_gloss": "additional_metrics",
    "diffuse_flushing_erythema": "additional_metrics",
    "skin_tone_radiance_evenness": "additional_metrics",
    "glabellar_wrinkle_depth": "structural_metrics",
    "under_eye_texture_density": "zone_metrics",
    "under_eye_dark_circle_density": "zone_metrics",
    "rosacea_severity": "zone_metrics",
    "structural_firmness_elasticity": "structural_metrics",
    "pore_contraction_index": "structural_metrics",
}

# Declared in CANONICAL_METRIC_ORDER but has no producer anywhere in main.py.
# Documented as a known gap, not a competing-producer issue. If a producer is
# ever added for this metric, update this set (and the registry comment).
KNOWN_UNPRODUCED_METRICS = {"skin_hydration"}

CANONICAL_METRIC_ORDER = list(EXPECTED_PRODUCERS) + sorted(KNOWN_UNPRODUCED_METRICS)

# zone_metrics keys that are computed but must never appear as a
# candidate_values source - if one of these starts being read, a dead
# computation has silently become a second producer.
ZONE_METRICS_DEAD_KEYS = {
    "sebum_excess_oil_gloss",
    "pore_visibility",
    "pore_visibility_detected",
    "localized_redness",
    "diffuse_flushing_erythema",
    "glabellar_11_lines_depth",
}

# Legacy top-level fields computed by an independent formula that bypasses
# the canonical pipeline entirely; never a valid alternate source for a
# canonical metric.
LEGACY_NON_CANONICAL_TOP_LEVEL_FIELDS = {
    "calibrated_redness_score",
    "calibrated_smoothness_score",
    "acne_activity_score",
    "raw_pore_density",
}


def _read_main_source() -> str:
    return MAIN_PY.read_text(encoding="utf-8")


def _extract_candidate_values_block(source: str) -> str:
    match = re.search(
        r"candidate_values: Dict\[str, Any\] = \{(.*?)\n    \}",
        source,
        re.DOTALL,
    )
    assert match is not None, (
        "candidate_values dict literal not found in main.py - the producer "
        "registry test needs updating to match the current source shape."
    )
    return match.group(1)


def _extract_producer_mapping(block: str) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for line in block.splitlines():
        line = line.strip()
        if not line or not line.startswith('"'):
            continue
        entry_match = re.match(r'"(?P<key>[a-z_]+)":\s*(?P<expr>.+?),?\s*$', line)
        if not entry_match:
            continue
        key = entry_match.group("key")
        expr = entry_match.group("expr")
        source_match = re.match(r"([a-z_]+)\.get\(", expr)
        mapping[key] = source_match.group(1) if source_match else expr
    return mapping


def test_every_canonical_metric_has_exactly_one_documented_producer():
    source = _read_main_source()
    block = _extract_candidate_values_block(source)
    actual_producers = _extract_producer_mapping(block)

    for metric in CANONICAL_METRIC_ORDER:
        if metric in KNOWN_UNPRODUCED_METRICS:
            assert metric not in actual_producers, (
                f"{metric} is documented as having no producer, but "
                "candidate_values now sources it from "
                f"{actual_producers.get(metric)!r}. If this is intentional, "
                "move it from KNOWN_UNPRODUCED_METRICS into "
                "EXPECTED_PRODUCERS in this test."
            )
            continue

        assert metric in actual_producers, (
            f"{metric} is a canonical metric with no entry in "
            "candidate_values - it will always be silently omitted."
        )
        assert actual_producers[metric] == EXPECTED_PRODUCERS[metric], (
            f"{metric} is now sourced from {actual_producers[metric]!r}, but "
            f"the documented single producer is {EXPECTED_PRODUCERS[metric]!r}. "
            "If this change is intentional, update EXPECTED_PRODUCERS here and "
            "the CANONICAL_METRIC_ORDER registry comment in main.py in the "
            "same change."
        )

    # No stray keys the registry doesn't know about.
    unexpected = set(actual_producers) - set(EXPECTED_PRODUCERS)
    assert not unexpected, (
        f"candidate_values has undocumented keys: {sorted(unexpected)}. "
        "Add them to CANONICAL_METRIC_ORDER's registry comment and to this "
        "test's EXPECTED_PRODUCERS/KNOWN_UNPRODUCED_METRICS."
    )


def test_zone_metrics_dead_keys_are_never_read_as_a_candidate_values_source():
    source = _read_main_source()
    block = _extract_candidate_values_block(source)
    actual_producers = _extract_producer_mapping(block)

    for metric, source_dict in actual_producers.items():
        if source_dict != "zone_metrics":
            continue
        assert metric not in ZONE_METRICS_DEAD_KEYS, (
            f"{metric} is read from zone_metrics in candidate_values, but is "
            "documented as one of zone_metrics's dead/shadowed keys. Either "
            "this key has been intentionally revived as a real producer (in "
            "which case remove it from ZONE_METRICS_DEAD_KEYS and update the "
            "comment at _compute_zone_based_metrics's return statement), or "
            "this is a regression reintroducing a competing producer."
        )


def test_legacy_top_level_fields_are_not_wired_into_candidate_values():
    source = _read_main_source()
    block = _extract_candidate_values_block(source)

    for legacy_field in LEGACY_NON_CANONICAL_TOP_LEVEL_FIELDS:
        assert legacy_field not in block, (
            f"{legacy_field} (a legacy, independently-computed top-level "
            "field) now appears inside candidate_values. It must never "
            "become an alternate source for a canonical metric - see the "
            "comment where it's computed in analyze_skin_patch."
        )
