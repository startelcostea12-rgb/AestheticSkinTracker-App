from __future__ import annotations

import json
from pathlib import Path

import cv2

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "diagnostics" / "opencv_yunet" / "calibration_batch_report.json"
PHOTO_DIR = ROOT / "calibration_stock_batch"
OUT = ROOT / "diagnostics" / "opencv_yunet" / "mediapipe_miss_yunet_hit_overlays"
OUT.mkdir(parents=True, exist_ok=True)

TARGETS = {
    "portrait_05_woman_smile.jpg",
    "portrait_07_man_beard.jpg",
    "portrait_13_man_outdoor.jpg",
    "portrait_14_woman_natural.jpg",
    "portrait_17_woman_older.jpg",
    "portrait_18_man_urban.jpg",
}


def resize_variant(image, label: str):
    if label == "native":
        return image
    size = int(label.split("x", 1)[0])
    h, w = image.shape[:2]
    interp = cv2.INTER_AREA if size < max(h, w) else cv2.INTER_CUBIC
    return cv2.resize(image, (size, size), interpolation=interp)


def main() -> None:
    data = json.loads(REPORT.read_text(encoding="utf-8"))
    written = []
    for row in data["rows"]:
        if row["photo"] not in TARGETS:
            continue
        if row.get("mediapipe_box") is not None or row.get("yunet_box") is None:
            continue
        source = cv2.imread(str(PHOTO_DIR / row["photo"]))
        if source is None:
            continue
        image = resize_variant(source, row["resolution"])
        x0, y0, x1, y1 = [int(round(value)) for value in row["yunet_box"]]
        cv2.rectangle(image, (x0, y0), (x1, y1), (0, 255, 0), 4)
        cv2.putText(
            image,
            f"YuNet {row['yunet_score']} / MediaPipe None",
            (max(0, x0), max(24, y0 - 10)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.8,
            (0, 255, 0),
            2,
            cv2.LINE_AA,
        )
        out_path = OUT / f"{Path(row['photo']).stem}_{row['resolution']}.jpg"
        cv2.imwrite(str(out_path), image)
        written.append(str(out_path))
    print(json.dumps(written, indent=2))


if __name__ == "__main__":
    main()
