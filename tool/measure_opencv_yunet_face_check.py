from __future__ import annotations

import json
from pathlib import Path
import time

import cv2
import mediapipe as mp
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "diagnostics" / "opencv_yunet" / "face_detection_yunet_2023mar.onnx"
PHOTOS = [
    ROOT / "test_fixtures" / "metric_regression" / "clear_face.jfif",
    ROOT / "test_fixtures" / "metric_regression" / "nikki2.jpg",
    ROOT / "test_fixtures" / "metric_regression" / "nikki3.jpg",
    ROOT / "test_fixtures" / "metric_regression" / "st1.jpg",
]


def iou(a, b):
    ax0, ay0, ax1, ay1 = a
    bx0, by0, bx1, by1 = b
    ix0, iy0 = max(ax0, bx0), max(ay0, by0)
    ix1, iy1 = min(ax1, bx1), min(ay1, by1)
    iw, ih = max(0.0, ix1 - ix0), max(0.0, iy1 - iy0)
    inter = iw * ih
    area_a = max(0.0, ax1 - ax0) * max(0.0, ay1 - ay0)
    area_b = max(0.0, bx1 - bx0) * max(0.0, by1 - by0)
    return inter / max(area_a + area_b - inter, 1e-9)


def box_metrics(a, b, w, h):
    ax0, ay0, ax1, ay1 = a
    bx0, by0, bx1, by1 = b
    acx, acy = (ax0 + ax1) / 2, (ay0 + ay1) / 2
    bcx, bcy = (bx0 + bx1) / 2, (by0 + by1) / 2
    return {
        "iou": round(float(iou(a, b)), 4),
        "center_delta_px": round(float(((acx - bcx) ** 2 + (acy - bcy) ** 2) ** 0.5), 2),
        "center_delta_norm": round(float((((acx - bcx) / w) ** 2 + ((acy - bcy) / h) ** 2) ** 0.5), 4),
        "width_ratio_yunet_to_mediapipe": round(float((ax1 - ax0) / max(bx1 - bx0, 1.0)), 4),
        "height_ratio_yunet_to_mediapipe": round(float((ay1 - ay0) / max(by1 - by0, 1.0)), 4),
    }


def yunet_detect(path: Path):
    image = cv2.imread(str(path))
    h, w = image.shape[:2]
    detector = cv2.FaceDetectorYN_create(str(MODEL), "", (w, h), 0.6, 0.3, 5000)
    started = time.perf_counter()
    _, faces = detector.detect(image)
    elapsed = (time.perf_counter() - started) * 1000
    if faces is None or len(faces) == 0:
        return None, elapsed
    face = max(faces, key=lambda row: float(row[2] * row[3]))
    x, y, bw, bh = map(float, face[:4])
    return {
        "box": [round(x, 2), round(y, 2), round(x + bw, 2), round(y + bh, 2)],
        "score": round(float(face[-1]), 4),
    }, elapsed


def mediapipe_detect(path: Path):
    image = cv2.imread(str(path))
    rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
    detector = mp.solutions.face_mesh.FaceMesh(
        static_image_mode=True,
        max_num_faces=1,
        refine_landmarks=False,
        min_detection_confidence=0.5,
    )
    started = time.perf_counter()
    result = detector.process(rgb)
    elapsed = (time.perf_counter() - started) * 1000
    detector.close()
    if not result.multi_face_landmarks:
        return None, elapsed
    pts = np.array(
        [[p.x * image.shape[1], p.y * image.shape[0]] for p in result.multi_face_landmarks[0].landmark],
        dtype=np.float32,
    )
    x0, y0 = pts.min(axis=0)
    x1, y1 = pts.max(axis=0)
    return {"box": [round(float(x0), 2), round(float(y0), 2), round(float(x1), 2), round(float(y1), 2)]}, elapsed


def main():
    report = {"model": str(MODEL), "photos": {}}
    for path in PHOTOS:
        image = cv2.imread(str(path))
        if image is None:
            report["photos"][path.name] = {"error": "unreadable"}
            continue
        h, w = image.shape[:2]
        y_cold, y_cold_ms = yunet_detect(path)
        m_cold, m_cold_ms = mediapipe_detect(path)
        y_warm = []
        m_warm = []
        for _ in range(5):
            _, elapsed = yunet_detect(path)
            y_warm.append(elapsed)
            _, elapsed = mediapipe_detect(path)
            m_warm.append(elapsed)
        entry = {
            "image_size": [w, h],
            "yunet": y_cold,
            "mediapipe_face_mesh_bbox": m_cold,
            "latency_ms": {
                "yunet_cold": round(y_cold_ms, 2),
                "yunet_warm_mean": round(float(np.mean(y_warm[1:])), 2),
                "yunet_warm_each": [round(float(x), 2) for x in y_warm],
                "mediapipe_cold": round(m_cold_ms, 2),
                "mediapipe_warm_mean": round(float(np.mean(m_warm[1:])), 2),
                "mediapipe_warm_each": [round(float(x), 2) for x in m_warm],
            },
        }
        if y_cold and m_cold:
            entry["agreement"] = box_metrics(y_cold["box"], m_cold["box"], w, h)
        report["photos"][path.name] = entry
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
