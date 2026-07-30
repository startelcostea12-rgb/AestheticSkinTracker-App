import argparse
import base64
import json
from pathlib import Path
import sys
from urllib.request import urlretrieve

import cv2
from fastapi.testclient import TestClient

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

import main

DEFAULT_FACE_URL = "https://raw.githubusercontent.com/opencv/opencv/master/samples/data/lena.jpg"
DEFAULT_CROP_FRACTIONS = [0.90, 0.82, 0.75, 0.68, 0.62, 0.56, 0.50, 0.45, 0.40]


def _load_image(path: Path):
    image = cv2.imread(str(path))
    if image is None:
        raise RuntimeError(f"Failed to read image: {path}")
    return image


def _encode_crop_b64(image, fraction: float, output_size: int = 512) -> str:
    h, w = image.shape[:2]
    side = int(min(h, w) * fraction)
    cx, cy = w // 2, h // 2
    x0 = max(0, cx - side // 2)
    y0 = max(0, cy - side // 2)
    x1 = min(w, x0 + side)
    y1 = min(h, y0 + side)

    crop = image[y0:y1, x0:x1]
    if crop.size == 0:
        raise RuntimeError(f"Generated empty crop at fraction={fraction}")

    crop = cv2.resize(crop, (output_size, output_size), interpolation=cv2.INTER_CUBIC)
    ok, buffer = cv2.imencode(".jpg", crop)
    if not ok:
        raise RuntimeError("OpenCV failed to encode crop to JPEG")

    return base64.b64encode(buffer.tobytes()).decode("utf-8")


def run_smoke_test(image_path: Path):
    image = _load_image(image_path)
    client = TestClient(main.app)

    tried = []
    success = None

    for fraction in DEFAULT_CROP_FRACTIONS:
        image_b64 = _encode_crop_b64(image, fraction)
        response = client.post("/api/analyze-skin", json={"imageBytes": image_b64})
        payload = response.json()

        tried.append(
            {
                "crop_fraction": fraction,
                "status_code": response.status_code,
                "detail": payload.get("detail", ""),
            }
        )

        if response.status_code == 200:
            success = (fraction, payload)
            break

    result = {
        "image_path": str(image_path),
        "tried": tried,
        "success": False,
    }

    if success is None:
        return result

    fraction, payload = success
    metric_matrix = payload.get("metric_matrix") or payload.get("metrics", {}).get("metric_matrix", {})
    top = payload.get("metrics") or payload

    keys = [
        "texture_smoothness",
        "pore_visibility",
        "breakout_activity",
        "sebum_excess_oil_gloss",
        "skin_tone_radiance_evenness",
        "localized_redness",
        "diffuse_flushing_erythema",
        "glabellar_11_lines_depth",
        "under_eye_dark_circle_density",
    ]

    result.update(
        {
            "success": True,
            "successful_crop_fraction": fraction,
            "confidence_score": top.get("confidence_score", payload.get("confidence_score")),
            "confidence_hints": top.get("confidence_hints", payload.get("confidence_hints")),
            "image_quality": top.get("image_quality", payload.get("image_quality")),
            "metric_matrix_subset": {k: metric_matrix.get(k) for k in keys},
        }
    )
    return result


def main_cli():
    parser = argparse.ArgumentParser(description="Smoke test /api/analyze-skin with crop sweep")
    parser.add_argument(
        "--image",
        type=Path,
        default=Path("tmp_lena.jpg"),
        help="Path to source face image",
    )
    parser.add_argument(
        "--download-if-missing",
        action="store_true",
        help="Download a default public face image if --image does not exist",
    )
    args = parser.parse_args()

    image_path = args.image
    if not image_path.exists():
        if not args.download_if_missing:
            raise SystemExit(f"Image does not exist: {image_path}")
        urlretrieve(DEFAULT_FACE_URL, str(image_path))

    result = run_smoke_test(image_path)
    print(json.dumps(result, indent=2))

    if not result.get("success"):
        raise SystemExit(1)


if __name__ == "__main__":
    main_cli()
