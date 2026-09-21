"""Experimental SCIN classifiers kept separate from canonical skin metrics."""
from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image

try:
    import torch
    from torch import nn
    from torchvision.models import efficientnet_b0
except Exception:  # pragma: no cover - optional backend dependency
    torch = None
    nn = None
    efficientnet_b0 = None


INPUT_SIZE = 224
IMAGENET_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
IMAGENET_STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)
IMAGENET_MEAN_METADATA = [0.485, 0.456, 0.406]
IMAGENET_STD_METADATA = [0.229, 0.224, 0.225]

MODEL_SPECS = {
    "rough_flaky": {
        "field": "texture_ml_rough_flaky_experimental",
        "path": "ml_models/scin_rough_flaky_classifier_v1.pth",
        "description": "SCIN rough/flaky surface-pattern probability",
    },
    "dermatitis": {
        "field": "dermatitis_pattern_ml_experimental",
        "path": "ml_models/scin_dermatitis_classifier_v1.pth",
        "description": "SCIN dermatitis-family pattern probability",
    },
}


class ScinExperimentalModels:
    """Loads the two SCIN models without entering canonical metric assembly."""

    def __init__(self, project_root: str | Path):
        self.project_root = Path(project_root)
        self._models: dict[str, Any] = {}
        self.load_error: str | None = None

    @property
    def available(self) -> bool:
        return len(self._models) == len(MODEL_SPECS)

    def load(self) -> None:
        if torch is None or nn is None or efficientnet_b0 is None:
            self.load_error = "torch/torchvision is not installed"
            return
        try:
            for name, spec in MODEL_SPECS.items():
                path = self.project_root / spec["path"]
                if not path.is_file():
                    raise FileNotFoundError(str(path))
                model = efficientnet_b0(weights=None)
                model.classifier = nn.Sequential(
                    nn.Dropout(p=0.2),
                    nn.Linear(1280, 256),
                    nn.ReLU(),
                    nn.Dropout(p=0.2),
                    nn.Linear(256, 1),
                )
                state_dict = torch.load(path, map_location="cpu", weights_only=True)
                model.load_state_dict(state_dict, strict=True)
                model.eval()
                self._models[name] = model
        except Exception as exc:
            self._models.clear()
            self.load_error = f"{type(exc).__name__}: {exc}"

    def predict(self, image_bgr: np.ndarray) -> dict[str, float]:
        if not self.available:
            return {}
        rgb = image_bgr[:, :, ::-1]
        image = Image.fromarray(rgb).convert("RGB").resize((INPUT_SIZE, INPUT_SIZE))
        array = np.asarray(image, dtype=np.float32) / 255.0
        array = (array - IMAGENET_MEAN) / IMAGENET_STD
        tensor = torch.from_numpy(array.transpose(2, 0, 1)).unsqueeze(0)
        with torch.inference_mode():
            output: dict[str, float] = {}
            for name, model in self._models.items():
                logit = model(tensor).reshape(-1)[0]
                probability = float(torch.sigmoid(logit).item())
                output[MODEL_SPECS[name]["field"]] = round(probability, 6)
        return output

    def metadata(self) -> dict[str, Any]:
        return {
            "status": "available" if self.available else "unavailable",
            "experimental": True,
            "canonical": False,
            "input_size": INPUT_SIZE,
            "normalization": {
                "mean": IMAGENET_MEAN_METADATA,
                "std": IMAGENET_STD_METADATA,
            },
            "models": {
                name: {
                    "field": spec["field"],
                    "path": spec["path"],
                    "description": spec["description"],
                }
                for name, spec in MODEL_SPECS.items()
            },
            "load_error": self.load_error,
        }
