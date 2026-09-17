from model_evaluation_gate import evaluate_model_direction


MANIFEST = {
    "heads": {
        "roughness": {
            "negative_labels": ["clean"],
            "positive_labels": ["bumpy"],
        },
        "texture": {
            "negative_labels": ["clean"],
            "positive_labels": ["bumpy"],
        },
    },
    "cases": [
        {"photo": "clean_1", "labels": {"roughness": "clean", "texture": "clean"}},
        {"photo": "clean_2", "labels": {"roughness": "clean", "texture": "clean"}},
        {"photo": "bumpy_1", "labels": {"roughness": "bumpy", "texture": "bumpy"}},
        {"photo": "bumpy_2", "labels": {"roughness": "bumpy", "texture": "bumpy"}},
    ],
}

TRAINING_ROWS = [
    {"photo": "train_1", "labels": {"roughness": "clean", "texture": "clean"}},
    {"photo": "train_2", "labels": {"roughness": "clean", "texture": "clean"}},
    {"photo": "train_3", "labels": {"roughness": "clean", "texture": "clean"}},
    {"photo": "train_4", "labels": {"roughness": "clean", "texture": "clean"}},
    {"photo": "train_5", "labels": {"roughness": "bumpy", "texture": "bumpy"}},
]

VALIDATION_ROWS = [
    {"photo": "clean_1", "labels": {"roughness": "clean", "texture": "clean"}},
    {"photo": "clean_2", "labels": {"roughness": "clean", "texture": "clean"}},
    {"photo": "clean_3", "labels": {"roughness": "clean", "texture": "clean"}},
    {"photo": "clean_4", "labels": {"roughness": "clean", "texture": "clean"}},
    {"photo": "bumpy_1", "labels": {"roughness": "bumpy", "texture": "bumpy"}},
]


def test_collapsed_model_fails_direction_even_when_accuracy_matches_majority() -> None:
    def collapsed_model(photo: str) -> dict[str, float]:
        del photo
        return {"roughness": 0.2, "texture": 0.2}

    report = evaluate_model_direction(
        collapsed_model,
        MANIFEST,
        TRAINING_ROWS,
        VALIDATION_ROWS,
    )

    assert report.passed is False
    assert all(not result.passed for result in report.direction_results.values())
    assert all(result.negative_mean == result.positive_mean for result in report.direction_results.values())
    assert all(result.warning for result in report.majority_baselines.values())
    assert all(result.majority_accuracy == 0.8 for result in report.majority_baselines.values())
    assert all(result.validation_accuracy == 0.8 for result in report.majority_baselines.values())
    assert "DO NOT USE this model" in report.render()
    assert "negative_mean=0.2000" in report.render()


def test_working_model_passes_direction_and_reports_actual_numbers() -> None:
    def working_model(photo: str) -> dict[str, float]:
        is_bumpy = "bumpy" in photo
        return {
            "roughness": 0.85 if is_bumpy else 0.15,
            "texture": 0.90 if is_bumpy else 0.10,
        }

    report = evaluate_model_direction(
        working_model,
        MANIFEST,
        TRAINING_ROWS,
        VALIDATION_ROWS,
        validation_accuracy={"roughness": 1.0, "texture": 1.0},
    )

    assert report.passed is True
    assert all(result.passed for result in report.direction_results.values())
    assert report.direction_results["roughness"].negative_mean == 0.15
    assert report.direction_results["roughness"].positive_mean == 0.85
    assert all(not result.warning for result in report.majority_baselines.values())
    rendered = report.render()
    assert "PASS direction[roughness]" in rendered
    assert "negative_mean=0.1500 (n=2) < positive_mean=0.8500 (n=2)" in rendered
    assert "validation_accuracy=1.0000" in rendered
