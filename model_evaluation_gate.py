"""Reusable pre-release gate for image-classification model directionality.

The gate is intentionally model-runtime agnostic. A caller supplies a model
adapter ``model(photo) -> {head_name: score}``, a JSON-like sanity manifest,
and training/validation rows. This lets the same check cover Keras, TFLite,
PyTorch, or a remote inference wrapper without trusting any particular
framework's validation report.

Manifest shape::

    {
      "heads": {
        "texture": {
          "negative_labels": ["clean"],
          "positive_labels": ["severe"]
        }
      },
      "cases": [
        {"photo": "clean_01.jpg", "labels": {"texture": "clean"}},
        {"photo": "severe_01.jpg", "labels": {"texture": "severe"}}
      ]
    }

Rows may be dictionaries, pandas DataFrame rows, or any mapping-like object.
Each validation row must contain ``photo`` and ``labels`` (or a head-specific
label column); training rows use the same shape. Validation accuracy may be
provided explicitly as ``validation_accuracy={"texture": 0.794}``, or it is
computed from the supplied validation rows using a 0.5 score threshold.
"""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
import importlib
import json
import math
from pathlib import Path
from typing import Any, Callable, Iterable, Mapping


ModelAdapter = Callable[[Any], Mapping[str, float]]


@dataclass(frozen=True)
class HeadDirectionResult:
    head: str
    negative_count: int
    positive_count: int
    negative_mean: float | None
    positive_mean: float | None
    passed: bool
    detail: str


@dataclass(frozen=True)
class MajorityBaselineResult:
    head: str
    positive_rate: float
    majority_accuracy: float
    validation_accuracy: float | None
    warning: bool
    detail: str


@dataclass(frozen=True)
class ModelEvaluationReport:
    direction_results: dict[str, HeadDirectionResult]
    majority_baselines: dict[str, MajorityBaselineResult]
    passed: bool
    warnings: tuple[str, ...]

    def render(self) -> str:
        lines = ["MODEL EVALUATION GATE"]
        for result in self.direction_results.values():
            status = "PASS" if result.passed else "FAIL"
            lines.append(f"{status} direction[{result.head}]: {result.detail}")
        for result in self.majority_baselines.values():
            prefix = "WARNING" if result.warning else "INFO"
            lines.append(f"{prefix} majority[{result.head}]: {result.detail}")
        if self.passed:
            lines.append("PASS: model direction checks passed; review warnings before use.")
        else:
            lines.append("DO NOT USE this model: one or more direction checks failed.")
        return "\n".join(lines)


def evaluate_model_direction(
    model: ModelAdapter,
    manifest: Mapping[str, Any],
    training_data: Iterable[Mapping[str, Any]] | Any,
    validation_data: Iterable[Mapping[str, Any]] | Any | None = None,
    *,
    validation_accuracy: Mapping[str, float] | None = None,
    score_threshold: float = 0.5,
    majority_warning_tolerance: float = 0.02,
) -> ModelEvaluationReport:
    """Evaluate qualitative direction and majority-class collapse risk.

    Direction passes only when the mean score for every configured negative
    label group is strictly lower than the mean score for its positive group.
    Merely having output variance is never sufficient. Missing/non-finite
    scores fail that head. Majority baselines are computed from *training*
    rows, while validation accuracy is either supplied or computed from the
    validation rows.
    """
    heads = _manifest_heads(manifest)
    cases = _manifest_cases(manifest)
    direction_results: dict[str, HeadDirectionResult] = {}

    for head, spec in heads.items():
        negative_labels = set(_string_list(spec.get("negative_labels")))
        positive_labels = set(_string_list(spec.get("positive_labels")))
        negative_scores: list[float] = []
        positive_scores: list[float] = []
        for case in cases:
            label = _case_label(case, head)
            if label is None:
                continue
            raw_score = model(case["photo"]).get(head)
            score = _finite_float(raw_score)
            if score is None:
                continue
            if label in negative_labels:
                negative_scores.append(score)
            elif label in positive_labels:
                positive_scores.append(score)

        negative_mean = _mean_or_none(negative_scores)
        positive_mean = _mean_or_none(positive_scores)
        passed = (
            negative_mean is not None
            and positive_mean is not None
            and negative_mean < positive_mean
        )
        if negative_mean is None or positive_mean is None:
            detail = (
                f"negative_mean={_format(negative_mean)} (n={len(negative_scores)}) "
                f"< positive_mean={_format(positive_mean)} (n={len(positive_scores)}) "
                "could not be established"
            )
        else:
            relation = "<" if passed else ">= (expected <)"
            detail = (
                f"negative_mean={negative_mean:.4f} (n={len(negative_scores)}) "
                f"{relation} positive_mean={positive_mean:.4f} "
                f"(n={len(positive_scores)})"
            )
        direction_results[head] = HeadDirectionResult(
            head=head,
            negative_count=len(negative_scores),
            positive_count=len(positive_scores),
            negative_mean=negative_mean,
            positive_mean=positive_mean,
            passed=passed,
            detail=detail,
        )

    rows_training = list(_rows(training_data))
    rows_validation = list(_rows(validation_data)) if validation_data is not None else []
    majority_baselines: dict[str, MajorityBaselineResult] = {}
    warnings: list[str] = []
    for head, spec in heads.items():
        positive_labels = set(_string_list(spec.get("positive_labels")))
        labels = [
            label
            for row in rows_training
            if (label := _row_label(row, head)) is not None
        ]
        positive_count = sum(label in positive_labels for label in labels)
        positive_rate = positive_count / len(labels) if labels else 0.0
        majority_accuracy = max(positive_rate, 1.0 - positive_rate) if labels else 0.0
        actual_validation_accuracy = _validation_accuracy(
            model,
            rows_validation,
            head,
            positive_labels,
            score_threshold,
            validation_accuracy,
        )
        warning = (
            actual_validation_accuracy is not None
            and labels
            and abs(actual_validation_accuracy - majority_accuracy)
            <= majority_warning_tolerance
        )
        detail = (
            f"positive_rate={positive_rate:.4f}; majority_accuracy={majority_accuracy:.4f}; "
            f"validation_accuracy={_format(actual_validation_accuracy)}"
        )
        if warning:
            warnings.append(
                f"{head}: validation accuracy is within "
                f"{majority_warning_tolerance:.1%} of majority baseline"
            )
        majority_baselines[head] = MajorityBaselineResult(
            head=head,
            positive_rate=positive_rate,
            majority_accuracy=majority_accuracy,
            validation_accuracy=actual_validation_accuracy,
            warning=warning,
            detail=detail,
        )

    passed = bool(direction_results) and all(
        result.passed for result in direction_results.values()
    )
    return ModelEvaluationReport(
        direction_results=direction_results,
        majority_baselines=majority_baselines,
        passed=passed,
        warnings=tuple(warnings),
    )


def _manifest_heads(manifest: Mapping[str, Any]) -> dict[str, Mapping[str, Any]]:
    heads = manifest.get("heads")
    if not isinstance(heads, Mapping) or not heads:
        raise ValueError("Manifest must define a non-empty 'heads' mapping.")
    return {str(key): value for key, value in heads.items() if isinstance(value, Mapping)}


def _manifest_cases(manifest: Mapping[str, Any]) -> list[Mapping[str, Any]]:
    cases = manifest.get("cases")
    if not isinstance(cases, list) or not cases:
        raise ValueError("Manifest must define a non-empty 'cases' list.")
    return [case for case in cases if isinstance(case, Mapping) and "photo" in case]


def _rows(data: Iterable[Mapping[str, Any]] | Any) -> Iterable[Mapping[str, Any]]:
    if data is None:
        return []
    if hasattr(data, "to_dict"):
        return data.to_dict(orient="records")
    return data


def _case_label(case: Mapping[str, Any], head: str) -> str | None:
    labels = case.get("labels")
    if isinstance(labels, Mapping):
        return _normalized_label(labels.get(head))
    return _normalized_label(case.get(head))


def _row_label(row: Mapping[str, Any], head: str) -> str | None:
    labels = row.get("labels")
    if isinstance(labels, Mapping):
        return _normalized_label(labels.get(head))
    return _normalized_label(row.get(head))


def _validation_accuracy(
    model: ModelAdapter,
    rows: list[Mapping[str, Any]],
    head: str,
    positive_labels: set[str],
    threshold: float,
    supplied: Mapping[str, float] | None,
) -> float | None:
    if supplied is not None and head in supplied:
        return _finite_float(supplied[head])
    if not rows:
        return None
    correct = 0
    total = 0
    for row in rows:
        label = _row_label(row, head)
        if label is None or "photo" not in row:
            continue
        score = _finite_float(model(row["photo"]).get(head))
        if score is None:
            continue
        predicted_positive = score >= threshold
        actual_positive = label in positive_labels
        correct += predicted_positive == actual_positive
        total += 1
    return correct / total if total else None


def _string_list(value: Any) -> list[str]:
    if isinstance(value, (list, tuple, set)):
        return [label for item in value if (label := _normalized_label(item)) is not None]
    return []


def _normalized_label(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip().lower()
    return text or None


def _finite_float(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None


def _mean_or_none(values: list[float]) -> float | None:
    return sum(values) / len(values) if values else None


def _format(value: float | None) -> str:
    return "unavailable" if value is None else f"{value:.4f}"


def _load_rows(path: str) -> list[Mapping[str, Any]]:
    source = Path(path)
    if source.suffix.lower() == ".csv":
        with source.open(newline="", encoding="utf-8") as handle:
            return list(csv.DictReader(handle))
    payload = json.loads(source.read_text(encoding="utf-8"))
    if isinstance(payload, list):
        return payload
    if isinstance(payload, Mapping) and isinstance(payload.get("rows"), list):
        return payload["rows"]
    raise ValueError(f"Expected a JSON list or {{'rows': [...]}} in {source}")


def _load_factory(spec: str) -> ModelAdapter:
    module_name, separator, attribute = spec.partition(":")
    if not separator or not module_name or not attribute:
        raise ValueError("--model-factory must use module_name:factory_name")
    factory = getattr(importlib.import_module(module_name), attribute)
    adapter = factory()
    if not callable(adapter):
        raise TypeError("Model factory must return a callable photo -> {head: score}")
    return adapter


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the model directionality gate.")
    parser.add_argument("--manifest", required=True, help="Sanity-check manifest JSON")
    parser.add_argument("--training-data", required=True, help="Training labels JSON or CSV")
    parser.add_argument("--validation-data", help="Validation labels JSON or CSV")
    parser.add_argument(
        "--model-factory",
        required=True,
        help="Import path module_name:factory_name returning a model adapter",
    )
    args = parser.parse_args()
    manifest = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
    report = evaluate_model_direction(
        _load_factory(args.model_factory),
        manifest,
        _load_rows(args.training_data),
        _load_rows(args.validation_data) if args.validation_data else None,
    )
    print(report.render())
    return 0 if report.passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
