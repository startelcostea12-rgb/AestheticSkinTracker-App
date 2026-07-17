import hashlib
import math
import os
import random
import threading
from typing import Any, Dict, Tuple

import cv2
import numpy as np

try:
    import mediapipe as mp
except Exception:  # pragma: no cover
    mp = None

try:
    from ultralytics import YOLO
except Exception:  # pragma: no cover
    YOLO = None

cv2.setNumThreads(1)
cv2.ocl.setUseOpenCL(False)

_PIPELINE_LOCK = threading.Lock()
_PIPELINE_READY = False
_PIPELINE_ERROR = ""
_FACE_MESH = None
_YOLO = None


def _seed_everything() -> None:
    random.seed(0)
    np.random.seed(0)
    try:
        import torch

        torch.manual_seed(0)
        torch.set_num_threads(1)
        torch.set_num_interop_threads(1)
        torch.use_deterministic_algorithms(True)
    except Exception:
        # Torch is optional for this module path.
        pass


def ensure_pipeline_ready() -> Dict[str, str]:
    global _PIPELINE_READY, _PIPELINE_ERROR, _FACE_MESH, _YOLO

    with _PIPELINE_LOCK:
        if _PIPELINE_READY:
            return {"status": "ready"}
        if _PIPELINE_ERROR:
            raise RuntimeError(_PIPELINE_ERROR)

        _seed_everything()

        if mp is None:
            _PIPELINE_ERROR = (
                "MediaPipe is not installed. Install with 'pip install mediapipe' "
                "and restart backend."
            )
            raise RuntimeError(_PIPELINE_ERROR)

        if YOLO is None:
            _PIPELINE_ERROR = (
                "Ultralytics YOLO is not installed. Install with 'pip install ultralytics' "
                "and restart backend."
            )
            raise RuntimeError(_PIPELINE_ERROR)

        model_path = os.getenv("SKIN_YOLO_MODEL_PATH", "assets/models/best.pt")
        if not os.path.exists(model_path):
            _PIPELINE_ERROR = (
                f"YOLO model file not found at '{model_path}'. "
                "Set SKIN_YOLO_MODEL_PATH or add assets/models/best.pt."
            )
            raise RuntimeError(_PIPELINE_ERROR)

        try:
            _FACE_MESH = mp.solutions.face_mesh.FaceMesh(
                static_image_mode=True,
                max_num_faces=1,
                refine_landmarks=False,
                min_detection_confidence=0.5,
            )
            _YOLO = YOLO(model_path)
            _PIPELINE_READY = True
            return {"status": "ready"}
        except Exception as exc:
            _PIPELINE_ERROR = f"Analysis pipeline failed to initialize: {exc}"
            raise RuntimeError(_PIPELINE_ERROR)


def _gray_world_white_balance(bgr: np.ndarray) -> np.ndarray:
    bgr_f = bgr.astype(np.float32) + 1.0
    means = bgr_f.reshape(-1, 3).mean(axis=0)
    gray = float(np.mean(means))
    gains = gray / means
    balanced = np.clip(bgr_f * gains, 0, 255).astype(np.uint8)
    return balanced


def normalize_lighting_and_shadows(bgr_image: np.ndarray) -> np.ndarray:
    balanced = _gray_world_white_balance(bgr_image)
    lab = cv2.cvtColor(balanced, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    l = clahe.apply(l)
    merged = cv2.merge((l, a, b))
    return cv2.cvtColor(merged, cv2.COLOR_LAB2BGR)


def _landmarks_to_points(landmarks, width: int, height: int) -> np.ndarray:
    pts = []
    for lm in landmarks.landmark:
        pts.append((lm.x * width, lm.y * height))
    return np.array(pts, dtype=np.float32)


def _align_and_crop_face(bgr: np.ndarray, points: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    # Eye centers for deterministic alignment.
    left_eye = np.mean(points[[33, 133]], axis=0)
    right_eye = np.mean(points[[362, 263]], axis=0)

    dy = float(right_eye[1] - left_eye[1])
    dx = float(right_eye[0] - left_eye[0])
    angle = math.degrees(math.atan2(dy, dx))

    center = tuple(np.mean([left_eye, right_eye], axis=0))
    rot = cv2.getRotationMatrix2D(center, angle, 1.0)

    h, w = bgr.shape[:2]
    aligned = cv2.warpAffine(
        bgr,
        rot,
        (w, h),
        flags=cv2.INTER_LINEAR,
        borderMode=cv2.BORDER_REFLECT,
    )

    pts_h = np.hstack([points, np.ones((points.shape[0], 1), dtype=np.float32)])
    aligned_points = (rot @ pts_h.T).T

    min_xy = aligned_points.min(axis=0)
    max_xy = aligned_points.max(axis=0)
    face_w = max_xy[0] - min_xy[0]
    face_h = max_xy[1] - min_xy[1]

    pad_x = face_w * 0.22
    pad_y = face_h * 0.28

    x0 = int(max(0, min_xy[0] - pad_x))
    y0 = int(max(0, min_xy[1] - pad_y))
    x1 = int(min(w, max_xy[0] + pad_x))
    y1 = int(min(h, max_xy[1] + pad_y))

    if x1 <= x0 or y1 <= y0:
        raise ValueError("Face crop failed due to invalid bounds")

    crop = aligned[y0:y1, x0:x1]
    crop = cv2.resize(crop, (512, 512), interpolation=cv2.INTER_LINEAR)
    return crop, aligned_points


def _skin_mask(bgr: np.ndarray) -> np.ndarray:
    ycrcb = cv2.cvtColor(bgr, cv2.COLOR_BGR2YCrCb)
    lower = np.array([0, 133, 77], dtype=np.uint8)
    upper = np.array([255, 173, 127], dtype=np.uint8)
    mask = cv2.inRange(ycrcb, lower, upper)

    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)
    return mask


def _region_masks(shape: Tuple[int, int], skin_mask: np.ndarray) -> Dict[str, np.ndarray]:
    h, w = shape
    region = {
        "forehead": np.zeros((h, w), dtype=np.uint8),
        "left_cheek": np.zeros((h, w), dtype=np.uint8),
        "right_cheek": np.zeros((h, w), dtype=np.uint8),
    }

    region["forehead"][int(h * 0.12) : int(h * 0.34), int(w * 0.25) : int(w * 0.75)] = 255
    region["left_cheek"][int(h * 0.38) : int(h * 0.72), int(w * 0.08) : int(w * 0.42)] = 255
    region["right_cheek"][int(h * 0.38) : int(h * 0.72), int(w * 0.58) : int(w * 0.92)] = 255

    for key in list(region.keys()):
        region[key] = cv2.bitwise_and(region[key], skin_mask)
    return region


def _percentile(channel: np.ndarray, mask: np.ndarray, p: float) -> float:
    vals = channel[mask > 0]
    if vals.size == 0:
        return 0.0
    return float(np.percentile(vals, p))


def _score_from_signal(signal: float, offset: float, gain: float) -> float:
    return float(np.clip((signal - offset) * gain, 0.0, 100.0))


def _run_yolo_lesion_count(bgr_face: np.ndarray) -> int:
    if _YOLO is None:
        return 0
    try:
        res = _YOLO.predict(
            source=bgr_face,
            imgsz=640,
            conf=0.25,
            iou=0.5,
            device="cpu",
            verbose=False,
        )
        if not res:
            return 0
        boxes = getattr(res[0], "boxes", None)
        if boxes is None:
            return 0
        return int(len(boxes))
    except Exception:
        return 0


def analyze_skin_patch(bgr_image: np.ndarray) -> Dict[str, Any]:
    try:
        ensure_pipeline_ready()

        rgb = cv2.cvtColor(bgr_image, cv2.COLOR_BGR2RGB)
        mesh_res = _FACE_MESH.process(rgb)
        if not mesh_res.multi_face_landmarks:
            raise RuntimeError(
                "No face detected by MediaPipe Face Mesh. Use a front-facing, well-lit image "
                "with full face visible."
            )

        points = _landmarks_to_points(
            mesh_res.multi_face_landmarks[0],
            bgr_image.shape[1],
            bgr_image.shape[0],
        )

        aligned_face, _ = _align_and_crop_face(bgr_image, points)
        norm = normalize_lighting_and_shadows(aligned_face)
        mask = _skin_mask(norm)
        regions = _region_masks(norm.shape[:2], mask)

        lab = cv2.cvtColor(norm, cv2.COLOR_BGR2LAB)
        gray = cv2.cvtColor(norm, cv2.COLOR_BGR2GRAY)

        # Redness map: robustly compare high-tail a* against median skin a*.
        a_channel = lab[:, :, 1].astype(np.float32)
        median_a = _percentile(a_channel, mask, 50)
        p90_a = _percentile(
            a_channel,
            cv2.bitwise_or(regions["left_cheek"], regions["right_cheek"]),
            90,
        )
        redness_signal = max(0.0, p90_a - median_a)
        redness_score = _score_from_signal(redness_signal, offset=2.0, gain=4.2)

        # Texture/wrinkle: robust high-percentile Laplacian energy on skin.
        lap = cv2.Laplacian(gray, cv2.CV_32F, ksize=3)
        lap_abs = np.abs(lap)
        texture_signal = _percentile(lap_abs, mask, 75)
        wrinkle_signal = _percentile(lap_abs, regions["forehead"], 85)
        texture_score = _score_from_signal(texture_signal, offset=8.0, gain=2.4)
        wrinkle_score = _score_from_signal(wrinkle_signal, offset=9.0, gain=2.2)

        # Visible vessel signal: red-green contrast with blackhat emphasizing thin lines.
        red_green = cv2.subtract(norm[:, :, 2], norm[:, :, 1])
        bh = cv2.morphologyEx(
            red_green,
            cv2.MORPH_BLACKHAT,
            cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9)),
        )
        vessel_signal = _percentile(bh.astype(np.float32), mask, 95)
        visible_vessels_score = _score_from_signal(vessel_signal, offset=10.0, gain=2.0)

        # Hydration/pigmentation remain deterministic and conservative.
        l_channel = lab[:, :, 0].astype(np.float32)
        hydration_signal = _percentile(l_channel, regions["forehead"], 50)
        hydration_score = float(np.clip((hydration_signal - 95.0) * 1.2, 0.0, 100.0))

        b_channel = lab[:, :, 2].astype(np.float32)
        pig_signal = _percentile(np.abs(b_channel - _percentile(b_channel, mask, 50)), mask, 85)
        pigmentation_score = _score_from_signal(pig_signal, offset=6.0, gain=2.4)

        dog = cv2.GaussianBlur(gray, (0, 0), 1.2) - cv2.GaussianBlur(gray, (0, 0), 3.0)
        cheek_mask = cv2.bitwise_or(regions["left_cheek"], regions["right_cheek"])
        dog_thr = _percentile(dog.astype(np.float32), cheek_mask, 97)
        pore_count = int(np.sum((dog > dog_thr) & (cheek_mask > 0)))

        lesion_count = _run_yolo_lesion_count(norm)
        acne_activity_score = float(np.clip(lesion_count * 5.0, 0.0, 100.0))

        severity = 0.32 * redness_score + 0.22 * texture_score + 0.2 * visible_vessels_score + 0.16 * wrinkle_score + 0.1 * acne_activity_score
        overall_skin_score = float(np.clip(100.0 - severity, 0.0, 100.0))

        fingerprint = hashlib.sha256(norm.tobytes()).hexdigest()

        return {
            "redness_score": round(redness_score, 2),
            "visible_vessels_score": round(visible_vessels_score, 2),
            "smoothness_score": round(max(0.0, 100.0 - texture_score), 2),
            "texture_score": round(texture_score, 2),
            "hydration_score": round(hydration_score, 2),
            "wrinkle_score": round(wrinkle_score, 2),
            "pigmentation_score": round(pigmentation_score, 2),
            "acne_activity_score": round(acne_activity_score, 2),
            "overall_skin_score": round(overall_skin_score, 2),
            "pore_count": pore_count,
            "lesion_count": lesion_count,
            "fingerprint": fingerprint,
        }
    except Exception as e:
        return {"error": str(e)}


def compute_deterministic_metrics(cropped_bgr_image: np.ndarray) -> Dict[str, Any]:
    return analyze_skin_patch(cropped_bgr_image)
