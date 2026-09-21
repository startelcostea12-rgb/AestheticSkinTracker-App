from pathlib import Path

import numpy as np

from scin_experimental_models import MODEL_SPECS, ScinExperimentalModels


ROOT = Path(__file__).resolve().parent


def test_scin_checkpoints_load_and_emit_only_experimental_fields() -> None:
    models = ScinExperimentalModels(ROOT)
    models.load()

    assert models.available, models.load_error
    scores = models.predict(np.zeros((224, 224, 3), dtype=np.uint8))

    assert set(scores) == {
        "texture_ml_rough_flaky_experimental",
        "dermatitis_pattern_ml_experimental",
    }
    assert all(0.0 <= value <= 1.0 for value in scores.values())
    assert not any(key in {"localized_redness", "texture_smoothness", "pore_visibility"} for key in scores)
    assert all(spec["field"].endswith("_experimental") for spec in MODEL_SPECS.values())


def test_scin_metadata_marks_outputs_noncanonical() -> None:
    metadata = ScinExperimentalModels(ROOT).metadata()
    assert metadata["experimental"] is True
    assert metadata["canonical"] is False
    assert metadata["input_size"] == 224
    assert metadata["normalization"]["mean"] == [0.485, 0.456, 0.406]
    assert metadata["normalization"]["std"] == [0.229, 0.224, 0.225]
