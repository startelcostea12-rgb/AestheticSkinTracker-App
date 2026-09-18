from __future__ import annotations

import json
from pathlib import Path
import time

import cv2
import mediapipe as mp
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "diagnostics" / "opencv_yunet" / "face_detection_yunet_2023mar.onnx"
PHOTO_DIR = ROOT / "calibration_stock_batch"
OUT = ROOT / "diagnostics" / "opencv_yunet" / "calibration_batch_report.json"


def resize_variant(image: np.ndarray, label: str) -> np.ndarray:
    if label == "native":
        return image
    size = int(label.split("x", 1)[0])
    h, w = image.shape[:2]
    interpolation = cv2.INTER_AREA if size < max(h, w) else cv2.INTER_CUBIC
    return cv2.resize(image, (size, size), interpolation=interpolation)


def iou(a, b):
    ax0, ay0, ax1, ay1 = a
    bx0, by0, bx1, by1 = b
    ix0, iy0 = max(ax0, bx0), max(ay0, by0)
    ix1, iy1 = min(ax1, bx1), min(ay1, by1)
    inter = max(0.0, ix1 - ix0) * max(0.0, iy1 - iy0)
    area_a = max(0.0, ax1 - ax0) * max(0.0, ay1 - ay0)
    area_b = max(0.0, bx1 - bx0) * max(0.0, by1 - by0)
    return inter / max(area_a + area_b - inter, 1e-9)


def agreement(yunet_box, mp_box, w, h):
    if yunet_box is None or mp_box is None:
        return None
    yx0, yy0, yx1, yy1 = yunet_box
    mx0, my0, mx1, my1 = mp_box
    ycx, ycy = (yx0 + yx1) / 2.0, (yy0 + yy1) / 2.0
    mcx, mcy = (mx0 + mx1) / 2.0, (my0 + my1) / 2.0
    return {
        "iou": round(float(iou(yunet_box, mp_box)), 4),
        "center_delta_px": round(float(((ycx - mcx) ** 2 + (ycy - mcy) ** 2) ** 0.5), 2),
        "center_delta_norm": round(float((((ycx - mcx) / w) ** 2 + ((ycy - mcy) / h) ** 2) ** 0.5), 4),
        "width_ratio_yunet_to_mediapipe": round(float((yx1 - yx0) / max(mx1 - mx0, 1.0)), 4),
        "height_ratio_yunet_to_mediapipe": round(float((yy1 - yy0) / max(my1 - my0, 1.0)), 4),
    }


def yunet_detect(image: np.ndarray):
    h, w = image.shape[:2]
    detector = cv2.FaceDetectorYN_create(str(MODEL), "", (w, h), 0.6, 0.3, 5000)
    start = time.perf_counter()
    _, faces = detector.detect(image)
    elapsed = (time.perf_counter() - start) * 1000.0
    if faces is None or len(faces) == 0:
        return None, elapsed
    face = max(faces, key=lambda row: float(row[2] * row[3]))
    x, y, bw, bh = map(float, face[:4])
    return {
        "box": [round(x, 2), round(y, 2), round(x + bw, 2), round(y + bh, 2)],
        "score": round(float(face[-1]), 4),
    }, elapsed


def mediapipe_detect(image: np.ndarray):
    rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
    detector = mp.solutions.face_mesh.FaceMesh(
        static_image_mode=True,
        max_num_faces=1,
        refine_landmarks=False,
        min_detection_confidence=0.5,
    )
    try:
        start = time.perf_counter()
        result = detector.process(rgb)
        elapsed = (time.perf_counter() - start) * 1000.0
    finally:
        detector.close()
    if not result.multi_face_landmarks:
        return None, elapsed
    points = np.array(
        [[point.x * image.shape[1], point.y * image.shape[0]] for point in result.multi_face_landmarks[0].landmark],
        dtype=np.float32,
    )
    x0, y0 = points.min(axis=0)
    x1, y1 = points.max(axis=0)
    return {
        "box": [round(float(x0), 2), round(float(y0), 2), round(float(x1), 2), round(float(y1), 2)],
    }, elapsed


def main() -> None:
    rows = []
    for path in sorted(PHOTO_DIR.glob("*.jpg")):
        source = cv2.imread(str(path), cv2.IMREAD_COLOR)
        if source is None:
            rows.append({"photo": path.name, "error": "unreadable"})
            continue
        for resolution in ("native", "512x512", "1024x1024"):
            image = resize_variant(source, resolution)
            h, w = image.shape[:2]
            yunet, yunet_ms = yunet_detect(image)
            media, media_ms = mediapipe_detect(image)
            rows.append({
                "photo": path.name,
                "resolution": resolution,
                "image_size": [w, h],
                "yunet_box": None if yunet is None else yunet["box"],
                "yunet_score": None if yunet is None else yunet["score"],
                "mediapipe_box": None if media is None else media["box"],
                "agreement": agreement(None if yunet is None else yunet["box"], None if media is None else media["box"], w, h),
                "latency_ms": {
                    "yunet": round(float(yunet_ms), 2),
                    "mediapipe": round(float(media_ms), 2),
                },
            })
    OUT.write_text(json.dumps({"model": str(MODEL), "rows": rows}, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({"rows": rows}, sort_keys=True))


if __name__ == "__main__":
    main()
