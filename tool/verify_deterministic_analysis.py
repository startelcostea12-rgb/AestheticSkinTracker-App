"""Simple deterministic backend check.

Usage:
  python tool/verify_deterministic_analysis.py --image path/to/photo.jpg
"""

import argparse
import base64
import json
from pathlib import Path

import requests


def run_once(endpoint: str, image_path: Path) -> dict:
    payload = {
        "imageBytes": base64.b64encode(image_path.read_bytes()).decode("utf-8"),
        "filename": image_path.name,
    }
    resp = requests.post(endpoint, json=payload, timeout=60)
    resp.raise_for_status()
    data = resp.json()
    if isinstance(data.get("metrics"), dict):
        return data["metrics"]
    return data


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True, help="Path to test image")
    parser.add_argument(
        "--endpoint",
        default="http://127.0.0.1:8000/api/analyze-skin",
        help="Backend analyze endpoint",
    )
    args = parser.parse_args()

    image_path = Path(args.image)
    if not image_path.exists():
        raise SystemExit(f"Image not found: {image_path}")

    m1 = run_once(args.endpoint, image_path)
    m2 = run_once(args.endpoint, image_path)

    same = m1 == m2
    print("Deterministic:", same)
    print("Run #1:")
    print(json.dumps(m1, indent=2, sort_keys=True))
    print("Run #2:")
    print(json.dumps(m2, indent=2, sort_keys=True))

    if not same:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
