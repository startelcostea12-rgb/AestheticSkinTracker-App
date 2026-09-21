#!/usr/bin/env python3
"""Run the model_evaluation_gate against a labeled SCIN reference manifest.

The manifest must contain real photos and explicit labels for each head. This
script refuses to invent labels from filenames or from model outputs.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any

import cv2
import numpy as np
import torch
from PIL import Image
from torchvision.models import efficientnet_b0
from torch import nn

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model_evaluation_gate import evaluate_model_direction
MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)
SPECS = {
    "rough_flaky": ROOT / "ml_models" / "scin_rough_flaky_classifier_v1.pth",
    "dermatitis": ROOT / "ml_models" / "scin_dermatitis_classifier_v1.pth",
}


def load_model(path: Path) -> nn.Module:
    model = efficientnet_b0(weights=None)
    model.classifier = nn.Sequential(
        nn.Dropout(p=0.2),
        nn.Linear(1280, 256),
        nn.ReLU(),
        nn.Dropout(p=0.2),
        nn.Linear(256, 1),
    )
    model.load_state_dict(torch.load(path, map_location="cpu", weights_only=True), strict=True)
    model.eval()
    return model


def predict(model: nn.Module, photo: str) -> float:
    image_path = ROOT / photo
    image = Image.open(image_path).convert("RGB").resize((224, 224))
    array = np.asarray(image, dtype=np.float32) / 255.0
    array = (array - MEAN) / STD
    tensor = torch.from_numpy(array.transpose(2, 0, 1)).unsqueeze(0)
    with torch.inference_mode():
        return float(torch.sigmoid(model(tensor).reshape(-1)[0]).item())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    manifest: dict[str, Any] = json.loads(args.manifest.read_text(encoding="utf-8"))
    cases = manifest.get("cases", [])
    if not cases:
        raise SystemExit("Manifest must contain labeled real-photo cases.")
    models = {head: load_model(path) for head, path in SPECS.items()}
    predictions = {
        head: {str(case["photo"]): predict(model, str(case["photo"])) for case in cases}
        for head, model in models.items()
    }

    def adapter(photo: str) -> dict[str, float]:
        return {head: values[photo] for head, values in predictions.items()}

    report = evaluate_model_direction(
        adapter,
        manifest,
        manifest.get("training_rows", cases),
        manifest.get("validation_rows", cases),
        validation_accuracy=manifest.get("validation_accuracy"),
    )
    print(report.render())
    print("RAW SCORES")
    for photo in predictions["rough_flaky"]:
        print(json.dumps({"photo": photo, **{head: values[photo] for head, values in predictions.items()}}))
    if not report.passed:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
