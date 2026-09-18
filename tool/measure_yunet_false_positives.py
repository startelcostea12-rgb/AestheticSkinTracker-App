from __future__ import annotations

import json
from pathlib import Path

import cv2

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "diagnostics" / "opencv_yunet" / "face_detection_yunet_2023mar.onnx"
OUT = ROOT / "diagnostics" / "opencv_yunet" / "false_positive_check"
OUT.mkdir(parents=True, exist_ok=True)

CANDIDATES = [
    ROOT / "stock_body_photo_a.jpg",
    ROOT / "stock_body_photo_b.jpg",
    *[ROOT / f"candidate_body_{i}.jpg" for i in range(1, 8)],
    ROOT / "assets" / "branding" / "splash_swirl_background.png",
    ROOT / "assets" / "branding" / "logo_variations" / "ast_logo_v5_luxe_badge.png",
    ROOT / "web" / "favicon.png",
]


def detect(path: Path):
    image = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if image is None:
        return None, "unreadable"
    h, w = image.shape[:2]
    detector = cv2.FaceDetectorYN_create(str(MODEL), "", (w, h), 0.6, 0.3, 5000)
    _, faces = detector.detect(image)
    if faces is None or len(faces) == 0:
        return [], None
    rows = []
    overlay = image.copy()
    for face in faces:
        x, y, bw, bh = map(float, face[:4])
        box = [round(x, 2), round(y, 2), round(x + bw, 2), round(y + bh, 2)]
        score = round(float(face[-1]), 4)
        rows.append({"box": box, "score": score})
        cv2.rectangle(
            overlay,
            (int(round(x)), int(round(y))),
            (int(round(x + bw)), int(round(y + bh))),
            (0, 255, 0),
            3,
        )
        cv2.putText(
            overlay,
            f"YuNet {score}",
            (max(0, int(round(x))), max(24, int(round(y)) - 8)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.7,
            (0, 255, 0),
            2,
            cv2.LINE_AA,
        )
    out_path = OUT / f"{path.stem}_yunet_detection.jpg"
    cv2.imwrite(str(out_path), overlay)
    return rows, str(out_path)


def main() -> None:
    report = []
    for path in CANDIDATES:
        if not path.exists():
            continue
        detections, artifact = detect(path)
        report.append({
            "photo": str(path.relative_to(ROOT)),
            "detections": detections,
            "artifact": artifact,
        })
    (OUT / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
