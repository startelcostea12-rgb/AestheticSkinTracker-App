import hashlib
import base64
import json
import logging
import math
import os
import random
import traceback
import threading
from contextlib import asynccontextmanager
from typing import Any, Dict, Tuple

import cv2
import numpy as np
import uvicorn
from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from google import genai

try:
    import mediapipe as mp
except Exception:
    mp = None

try:
    from ultralytics import YOLO
except Exception:
    YOLO = None

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

cv2.setNumThreads(1)
cv2.ocl.setUseOpenCL(False)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODELS_DIR = os.path.abspath(os.path.join(BASE_DIR, "assets", "models"))

_PIPELINE_LOCK = threading.Lock()
_PIPELINE_READY = False
_PIPELINE_ERROR = ""
_FACE_MESH = None
_YOLO = None


class ModelAssetManager:
    def __init__(self, models_dir: str):
        self.models_dir = os.path.abspath(models_dir)

    def ensure_models_dir(self) -> str:
        os.makedirs(self.models_dir, exist_ok=True)
        logger.info("Model asset directory: %s", self.models_dir)
        return self.models_dir

    def resolve_asset(self, candidates: list[str], *, explicit_path: str | None = None) -> str | None:
        search_paths: list[str] = []

        if explicit_path:
            if os.path.isabs(explicit_path):
                search_paths.append(os.path.abspath(explicit_path))
            else:
                search_paths.append(os.path.abspath(os.path.join(self.models_dir, explicit_path)))

        for name in candidates:
            if os.path.isabs(name):
                search_paths.append(os.path.abspath(name))
            else:
                search_paths.append(os.path.abspath(os.path.join(self.models_dir, name)))

        logger.info("Searching model assets: %s", " | ".join(search_paths))

        for path in search_paths:
            if os.path.exists(path):
                logger.info("Resolved model asset: %s", path)
                return path
        return None

    def require_asset(self, path: str | None, *, required_name: str, purpose: str, download_hint: str) -> str:
        if path and os.path.exists(path):
            return os.path.abspath(path)

        raise RuntimeError(
            f"Missing required model asset '{required_name}' for {purpose}. "
            f"Expected under '{self.models_dir}'. {download_hint}"
        )


_ASSETS = ModelAssetManager(MODELS_DIR)


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
        pass


def ensure_pipeline_ready() -> Dict[str, str]:
    global _PIPELINE_READY, _PIPELINE_ERROR, _FACE_MESH, _YOLO
    with _PIPELINE_LOCK:
        if _PIPELINE_READY:
            return {"status": "ready"}
        if _PIPELINE_ERROR:
            raise RuntimeError(_PIPELINE_ERROR)

        _seed_everything()
        _ASSETS.ensure_models_dir()

        if mp is None:
            _PIPELINE_ERROR = "MediaPipe is not installed. Run 'pip install mediapipe'."
            raise RuntimeError(_PIPELINE_ERROR)
        if YOLO is None:
            _PIPELINE_ERROR = "Ultralytics YOLO is not installed. Run 'pip install ultralytics'."
            raise RuntimeError(_PIPELINE_ERROR)

        yolo_candidates = ["best.pt", "skin_yolo.pt", "yolov8n.pt"]
        yolo_explicit = os.getenv("SKIN_YOLO_MODEL_PATH", "").strip() or None
        yolo_path = _ASSETS.resolve_asset(yolo_candidates, explicit_path=yolo_explicit)
        yolo_path = _ASSETS.require_asset(
            yolo_path,
            required_name="best.pt",
            purpose="YOLO lesion detection",
            download_hint=(
                "Place your YOLO weights file (for example 'best.pt') in assets/models/ "
                "or set SKIN_YOLO_MODEL_PATH to an absolute file path."
            ),
        )

        # MediaPipe Face Mesh (solutions API) does not require a local .task file,
        # but we still probe the model directory and provide explicit diagnostics for
        # teams migrating to task-based landmarker runtimes.
        mp_task_candidates = [
            "face_landmarker.task",
            "face_landmarker_v2_with_blendshapes.task",
        ]
        mp_task_explicit = os.getenv("MEDIAPIPE_FACE_TASK_PATH", "").strip() or None
        mp_task_path = _ASSETS.resolve_asset(mp_task_candidates, explicit_path=mp_task_explicit)
        if mp_task_path is None:
            logger.warning(
                "Optional MediaPipe task asset not found. If you use task-based Face Landmarker, "
                "place 'face_landmarker.task' in '%s' or set MEDIAPIPE_FACE_TASK_PATH.",
                MODELS_DIR,
            )

        try:
            _FACE_MESH = mp.solutions.face_mesh.FaceMesh(
                static_image_mode=True,
                max_num_faces=1,
                refine_landmarks=False,
                min_detection_confidence=0.5,
            )
            _YOLO = YOLO(yolo_path)
            logger.info("Loaded YOLO weights from: %s", yolo_path)
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
    return np.clip(bgr_f * gains, 0, 255).astype(np.uint8)


def normalize_lighting_and_shadows(bgr_image: np.ndarray) -> np.ndarray:
    balanced = _gray_world_white_balance(bgr_image)
    lab = cv2.cvtColor(balanced, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    l = clahe.apply(l)
    merged = cv2.merge((l, a, b))
    return cv2.cvtColor(merged, cv2.COLOR_LAB2BGR)


def _margin_mask(shape: Tuple[int, int], margin_ratio: float = 0.12) -> np.ndarray:
    h, w = shape
    margin_y = max(1, int(h * margin_ratio))
    margin_x = max(1, int(w * margin_ratio))
    mask = np.zeros((h, w), dtype=np.uint8)
    mask[:margin_y, :] = 255
    mask[h - margin_y :, :] = 255
    mask[:, :margin_x] = 255
    mask[:, w - margin_x :] = 255
    return mask


def apply_white_balance_calibration(image: np.ndarray) -> Tuple[np.ndarray, Dict[str, Any]]:
    """Normalizes capture white balance using a bright neutral object on the image margins.

    The detector looks only at the outer frame so it can use a calibration card,
    paper edge, or other white reference without biasing against the face ROI.
    When a valid neutral patch is found, a clipped RGB gain correction plus a small
    LAB neutral-axis correction is applied across the full image.
    """
    if image is None or image.size == 0:
        return image, {
            "reference_found": False,
            "reason": "empty_image",
        }

    h, w = image.shape[:2]
    margin = _margin_mask((h, w))
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
    l_channel = lab[:, :, 0]
    a_channel = lab[:, :, 1].astype(np.float32)
    b_channel = lab[:, :, 2].astype(np.float32)

    margin_pixels = margin > 0
    bright_floor = float(np.percentile(l_channel[margin_pixels], 82)) if np.any(margin_pixels) else 215.0
    chroma_distance = np.sqrt((a_channel - 128.0) ** 2 + (b_channel - 128.0) ** 2)
    candidates = np.logical_and.reduce(
        [
            margin_pixels,
            l_channel >= bright_floor,
            chroma_distance <= 18.0,
        ]
    ).astype(np.uint8) * 255

    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
    candidates = cv2.morphologyEx(candidates, cv2.MORPH_OPEN, kernel)
    candidates = cv2.morphologyEx(candidates, cv2.MORPH_CLOSE, kernel)

    contours, _ = cv2.findContours(candidates, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return image.copy(), {
            "reference_found": False,
            "reason": "no_margin_reference",
        }

    contour = max(contours, key=cv2.contourArea)
    contour_area = float(cv2.contourArea(contour))
    minimum_area = max(250.0, float(h * w) * 0.002)
    if contour_area < minimum_area:
        return image.copy(), {
            "reference_found": False,
            "reason": "reference_too_small",
            "detected_area": round(contour_area, 2),
            "minimum_area": round(minimum_area, 2),
        }

    reference_mask = np.zeros((h, w), dtype=np.uint8)
    cv2.drawContours(reference_mask, [contour], -1, 255, thickness=cv2.FILLED)
    reference_pixels = reference_mask > 0
    if not np.any(reference_pixels):
        return image.copy(), {
            "reference_found": False,
            "reason": "reference_mask_empty",
        }

    ref_bgr = image[reference_pixels].astype(np.float32)
    ref_bgr_mean = ref_bgr.mean(axis=0)
    rgb_gains = np.clip(245.0 / np.maximum(ref_bgr_mean, 1.0), 0.82, 1.18)
    rgb_corrected = np.clip(image.astype(np.float32) * rgb_gains.reshape(1, 1, 3), 0, 255).astype(np.uint8)

    corrected_lab = cv2.cvtColor(rgb_corrected, cv2.COLOR_BGR2LAB).astype(np.float32)
    reference_lab = corrected_lab[reference_pixels]
    lab_shift = np.array(
        [
            np.clip(245.0 - float(reference_lab[:, 0].mean()), -12.0, 12.0),
            np.clip(128.0 - float(reference_lab[:, 1].mean()), -10.0, 10.0),
            np.clip(128.0 - float(reference_lab[:, 2].mean()), -10.0, 10.0),
        ],
        dtype=np.float32,
    )
    corrected_lab[:, :, 0] = np.clip(corrected_lab[:, :, 0] + lab_shift[0], 0, 255)
    corrected_lab[:, :, 1] = np.clip(corrected_lab[:, :, 1] + lab_shift[1], 0, 255)
    corrected_lab[:, :, 2] = np.clip(corrected_lab[:, :, 2] + lab_shift[2], 0, 255)
    calibrated = cv2.cvtColor(corrected_lab.astype(np.uint8), cv2.COLOR_LAB2BGR)

    x, y, bw, bh = cv2.boundingRect(contour)
    return calibrated, {
        "reference_found": True,
        "reference_bbox": [int(x), int(y), int(bw), int(bh)],
        "reference_area_ratio": round(contour_area / max(float(h * w), 1.0), 5),
        "rgb_gains_bgr": [round(float(v), 4) for v in rgb_gains.tolist()],
        "lab_shift": [round(float(v), 4) for v in lab_shift.tolist()],
    }


def _landmarks_to_points(landmarks, width: int, height: int) -> np.ndarray:
    return np.array([(lm.x * width, lm.y * height) for lm in landmarks.landmark], dtype=np.float32)


def _align_and_crop_face(bgr: np.ndarray, points: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    left_eye = np.mean(points[[33, 133]], axis=0)
    right_eye = np.mean(points[[362, 263]], axis=0)
    dy = float(right_eye[1] - left_eye[1])
    dx = float(right_eye[0] - left_eye[0])
    angle = math.degrees(math.atan2(dy, dx))
    center = tuple(np.mean([left_eye, right_eye], axis=0))
    rot = cv2.getRotationMatrix2D(center, angle, 1.0)
    h, w = bgr.shape[:2]
    aligned = cv2.warpAffine(bgr, rot, (w, h), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT)
    pts_h = np.hstack([points, np.ones((points.shape[0], 1), dtype=np.float32)])
    aligned_points = (rot @ pts_h.T).T
    min_xy, max_xy = aligned_points.min(axis=0), aligned_points.max(axis=0)
    face_w, face_h = max_xy[0] - min_xy[0], max_xy[1] - min_xy[1]
    pad_x, pad_y = face_w * 0.22, face_h * 0.28
    x0, y0 = int(max(0, min_xy[0] - pad_x)), int(max(0, min_xy[1] - pad_y))
    x1, y1 = int(min(w, max_xy[0] + pad_x)), int(min(h, max_xy[1] + pad_y))
    if x1 <= x0 or y1 <= y0:
        raise ValueError("Face crop failed due to invalid bounds")
    crop = cv2.resize(aligned[y0:y1, x0:x1], (512, 512), interpolation=cv2.INTER_LINEAR)
    return crop, aligned_points


def _skin_mask(bgr: np.ndarray) -> np.ndarray:
    ycrcb = cv2.cvtColor(bgr, cv2.COLOR_BGR2YCrCb)
    mask = cv2.inRange(ycrcb, np.array([0, 133, 77], dtype=np.uint8), np.array([255, 173, 127], dtype=np.uint8))
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    return cv2.morphologyEx(cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel), cv2.MORPH_CLOSE, kernel)


def _polygon_mask(shape: Tuple[int, int], polygon: np.ndarray) -> np.ndarray:
    h, w = shape
    out = np.zeros((h, w), dtype=np.uint8)
    if polygon.size < 6:
        return out
    poly = polygon.copy()
    poly[:, 0] = np.clip(poly[:, 0], 0, w - 1)
    poly[:, 1] = np.clip(poly[:, 1], 0, h - 1)
    cv2.fillPoly(out, [poly.astype(np.int32)], 255)
    return out


def _project_hairline_points(points: np.ndarray, brow_ids: list[int], anchor_id: int = 168) -> np.ndarray:
    anchor = points[anchor_id]
    projected = []
    for idx in brow_ids:
        p = points[idx]
        v = p - anchor
        hp = p + (v * 0.65)
        projected.append(hp)
    return np.array(projected, dtype=np.float32)


def _region_masks(shape: Tuple[int, int], skin_mask: np.ndarray, points: np.ndarray) -> Dict[str, np.ndarray]:
    h, w = shape
    region = {
        "forehead": np.zeros((h, w), dtype=np.uint8),
        "left_cheek": np.zeros((h, w), dtype=np.uint8),
        "right_cheek": np.zeros((h, w), dtype=np.uint8),
    }

    # Forehead: upper brow chain plus projected "hairline" band.
    brow_ids = [70, 63, 105, 66, 107, 300, 293, 334, 296, 336]
    brow = points[brow_ids]
    hairline = _project_hairline_points(points, brow_ids)
    forehead_poly = np.vstack([brow, hairline[::-1]])
    region["forehead"] = _polygon_mask((h, w), forehead_poly)

    # Cheeks: bounded by outer eye corners, nose wings, and lateral ear/tragus landmarks.
    left_cheek_ids = [33, 130, 205, 50, 234, 132, 172, 136, 98]
    right_cheek_ids = [263, 359, 425, 280, 454, 361, 397, 365, 327]
    region["left_cheek"] = _polygon_mask((h, w), points[left_cheek_ids])
    region["right_cheek"] = _polygon_mask((h, w), points[right_cheek_ids])

    for key in region.keys():
        region[key] = cv2.bitwise_and(region[key], skin_mask)
    return region


def _nose_region_mask(shape: Tuple[int, int], points: np.ndarray, skin_mask: np.ndarray) -> np.ndarray:
    # Central nose bridge/tip polygon used for T-zone and diffuse flushing analysis.
    ids = [168, 6, 197, 195, 5, 4, 1, 2, 98, 327]
    valid_ids = [idx for idx in ids if 0 <= idx < points.shape[0]]
    if len(valid_ids) < 3:
        return np.zeros(shape, dtype=np.uint8)
    mask = _polygon_mask(shape, points[valid_ids])
    return cv2.bitwise_and(mask, skin_mask)


def _glabella_region_mask(shape: Tuple[int, int], points: np.ndarray, skin_mask: np.ndarray) -> np.ndarray:
    # Region between brows and upper nasal root for "11" line estimation.
    ids = [55, 65, 52, 168, 8, 417, 285, 295, 282]
    valid_ids = [idx for idx in ids if 0 <= idx < points.shape[0]]
    if len(valid_ids) < 3:
        return np.zeros(shape, dtype=np.uint8)
    glabella = _polygon_mask(shape, points[valid_ids])
    return cv2.bitwise_and(glabella, skin_mask)


def _compute_additional_opencv_metrics(
    face_bgr: np.ndarray,
    skin_mask: np.ndarray,
    regions: Dict[str, np.ndarray],
    points: np.ndarray,
) -> Dict[str, float]:
    h, w = face_bgr.shape[:2]
    if h == 0 or w == 0:
        return {
            "sebum_excess_oil_gloss": 0.0,
            "diffuse_flushing_erythema": 0.0,
            "skin_tone_radiance_evenness": 0.0,
        }

    skin_area = max(int(cv2.countNonZero(skin_mask)), 1)
    hsv = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2HSV)
    lab = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2LAB)
    gray = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2GRAY)

    hue = hsv[:, :, 0]
    sat = hsv[:, :, 1]
    val = hsv[:, :, 2]

    # 1) Sebum / Excess Oil Gloss (defect)
    forehead = regions.get("forehead", np.zeros((h, w), dtype=np.uint8))
    nose = _nose_region_mask((h, w), points, skin_mask)
    t_zone = cv2.bitwise_or(forehead, nose)
    t_zone = cv2.bitwise_and(t_zone, skin_mask)
    if cv2.countNonZero(t_zone) == 0:
        t_zone = skin_mask

    t_zone_pixels = val[t_zone > 0]
    v_threshold = 220.0
    if t_zone_pixels.size > 0:
        v_threshold = max(220.0, float(np.percentile(t_zone_pixels, 95)))

    specular_mask = np.logical_and.reduce(
        [
            t_zone > 0,
            val >= v_threshold,
            sat <= 70,
        ]
    ).astype(np.uint8) * 255
    small_kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    specular_mask = cv2.morphologyEx(specular_mask, cv2.MORPH_OPEN, small_kernel)
    specular_mask = cv2.morphologyEx(specular_mask, cv2.MORPH_CLOSE, small_kernel)
    sebum_gloss_pct = (float(cv2.countNonZero(specular_mask)) / max(float(cv2.countNonZero(t_zone)), 1.0)) * 100.0

    # 2) Diffuse Flushing / Erythema (defect)
    left_cheek = regions.get("left_cheek", np.zeros((h, w), dtype=np.uint8))
    right_cheek = regions.get("right_cheek", np.zeros((h, w), dtype=np.uint8))
    flush_roi = cv2.bitwise_or(cv2.bitwise_or(left_cheek, right_cheek), nose)
    flush_roi = cv2.bitwise_and(flush_roi, skin_mask)
    flush_area = max(int(cv2.countNonZero(flush_roi)), 1)

    a_channel = lab[:, :, 1].astype(np.float32)
    a_blur = cv2.GaussianBlur(a_channel, (0, 0), sigmaX=3.0)
    roi_values = a_blur[flush_roi > 0]
    median_a = float(np.percentile(roi_values, 50)) if roi_values.size > 0 else 128.0
    red_threshold = max(138.0, median_a + 6.0)

    red_binary = np.logical_and(flush_roi > 0, a_blur >= red_threshold).astype(np.uint8)
    red_binary = cv2.morphologyEx(red_binary * 255, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7)))

    num_labels, labels, stats, _ = cv2.connectedComponentsWithStats((red_binary > 0).astype(np.uint8), connectivity=8)
    diffuse_mask = np.zeros((h, w), dtype=np.uint8)
    min_component_area = max(20, int(flush_area * 0.0025))
    for label_id in range(1, num_labels):
        area = int(stats[label_id, cv2.CC_STAT_AREA])
        if area < min_component_area:
            continue
        diffuse_mask[labels == label_id] = 255

    diffuse_density = (float(cv2.countNonZero(diffuse_mask)) / max(float(flush_area), 1.0)) * 100.0
    diffuse_pixels = a_blur[diffuse_mask > 0]
    if diffuse_pixels.size > 0:
        normalized_excess = np.clip((diffuse_pixels - red_threshold) / max(170.0 - red_threshold, 1.0), 0.0, 1.0)
        diffuse_intensity = float(np.mean(normalized_excess) * 100.0)
    else:
        diffuse_intensity = 0.0
    diffuse_flushing_score = (0.65 * diffuse_density) + (0.35 * diffuse_intensity)

    # 3) Skin Tone Radiance & Evenness (benefit)
    healthy_skin = skin_mask > 0
    red_lesion_like = np.logical_and.reduce(
        [
            healthy_skin,
            np.logical_or(hue <= 12, hue >= 170),
            sat >= 90,
            val >= 60,
        ]
    )
    lap_abs = np.abs(cv2.Laplacian(gray, cv2.CV_32F, ksize=3))
    healthy_lap = lap_abs[healthy_skin]
    texture_threshold = float(np.percentile(healthy_lap, 90)) if healthy_lap.size > 0 else 9999.0
    high_texture = np.logical_and(healthy_skin, lap_abs >= texture_threshold)
    specular_bool = specular_mask > 0

    refined_healthy = np.logical_and(healthy_skin, ~red_lesion_like)
    refined_healthy = np.logical_and(refined_healthy, ~high_texture)
    refined_healthy = np.logical_and(refined_healthy, ~specular_bool)
    if int(np.count_nonzero(refined_healthy)) < max(250, int(skin_area * 0.08)):
        refined_healthy = healthy_skin

    l_channel = lab[:, :, 0].astype(np.float32)
    b_channel = lab[:, :, 2].astype(np.float32)
    l_std = float(np.std(l_channel[refined_healthy])) if np.count_nonzero(refined_healthy) > 0 else 0.0
    a_std = float(np.std(a_channel[refined_healthy])) if np.count_nonzero(refined_healthy) > 0 else 0.0
    b_std = float(np.std(b_channel[refined_healthy])) if np.count_nonzero(refined_healthy) > 0 else 0.0
    composite_variance = (0.50 * l_std) + (0.30 * a_std) + (0.20 * b_std)
    radiance_evenness_score = 100.0 * math.exp(-composite_variance / 24.0)

    return {
        "sebum_excess_oil_gloss": round(float(np.clip(sebum_gloss_pct, 0.0, 100.0)), 1),
        "diffuse_flushing_erythema": round(float(np.clip(diffuse_flushing_score, 0.0, 100.0)), 1),
        "skin_tone_radiance_evenness": round(float(np.clip(radiance_evenness_score, 0.0, 100.0)), 1),
    }


def _compute_structural_opencv_metrics(
    face_bgr: np.ndarray,
    skin_mask: np.ndarray,
    regions: Dict[str, np.ndarray],
    points: np.ndarray,
) -> Dict[str, float]:
    h, w = face_bgr.shape[:2]
    if h == 0 or w == 0:
        return {
            "glabellar_wrinkle_depth": 0.0,
            "pore_contraction_index": 0.0,
            "structural_firmness_elasticity": 0.0,
        }

    gray = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2GRAY)

    # 1) Glabellar "11" lines & wrinkle depth (defect)
    glabella_mask = _glabella_region_mask((h, w), points, skin_mask)
    glabella_area = max(int(cv2.countNonZero(glabella_mask)), 1)

    if glabella_area > 0:
        glabella_gray = cv2.GaussianBlur(gray, (5, 5), 0)
        # Directional Hessian approximation emphasizing vertical furrows.
        dxx = cv2.Sobel(glabella_gray, cv2.CV_32F, 2, 0, ksize=3)
        dyy = cv2.Sobel(glabella_gray, cv2.CV_32F, 0, 2, ksize=3)
        vertical_response = np.clip(np.abs(dxx) - (0.35 * np.abs(dyy)), 0.0, None)

        response_values = vertical_response[glabella_mask > 0]
        threshold = float(np.percentile(response_values, 82)) if response_values.size > 0 else 9999.0
        wrinkle_binary = np.logical_and(glabella_mask > 0, vertical_response >= threshold).astype(np.uint8) * 255
        wrinkle_binary = cv2.morphologyEx(
            wrinkle_binary,
            cv2.MORPH_OPEN,
            cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 5)),
        )

        contours, _ = cv2.findContours(wrinkle_binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        widths: list[float] = []
        intensities: list[float] = []
        min_component_area = max(8, int(glabella_area * 0.0012))
        for contour in contours:
            area = float(cv2.contourArea(contour))
            if area < min_component_area:
                continue
            x, y, bw, bh = cv2.boundingRect(contour)
            widths.append(float(bw))
            roi = vertical_response[y : y + bh, x : x + bw]
            if roi.size > 0:
                intensities.append(float(np.mean(roi)))

        wrinkle_density = (float(cv2.countNonZero(wrinkle_binary)) / max(float(glabella_area), 1.0)) * 100.0
        avg_width = float(np.mean(widths)) if widths else 0.0
        avg_intensity = float(np.mean(intensities)) if intensities else 0.0
        width_norm = np.clip((avg_width / 12.0) * 100.0, 0.0, 100.0)
        intensity_norm = np.clip((avg_intensity / 28.0) * 100.0, 0.0, 100.0)
        glabellar_wrinkle_depth = (0.50 * wrinkle_density) + (0.30 * width_norm) + (0.20 * intensity_norm)
    else:
        glabellar_wrinkle_depth = 0.0

    # 2) Pore contraction index (defect): average visible pore contour area.
    nose_mask = _nose_region_mask((h, w), points, skin_mask)
    cheek_mask = cv2.bitwise_or(
        regions.get("left_cheek", np.zeros((h, w), dtype=np.uint8)),
        regions.get("right_cheek", np.zeros((h, w), dtype=np.uint8)),
    )
    pore_roi = cv2.bitwise_and(cv2.bitwise_or(cheek_mask, nose_mask), skin_mask)
    pore_area = max(int(cv2.countNonZero(pore_roi)), 1)
    if pore_area > 0:
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        enhanced = clahe.apply(gray)
        blackhat = cv2.morphologyEx(
            enhanced,
            cv2.MORPH_BLACKHAT,
            cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5)),
        )
        bh_values = blackhat[pore_roi > 0]
        bh_threshold = float(np.percentile(bh_values, 88)) if bh_values.size > 0 else 255.0
        pores_binary = np.logical_and(pore_roi > 0, blackhat >= bh_threshold).astype(np.uint8) * 255
        pores_binary = cv2.morphologyEx(
            pores_binary,
            cv2.MORPH_OPEN,
            cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3)),
        )

        num_labels, labels, stats, _ = cv2.connectedComponentsWithStats((pores_binary > 0).astype(np.uint8), connectivity=8)
        pore_component_areas: list[float] = []
        min_pore_area = 2
        max_pore_area = max(10, int(pore_area * 0.0045))
        for label_id in range(1, num_labels):
            area = int(stats[label_id, cv2.CC_STAT_AREA])
            if area < min_pore_area or area > max_pore_area:
                continue
            pore_component_areas.append(float(area))

        if pore_component_areas:
            avg_pore_area = float(np.mean(pore_component_areas))
            pore_contraction_index = np.clip((avg_pore_area / 20.0) * 100.0, 0.0, 100.0)
        else:
            pore_contraction_index = 0.0
    else:
        pore_contraction_index = 0.0

    # 3) Structural firmness / elasticity (benefit)
    upper_ids = [6, 168, 197]
    jaw_ids = [152, 149, 176, 377, 400]
    nasolabial_ids = [61, 291]
    upper_pts = np.array([points[i] for i in upper_ids if 0 <= i < points.shape[0]], dtype=np.float32)
    jaw_pts = np.array([points[i] for i in jaw_ids if 0 <= i < points.shape[0]], dtype=np.float32)
    nasolabial_pts = np.array([points[i] for i in nasolabial_ids if 0 <= i < points.shape[0]], dtype=np.float32)

    face_height = max(float(np.max(points[:, 1]) - np.min(points[:, 1])), 1.0)
    if upper_pts.size > 0 and jaw_pts.size > 0 and nasolabial_pts.size > 0:
        upper_y = float(np.mean(upper_pts[:, 1]))
        jaw_y = float(np.mean(jaw_pts[:, 1]))
        nasolabial_y = float(np.mean(nasolabial_pts[:, 1]))
        gravity_drift_ratio = ((jaw_y - upper_y) * 0.65 + (nasolabial_y - upper_y) * 0.35) / face_height
        # Lower drift ratio implies tighter support; convert to higher-is-better score.
        structural_firmness = np.clip(((0.72 - gravity_drift_ratio) / 0.34) * 100.0, 0.0, 100.0)
    else:
        structural_firmness = 0.0

    return {
        "glabellar_wrinkle_depth": round(float(np.clip(glabellar_wrinkle_depth, 0.0, 100.0)), 1),
        "pore_contraction_index": round(float(np.clip(pore_contraction_index, 0.0, 100.0)), 1),
        "structural_firmness_elasticity": round(float(np.clip(structural_firmness, 0.0, 100.0)), 1),
    }


def filter_safe_skin_routine(user_metrics: Dict[str, Any], product_pool: list[Dict[str, Any]]) -> list[Dict[str, Any]]:
    rosacea_score = float(user_metrics.get("rosacea_score", 0.0))
    sensitivity_score = float(user_metrics.get("sensitivity_score", 0.0))
    compromised_barrier = bool(user_metrics.get("compromised_barrier", False))
    acne_score = float(user_metrics.get("acne_score", 0.0))

    high_strength_acids = {
        "glycolic",
        "salicylic",
        "lactic",
        "aha",
        "bha",
        "pha",
    }
    barrier_keywords = {
        "ceramide",
        "hyaluronic",
        "centella",
        "snail mucin",
    }

    def _has_keyword(product: Dict[str, Any], keywords: set[str]) -> bool:
        haystack = " ".join(
            [
                str(product.get("name", "")),
                str(product.get("reason_tag", "")),
                " ".join(str(x) for x in product.get("ingredients", [])),
            ]
        ).lower()
        return any(k in haystack for k in keywords)

    filtered = list(product_pool)
    safety_trigger = rosacea_score > 5.0 or sensitivity_score > 5.0 or compromised_barrier

    if safety_trigger:
        filtered = [p for p in filtered if not _has_keyword(p, high_strength_acids)]

        barrier_replacements = [
            {
                "brand": "CeraVe",
                "name": "Moisturizing Cream",
                "price": "$19.99",
                "reason_tag": "Barrier Repair",
                "affiliate_url": "https://amazon.com",
                "ingredients": ["ceramide"],
            },
            {
                "brand": "La Roche-Posay",
                "name": "Cicaplast Baume B5+",
                "price": "$16.99",
                "reason_tag": "Barrier Recovery",
                "affiliate_url": "https://laroche-posay.us",
                "ingredients": ["centella"],
            },
            {
                "brand": "COSRX",
                "name": "Advanced Snail 96 Mucin Essence",
                "price": "$25.00",
                "reason_tag": "Hydration Barrier",
                "affiliate_url": "https://amazon.com",
                "ingredients": ["snail mucin", "hyaluronic"],
            },
        ]

        for replacement in barrier_replacements:
            if not any(p.get("name") == replacement["name"] for p in filtered):
                filtered.append(replacement)

    acne_and_sensitive = acne_score > 6.0 and sensitivity_score > 5.0
    if acne_and_sensitive:
        # Remove leave-on peels/acid toners and inject gentle anti-inflammatory option.
        filtered = [
            p
            for p in filtered
            if "leave-on" not in str(p.get("reason_tag", "")).lower() and not _has_keyword(p, high_strength_acids)
        ]
        gentle_option = {
            "brand": "PanOxyl",
            "name": "4% Benzoyl Peroxide Creamy Wash",
            "price": "$12.99",
            "reason_tag": "Gentle Anti-Inflammatory Rinse-Off",
            "affiliate_url": "https://amazon.com",
            "ingredients": ["benzoyl peroxide"],
        }
        if not any(p.get("name") == gentle_option["name"] for p in filtered):
            filtered.append(gentle_option)

    deduped: list[Dict[str, Any]] = []
    seen = set()
    for p in filtered:
        key = (str(p.get("brand", "")).strip().lower(), str(p.get("name", "")).strip().lower())
        if key in seen:
            continue
        seen.add(key)
        deduped.append(p)
    return deduped


def _percentile(channel: np.ndarray, mask: np.ndarray, p: float) -> float:
    vals = channel[mask > 0]
    return float(np.percentile(vals, p)) if vals.size > 0 else 0.0


def _run_yolo_lesion_count(bgr_face: np.ndarray) -> int:
    if _YOLO is None:
        raise RuntimeError("YOLO model handle is not initialized after pipeline bootstrap.")

    def _to_numpy_array(value: Any) -> np.ndarray:
        data = value
        if hasattr(data, "detach"):
            data = data.detach()
        if hasattr(data, "cpu"):
            data = data.cpu()
        if hasattr(data, "numpy"):
            return data.numpy()
        return np.asarray(data)

    try:
        yolo_conf = float(os.getenv("YOLO_CONF_THRESHOLD", "0.18"))
    except Exception:
        yolo_conf = 0.18
    yolo_conf = float(np.clip(yolo_conf, 0.01, 0.95))

    # Run model prediction with a low diagnostic confidence so subtle lesions
    # are not pre-filtered out by the model API; apply the runtime threshold
    # below in Python for explicit, inspectable filtering.
    try:
        raw_conf = float(os.getenv("YOLO_RAW_CONF_THRESHOLD", "0.001"))
    except Exception:
        raw_conf = 0.001
    predict_conf = float(np.clip(min(raw_conf, yolo_conf), 0.001, 0.95))

    try:
        res = _YOLO.predict(
            source=bgr_face,
            imgsz=640,
            conf=predict_conf,
            iou=0.5,
            device="cpu",
            verbose=False,
            max_det=300,
        )
    except Exception as exc:
        logger.exception("YOLO inference failed on face ROI: %s", exc)
        raise RuntimeError(f"YOLO inference execution failed: {exc}") from exc

    if not res:
        logger.warning("YOLO inference returned an empty prediction object.")
        return 0

    result = res[0]
    boxes = getattr(result, "boxes", None)
    if boxes is None:
        logger.warning("YOLO returned no boxes container on results object: %s", type(result))
        return 0

    raw_box_data = getattr(boxes, "data", None)
    raw_conf_tensor = getattr(boxes, "conf", None)
    raw_data_shape = None
    conf_values: list[float] = []

    if raw_box_data is not None:
        try:
            raw_data_np = _to_numpy_array(raw_box_data)
            raw_data_shape = tuple(raw_data_np.shape)
        except Exception:
            raw_data_np = None
    else:
        raw_data_np = None

    if raw_conf_tensor is not None:
        try:
            conf_np = _to_numpy_array(raw_conf_tensor).astype(np.float32).reshape(-1)
            conf_values = [float(v) for v in conf_np.tolist()]
        except Exception:
            conf_values = []

    logger.info(
        "Raw YOLO prediction diagnostics: boxes_shape=%s conf_count=%d conf_min=%.4f conf_max=%.4f conf_head=%s",
        raw_data_shape,
        len(conf_values),
        min(conf_values) if conf_values else 0.0,
        max(conf_values) if conf_values else 0.0,
        conf_values[:8],
    )

    count = 0
    if raw_data_np is not None and raw_data_np.ndim == 2 and raw_data_np.shape[1] >= 5:
        # Ultralytics boxes.data rows are typically [x1, y1, x2, y2, conf, cls].
        for row in raw_data_np:
            try:
                score = float(row[4])
            except Exception:
                continue
            if score >= yolo_conf:
                count += 1
    elif conf_values:
        count = sum(1 for score in conf_values if score >= yolo_conf)
    else:
        # Last-resort fallback if the backend returns an unexpected structure.
        try:
            count = int(len(boxes))
        except Exception:
            count = 0

    logger.info(
        "YOLO filtered detections: kept=%d threshold=%.3f predict_conf=%.3f",
        count,
        yolo_conf,
        predict_conf,
    )
    return int(count)


def _build_metric_matrix(results: Dict[str, Any]) -> Dict[str, float]:
    redness_score = float(results.get("calibrated_redness_score", 0.0))
    smoothness_score = float(results.get("calibrated_smoothness_score", 0.0))
    acne_health_score = float(results.get("acne_activity_score", 100.0))
    pore_density = float(results.get("raw_pore_density", 0.0))
    sebum_gloss = float(results.get("sebum_excess_oil_gloss", 0.0))
    diffuse_flushing = float(results.get("diffuse_flushing_erythema", 0.0))
    skin_radiance = float(results.get("skin_tone_radiance_evenness", 0.0))
    glabellar_wrinkle_depth = float(results.get("glabellar_wrinkle_depth", 0.0))
    pore_contraction_index = float(results.get("pore_contraction_index", 0.0))
    structural_firmness = float(results.get("structural_firmness_elasticity", 0.0))
    return {
        "texture_smoothness": round(smoothness_score, 1),
        "localized_redness": round(max(0.0, 100.0 - redness_score), 1),
        "pore_visibility": round(pore_density, 1),
        "breakout_activity": round(max(0.0, 100.0 - acne_health_score), 1),
        "sebum_excess_oil_gloss": round(max(0.0, sebum_gloss), 1),
        "diffuse_flushing_erythema": round(max(0.0, diffuse_flushing), 1),
        "skin_tone_radiance_evenness": round(max(0.0, skin_radiance), 1),
        "glabellar_wrinkle_depth": round(max(0.0, glabellar_wrinkle_depth), 1),
        "pore_contraction_index": round(max(0.0, pore_contraction_index), 1),
        "structural_firmness_elasticity": round(max(0.0, structural_firmness), 1),
    }


def _parse_baseline_metric_matrix(raw: Any) -> Dict[str, float]:
    if raw is None:
        return {}

    payload = raw
    if isinstance(raw, str):
        text = raw.strip()
        if not text:
            return {}
        payload = json.loads(text)

    if not isinstance(payload, dict):
        raise ValueError("Baseline metric matrix must be a JSON object.")

    baseline: Dict[str, float] = {}
    for key, value in payload.items():
        try:
            baseline[str(key)] = float(value)
        except Exception as exc:
            raise ValueError(f"Baseline metric matrix contains a non-numeric value for '{key}'.") from exc
    return baseline


def _compute_trend_deltas(current_matrix: Dict[str, float], baseline_matrix: Dict[str, float]) -> Dict[str, float]:
    deltas: Dict[str, float] = {}
    # Metric directionality:
    # - Higher is better: positive deltas indicate improvement.
    # - Lower is better: positive deltas indicate improvement (decrease in defect load).
    higher_is_better = {
        "texture_smoothness",
        "skin_tone_radiance_evenness",
        "structural_firmness_elasticity",
    }

    for key, current_value in current_matrix.items():
        if key not in baseline_matrix:
            continue

        current = float(current_value)
        baseline_value = float(baseline_matrix[key])

        # Graceful zero-baseline handling: avoid synthetic +/-100% jumps
        # or NaN/inf when no meaningful baseline exists.
        if abs(baseline_value) < 1e-9:
            deltas[key] = 0.0
            continue

        denominator = abs(baseline_value)
        if key in higher_is_better:
            delta_pct = ((current - baseline_value) / denominator) * 100.0
        else:
            # Defect-like metrics: a decrease is an improvement.
            delta_pct = ((baseline_value - current) / denominator) * 100.0

        deltas[key] = round(delta_pct, 1)
    return deltas


def analyze_skin_patch(bgr_image: np.ndarray, baseline_matrix: Dict[str, float] | None = None) -> Dict[str, Any]:
    """Core math analytics processor combined with 0-100 linear calibration scoring."""
    ensure_pipeline_ready()
    if not hasattr(math, "exp"):
        raise RuntimeError("Python math.exp is unavailable for metric calibration.")

    def _clamp_score(value: float) -> float:
        return float(max(0.0, min(100.0, value)))

    logger.info(
        "analyze_skin_patch: input matrix shape=%s dtype=%s",
        tuple(bgr_image.shape),
        bgr_image.dtype,
    )

    calibrated_image, calibration = apply_white_balance_calibration(bgr_image)

    rgb = cv2.cvtColor(calibrated_image, cv2.COLOR_BGR2RGB)
    mesh_res = _FACE_MESH.process(rgb)

    if not mesh_res.multi_face_landmarks:
        raise RuntimeError(
            "No face detected by MediaPipe Face Mesh. Please avoid camera monitor reflection or glare noise."
        )

    primary_face = mesh_res.multi_face_landmarks[0]
    primary_landmark_count = len(primary_face.landmark)
    logger.info("MediaPipe face mesh: faces=1 primary_landmarks=%d", primary_landmark_count)

    points = _landmarks_to_points(primary_face, calibrated_image.shape[1], calibrated_image.shape[0])
    aligned_face, _ = _align_and_crop_face(calibrated_image, points)
    norm = normalize_lighting_and_shadows(aligned_face)
    mask = _skin_mask(norm)

    norm_rgb = cv2.cvtColor(norm, cv2.COLOR_BGR2RGB)
    norm_mesh = _FACE_MESH.process(norm_rgb)
    if not norm_mesh.multi_face_landmarks:
        raise RuntimeError(
            "Could not derive dynamic facial regions from the normalized face patch. Retake photo in frontal lighting."
        )
    norm_primary_face = norm_mesh.multi_face_landmarks[0]
    norm_landmark_count = len(norm_primary_face.landmark)
    logger.info(
        "MediaPipe normalized face mesh: faces=1 primary_landmarks=%d roi_shape=%s",
        norm_landmark_count,
        tuple(norm.shape),
    )
    norm_points = _landmarks_to_points(norm_primary_face, norm.shape[1], norm.shape[0])
    regions = _region_masks(norm.shape[:2], mask, norm_points)

    lab = cv2.cvtColor(norm, cv2.COLOR_BGR2LAB)
    gray = cv2.cvtColor(norm, cv2.COLOR_BGR2GRAY)

    a_channel = lab[:, :, 1].astype(np.float32)
    p95_a = _percentile(a_channel, cv2.bitwise_or(regions["left_cheek"], regions["right_cheek"]), 95)
    redness_logistic = 1.0 / (1.0 + math.exp(-0.35 * (p95_a - 136.0)))
    calibrated_redness_score = (1.0 - redness_logistic) * 100.0
    if p95_a <= 132.5:
        calibrated_redness_score = max(96.0, 100.0 - (p95_a - 130.0))
    calibrated_redness_score = _clamp_score(calibrated_redness_score)

    lap = cv2.Laplacian(gray, cv2.CV_64F, ksize=3)
    raw_variance = float(np.var(lap))
    texture_logistic = 1.0 / (1.0 + math.exp(-0.025 * (raw_variance - 65.0)))
    calibrated_smoothness_score = (1.0 - texture_logistic) * 100.0
    if raw_variance <= 25.0:
        calibrated_smoothness_score = max(94.0, 100.0 - (raw_variance * 0.15))
    calibrated_smoothness_score = _clamp_score(calibrated_smoothness_score)

    lesion_count = _run_yolo_lesion_count(norm)
    logger.info("YOLO lesion detector: boxes=%d", lesion_count)
    acne_activity_score = float(np.clip(100.0 - (lesion_count * 10.0), 0.0, 100.0))
    fingerprint = hashlib.sha256(norm.tobytes()).hexdigest()
    metric_matrix = _build_metric_matrix(
        {
            "calibrated_redness_score": calibrated_redness_score,
            "calibrated_smoothness_score": calibrated_smoothness_score,
            "acne_activity_score": acne_activity_score,
            "raw_pore_density": int(lesion_count * 4),
        }
    )
    additional_metrics = _compute_additional_opencv_metrics(norm, mask, regions, norm_points)
    structural_metrics = _compute_structural_opencv_metrics(norm, mask, regions, norm_points)
    metric_matrix.update(additional_metrics)
    metric_matrix.update(structural_metrics)
    trend_deltas = _compute_trend_deltas(metric_matrix, baseline_matrix or {})

    return {
        "calibrated_redness_score": round(calibrated_redness_score, 1),
        "calibrated_smoothness_score": round(calibrated_smoothness_score, 1),
        "acne_activity_score": round(acne_activity_score, 1),
        "raw_pore_density": int(lesion_count * 4),
        "sebum_excess_oil_gloss": additional_metrics.get("sebum_excess_oil_gloss", 0.0),
        "diffuse_flushing_erythema": additional_metrics.get("diffuse_flushing_erythema", 0.0),
        "skin_tone_radiance_evenness": additional_metrics.get("skin_tone_radiance_evenness", 0.0),
        "glabellar_wrinkle_depth": structural_metrics.get("glabellar_wrinkle_depth", 0.0),
        "pore_contraction_index": structural_metrics.get("pore_contraction_index", 0.0),
        "structural_firmness_elasticity": structural_metrics.get("structural_firmness_elasticity", 0.0),
        "fingerprint": fingerprint,
        "calibration": calibration,
        "metric_matrix": metric_matrix,
        "trend_deltas": trend_deltas,
        "model_debug": {
            "face_mesh_landmarks": int(primary_landmark_count),
            "normalized_face_mesh_landmarks": int(norm_landmark_count),
            "yolo_boxes": int(lesion_count),
        },
    }


@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        ensure_pipeline_ready()
        logger.info("Deterministic analysis pipeline initialized (YOLO + MediaPipe + OpenCV)")
    except Exception as exc:
        logger.error("Analysis pipeline startup check failed: %s", exc)
    logger.info("AestheticSkin backend started on http://127.0.0.1:8000")
    yield
    logger.info("AestheticSkin backend shutting down")


app = FastAPI(title="AestheticSkin Analysis API", version="0.3.2", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"http://(127\.0\.0\.1|localhost)(:\d+)?",
    allow_methods=["POST", "GET", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization"],
)


def _decode_image_bytes(raw: bytes) -> np.ndarray:
    arr = np.frombuffer(raw, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("Could not decode image")
    logger.info("Decoded image matrix: shape=%s dtype=%s", tuple(img.shape), img.dtype)
    return img


def validate_camera_hardware_qa(bgr_image: np.ndarray) -> None:
    if bgr_image is None or bgr_image.size == 0:
        raise HTTPException(
            status_code=400,
            detail=(
                "Camera hardware QA failed: decoded frame is empty. "
                "Clinical troubleshooting: retake the photo and ensure the camera feed is active."
            ),
        )

    h, w = bgr_image.shape[:2]
    total_area = float(max(h * w, 1))

    rgb = cv2.cvtColor(bgr_image, cv2.COLOR_BGR2RGB)
    mesh_res = _FACE_MESH.process(rgb)
    if not mesh_res.multi_face_landmarks:
        raise HTTPException(
            status_code=400,
            detail=(
                "Camera hardware QA failed: no face could be localized in the incoming frame. "
                "Clinical troubleshooting: center your full face, remove glare, and avoid profile angles."
            ),
        )

    pts = _landmarks_to_points(mesh_res.multi_face_landmarks[0], w, h)
    min_xy = np.clip(pts.min(axis=0), [0, 0], [w - 1, h - 1])
    max_xy = np.clip(pts.max(axis=0), [0, 0], [w - 1, h - 1])
    x0, y0 = int(min_xy[0]), int(min_xy[1])
    x1, y1 = int(max_xy[0]), int(max_xy[1])

    if x1 <= x0 or y1 <= y0:
        raise HTTPException(
            status_code=400,
            detail=(
                "Camera hardware QA failed: invalid face bounding geometry was detected. "
                "Clinical troubleshooting: hold still and keep your full face in frame."
            ),
        )

    face_roi = bgr_image[y0:y1, x0:x1]
    if face_roi.size == 0:
        raise HTTPException(
            status_code=400,
            detail=(
                "Camera hardware QA failed: face region extraction returned no pixels. "
                "Clinical troubleshooting: recenter and retake under stable framing."
            ),
        )

    # Webcams and phone lenses suffer from smudged glass or motion blur. Standard human skin should yield a Laplacian variance above 45.0. Anything lower indicates an out-of-focus or unacceptably blurry image sensor frame.
    gray_face = cv2.cvtColor(face_roi, cv2.COLOR_BGR2GRAY)
    lap_var = float(cv2.Laplacian(gray_face, cv2.CV_64F, ksize=3).var())
    if lap_var < 45.0:
        raise HTTPException(
            status_code=400,
            detail=(
                f"Camera hardware QA failed: frame sharpness is too low (laplacian_variance={lap_var:.2f}, minimum=45.0). "
                "Clinical troubleshooting: clean the lens, hold still, and refocus before capture."
            ),
        )

    # Enforces distance control. If the face takes up less than 15% of the frame, the user is sitting too far away, resulting in insufficient pixel density for pores. If it takes up more than 65%, the face is jammed against the lens, creating macro lens distortion.
    face_area_ratio = float(((x1 - x0) * (y1 - y0)) / total_area)
    if face_area_ratio < 0.15 or face_area_ratio > 0.65:
        raise HTTPException(
            status_code=400,
            detail=(
                f"Camera hardware QA failed: face fill ratio is out of range (ratio={face_area_ratio:.3f}, expected=0.15-0.65). "
                "Clinical troubleshooting: adjust distance so your face fills a moderate portion of the frame."
            ),
        )

    lab = cv2.cvtColor(bgr_image, cv2.COLOR_BGR2LAB)
    l_channel = lab[:, :, 0].astype(np.float32)
    l_mean = float(l_channel.mean())

    # Prevents silhouette failures. Mean 'L' channel below 60 is completely underexposed (dark room). Max above 225 is totally washed out/overexposed. If the background frame is over 2.5x brighter than the face mask region, the user is backlit by a bright window or lamp, blending facial features into shadows.
    if l_mean < 60.0 or l_mean > 225.0:
        raise HTTPException(
            status_code=400,
            detail=(
                f"Camera hardware QA failed: global exposure is invalid (lab_l_mean={l_mean:.2f}, expected=60.0-225.0). "
                "Clinical troubleshooting: move to even, indirect front lighting and avoid dark rooms or blown highlights."
            ),
        )

    face_l_mean = float(cv2.cvtColor(face_roi, cv2.COLOR_BGR2LAB)[:, :, 0].mean())

    margin_y = max(1, int(h * 0.16))
    margin_x = max(1, int(w * 0.16))
    background_mask = np.zeros((h, w), dtype=bool)
    background_mask[:margin_y, :] = True
    background_mask[h - margin_y :, :] = True
    background_mask[:, :margin_x] = True
    background_mask[:, w - margin_x :] = True

    background_l_mean = float(l_channel[background_mask].mean()) if np.any(background_mask) else l_mean
    backlight_ratio = background_l_mean / max(face_l_mean, 1e-6)
    if backlight_ratio > 2.5:
        raise HTTPException(
            status_code=400,
            detail=(
                f"Camera hardware QA failed: severe backlight detected (background_to_face_l_ratio={backlight_ratio:.2f}, maximum=2.5). "
                "Clinical troubleshooting: avoid bright windows/lights behind you and place soft light in front of your face."
            ),
        )


def _compute_timeline_metrics(face_bgr: np.ndarray) -> dict:
    if not hasattr(math, "exp"):
        raise RuntimeError("Python math.exp is unavailable for metric calibration.")

    def _clamp_score(value: float) -> float:
        return float(max(0.0, min(100.0, value)))

    lab = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2LAB)
    a_channel = lab[:, :, 1].astype(np.float32)
    redness_p95 = float(np.percentile(a_channel, 95))

    gray = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2GRAY)
    lap = cv2.Laplacian(gray, cv2.CV_64F, ksize=3)
    texture_variance = float(np.var(lap))

    redness_logistic = 1.0 / (1.0 + math.exp(-0.35 * (redness_p95 - 136.0)))
    calibrated_redness = (1.0 - redness_logistic) * 100.0
    if redness_p95 <= 132.5:
        calibrated_redness = max(96.0, 100.0 - (redness_p95 - 130.0))
    calibrated_redness = _clamp_score(calibrated_redness)

    texture_logistic = 1.0 / (1.0 + math.exp(-0.025 * (texture_variance - 65.0)))
    calibrated_smoothness = (1.0 - texture_logistic) * 100.0
    if texture_variance <= 25.0:
        calibrated_smoothness = max(94.0, 100.0 - (texture_variance * 0.15))
    calibrated_smoothness = _clamp_score(calibrated_smoothness)

    return {
        "redness_a_star_p95": round(redness_p95, 4),
        "texture_laplacian_variance": round(texture_variance, 4),
        "calibrated_redness_score": round(calibrated_redness, 1),
        "calibrated_smoothness_score": round(calibrated_smoothness, 1),
    }


@app.get("/health")
async def health_check():
    return {"status": "ok"}


@app.post("/api/analyze-skin")
async def analyze_skin(request: Request):
    try:
        ensure_pipeline_ready()

        body = await request.json()
        logger.info(f"Analyze request keys: {list(body.keys())}")

        # Accept multiple possible field names
        image_b64 = body.get("imageBytes") or body.get("image_bytes") or body.get("image")
        baseline_matrix = _parse_baseline_metric_matrix(
            body.get("baselineMetricMatrix") or body.get("baseline_metric_matrix") or body.get("baselineMetrics")
        )

        if not image_b64:
            raise HTTPException(status_code=422, detail="Missing image data (imageBytes / image_bytes / image)")

        image_data = base64.b64decode(image_b64)
        logger.info("Photo received: size=%.1f KB", len(image_data) / 1024)

        raw_image = _decode_image_bytes(image_data)
        logger.info("/api/analyze-skin request matrix accepted for inference.")
        validate_camera_hardware_qa(raw_image)
        result = analyze_skin_patch(raw_image, baseline_matrix=baseline_matrix)
        debug = result.get("model_debug", {})
        logger.info(
            "/api/analyze-skin model outputs: yolo_boxes=%s face_landmarks=%s normalized_landmarks=%s",
            debug.get("yolo_boxes"),
            debug.get("face_mesh_landmarks"),
            debug.get("normalized_face_mesh_landmarks"),
        )

        if "error" in result:
            raise RuntimeError(result["error"])

        response = {
            "status": "success",
            "text": "Deterministic skin analysis complete.",
            "modelUsed": "yolo+mediapipe+opencv-deterministic-v2",
            "metrics": result,
            "opencv_metrics": {
                "sebum_excess_oil_gloss": result.get("sebum_excess_oil_gloss", 0.0),
                "diffuse_flushing_erythema": result.get("diffuse_flushing_erythema", 0.0),
                "skin_tone_radiance_evenness": result.get("skin_tone_radiance_evenness", 0.0),
                "glabellar_wrinkle_depth": result.get("glabellar_wrinkle_depth", 0.0),
                "pore_contraction_index": result.get("pore_contraction_index", 0.0),
                "structural_firmness_elasticity": result.get("structural_firmness_elasticity", 0.0),
            },
        }
        # Compatibility shim for existing Flutter readers expecting top-level keys.
        response.update(result)
        return response

    except HTTPException:
        raise
    except RuntimeError as e:
        logger.error(f"Analysis runtime error: {e}")
        raise HTTPException(
            status_code=503,
            detail=(
                "Skin analysis model pipeline unavailable. "
                f"Action: verify MediaPipe + YOLO model load. Details: {e}"
            ),
        )
    except Exception as e:
        logger.error(f"Analysis error: {e}")
        raise HTTPException(status_code=400, detail=str(e))


@app.post("/api/skin/analyze-single")
async def analyze_skin_single(
    image: UploadFile = File(...),
    procedure_type: str | None = Form(None),
    days_post_op: str | None = Form(None),
    skin_profile_note: str | None = Form(None),
    selected_skin_profile_note: str | None = Form(None),
    rosacea_score: str | None = Form(None),
    sensitivity_score: str | None = Form(None),
    compromised_barrier: str | None = Form(None),
    baseline_metric_matrix: str | None = Form(None),
):
    try:
        ensure_pipeline_ready()

        parsed_baseline_matrix = _parse_baseline_metric_matrix(baseline_metric_matrix)

        contents = await image.read()
        if not contents:
            raise HTTPException(status_code=400, detail="Empty file attachment package received.")

        try:
            img_bgr = _decode_image_bytes(contents)
        except Exception as exc:
            raise HTTPException(status_code=400, detail="Corrupted image encoding matrix parameters.") from exc

        logger.info("/api/skin/analyze-single request matrix accepted for inference.")

        validate_camera_hardware_qa(img_bgr)

        results = analyze_skin_patch(img_bgr, baseline_matrix=parsed_baseline_matrix)
        debug = results.get("model_debug", {})
        logger.info(
            "/api/skin/analyze-single model outputs: yolo_boxes=%s face_landmarks=%s normalized_landmarks=%s",
            debug.get("yolo_boxes"),
            debug.get("face_mesh_landmarks"),
            debug.get("normalized_face_mesh_landmarks"),
        )

        redness_score = float(results.get("calibrated_redness_score", 0.0))
        smoothness_score = float(results.get("calibrated_smoothness_score", 0.0))
        acne_health_score = float(results.get("acne_activity_score", 100.0))

        procedure = (procedure_type or "").strip().lower()
        note = f"{skin_profile_note or ''} {selected_skin_profile_note or ''}".strip().lower()

        parsed_days: int | None = None
        if days_post_op is not None and str(days_post_op).strip():
            try:
                parsed_days = int(str(days_post_op).strip())
            except Exception:
                parsed_days = None

        parsed_rosacea: float | None = None
        if rosacea_score is not None and str(rosacea_score).strip():
            try:
                parsed_rosacea = float(str(rosacea_score).strip())
            except Exception:
                parsed_rosacea = None

        parsed_sensitivity: float | None = None
        if sensitivity_score is not None and str(sensitivity_score).strip():
            try:
                parsed_sensitivity = float(str(sensitivity_score).strip())
            except Exception:
                parsed_sensitivity = None

        barrier_flag = False
        if compromised_barrier is not None:
            barrier_flag = str(compromised_barrier).strip().lower() in {
                "1",
                "true",
                "yes",
                "y",
            }

        recommended_products: list[dict[str, Any]] = []

        def _append_product(
            *,
            brand: str,
            name: str,
            price: str,
            reason_tag: str,
            affiliate_url: str,
            ingredients: list[str] | None = None,
        ) -> None:
            candidate = {
                "brand": brand,
                "name": name,
                "price": price,
                "reason_tag": reason_tag,
                "affiliate_url": affiliate_url,
                "ingredients": ingredients or [],
            }
            if candidate not in recommended_products:
                recommended_products.append(candidate)

        # 1) Post-procedure shield.
        in_laser_window = (
            parsed_days is not None
            and 1 <= parsed_days <= 7
            and any(token in procedure for token in ("halo", "tca", "co2"))
        )
        if in_laser_window or redness_score < 75.0:
            _append_product(
                brand="Avène",
                name="Cicalfate+ Restorative Protective Cream",
                price="$28.00",
                reason_tag="Acute Inflammation Barrier",
                affiliate_url="https://amazon.com",
                ingredients=["centella", "barrier lipids"],
            )

        # 2) Texture and hydration corrector.
        if smoothness_score < 80.0:
            _append_product(
                brand="SkinCeuticals",
                name="HA Intensive Amplifier",
                price="$110.00",
                reason_tag="Corrects Rough Texture",
                affiliate_url="https://sjv.io",
                ingredients=["hyaluronic"],
            )

        # 3) Vascular stabilizer.
        has_rosacea_note = "rosacea" in note
        if has_rosacea_note or (75.0 <= redness_score <= 85.0):
            _append_product(
                brand="La Roche-Posay",
                name="Rosaliac AR Intense Localized Redness Serum",
                price="$40.00",
                reason_tag="Vascular Calm",
                affiliate_url="https://laroche-posay.us",
                ingredients=["niacinamide", "soothing complex"],
            )

        # Example high-activity pool entry (filtered out when safety matrix triggers).
        acne_severity_score = max(0.0, min(10.0, (100.0 - acne_health_score) / 10.0))
        if acne_severity_score > 5.5:
            _append_product(
                brand="Generic Active",
                name="AHA/BHA/PHA Multi-Acid Toner",
                price="$32.00",
                reason_tag="Leave-on resurfacing active",
                affiliate_url="https://amazon.com",
                ingredients=["aha", "bha", "pha", "glycolic", "salicylic"],
            )

        inferred_rosacea = parsed_rosacea if parsed_rosacea is not None else max(0.0, min(10.0, (90.0 - redness_score) / 3.0))
        inferred_sensitivity = (
            parsed_sensitivity
            if parsed_sensitivity is not None
            else max(0.0, min(10.0, ((85.0 - redness_score) / 4.0) + ((80.0 - smoothness_score) / 8.0)))
        )
        inferred_compromised = (
            barrier_flag
            or "compromised barrier" in note
            or "barrier" in note and "compromised" in note
            or redness_score < 78.0
            or smoothness_score < 76.0
        )

        safety_metrics = {
            "rosacea_score": inferred_rosacea,
            "sensitivity_score": inferred_sensitivity,
            "compromised_barrier": inferred_compromised,
            "acne_score": acne_severity_score,
        }
        filtered = filter_safe_skin_routine(safety_metrics, recommended_products)

        return {
            "status": "success",
            "metrics": results,
            "metric_matrix": results.get("metric_matrix", {}),
            "trend_deltas": results.get("trend_deltas", {}),
            "opencv_metrics": {
                "sebum_excess_oil_gloss": results.get("sebum_excess_oil_gloss", 0.0),
                "diffuse_flushing_erythema": results.get("diffuse_flushing_erythema", 0.0),
                "skin_tone_radiance_evenness": results.get("skin_tone_radiance_evenness", 0.0),
                "glabellar_wrinkle_depth": results.get("glabellar_wrinkle_depth", 0.0),
                "pore_contraction_index": results.get("pore_contraction_index", 0.0),
                "structural_firmness_elasticity": results.get("structural_firmness_elasticity", 0.0),
            },
            "calibration": results.get("calibration", {}),
            "smart_narrative": "Your single skin scan analysis has successfully loaded. Metrics show healthy, compliant cellular maturation trajectories.",
            "recommended_products": [
                {
                    "brand": p.get("brand", ""),
                    "name": p.get("name", ""),
                    "price": p.get("price", ""),
                    "reason_tag": p.get("reason_tag", ""),
                    "affiliate_url": p.get("affiliate_url", ""),
                }
                for p in filtered
            ],
            "safety_profile": {
                "rosacea_score": round(float(safety_metrics["rosacea_score"]), 1),
                "sensitivity_score": round(float(safety_metrics["sensitivity_score"]), 1),
                "compromised_barrier": bool(safety_metrics["compromised_barrier"]),
                "acne_score": round(float(safety_metrics["acne_score"]), 1),
            },
        }

    except HTTPException:
        raise
    except RuntimeError as exc:
        message = str(exc)
        status_code = 400 if "face" in message.lower() or "landmark" in message.lower() else 503
        raise HTTPException(status_code=status_code, detail=message)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        logger.error("Single-image analysis error: %s", exc)
        raise HTTPException(status_code=400, detail=str(exc))


@app.post("/api/coach")
async def ai_coach(request: Request):
    try:
        raw_bytes = await request.body()
        raw_text = raw_bytes.decode("utf-8", errors="replace").strip()

        if not raw_text:
            raise HTTPException(
                status_code=400,
                detail="Empty request body. Expected a JSON object payload.",
            )

        # 1) Robust JSON parsing layers to prevent 500 parse issues
        try:
            body = json.loads(raw_text)
        except json.JSONDecodeError:
            try:
                unescaped = raw_text.encode("utf-8").decode("unicode_escape")
                body = json.loads(unescaped)
            except Exception:
                logger.exception("JSON decode failed for /api/coach")
                logger.error("Raw body preview (first 1000 chars): %s", raw_text[:1000])
                raise HTTPException(
                    status_code=400,
                    detail="Could not decode request body as valid JSON format.",
                )

        if isinstance(body, str):
            try:
                body = json.loads(body)
            except json.JSONDecodeError:
                raise HTTPException(
                    status_code=400,
                    detail="Request payload parsed down to a string, not a valid object map.",
                )

        if not isinstance(body, dict):
            raise HTTPException(
                status_code=400,
                detail="Top-level JSON payload content must resolve to a valid JSON dictionary structure.",
            )

        # 2) Token normalization matching algorithms
        def _norm(key: str) -> str:
            return "".join(ch for ch in str(key).lower() if ch.isalnum())

        def _as_dict(v):
            return v if isinstance(v, dict) else {}

        # Evaluates deep map wrappers cleanly
        candidates = [
            body,
            _as_dict(body.get("User Skin Profile")),
            _as_dict(body.get("user_skin_profile")),
            _as_dict(body.get("payload")),
            _as_dict(body.get("data")),
        ]

        normalized_map = {}
        for container in candidates:
            for k, v in container.items():
                nk = _norm(k)
                if nk not in normalized_map:
                    normalized_map[nk] = v

        def _pick(*keys, default=None):
            for key in keys:
                nk = _norm(key)
                if nk in normalized_map:
                    return normalized_map[nk]
            return default

        # Extract system & user string markers securely
        system_prompt = str(_pick("systemPrompt", "system_prompt", "system", "instructions", default="")).strip()
        user_prompt = str(_pick("userPrompt", "user_prompt", "prompt", "query", "message", default="")).strip()
        gemini_api_key = str(_pick("geminiApiKey", "gemini_api_key", "apiKey", "api_key", default="")).strip()

        if not system_prompt and not user_prompt:
            raise HTTPException(status_code=400, detail="Either systemPrompt or userPrompt data is required.")

        # Resolve authentication key safely
        api_key = os.getenv("GEMINI_API_KEY", "").strip() or gemini_api_key
        if not api_key:
            logger.warning("/api/coach fallback: GEMINI_API_KEY missing; returning non-LLM guidance response")
            fallback_text = (
                "AI coach is running in fallback mode because GEMINI_API_KEY is not configured. "
                "You can still continue tracking scans and trends. "
                "To enable live AI responses, set GEMINI_API_KEY and restart the backend."
            )
            return {
                "text": fallback_text,
                "modelUsed": "fallback-no-key",
                "attempts": 0,
                "status": "fallback",
            }

        # Combine payload context explicitly
        full_prompt = (
            "SYSTEM INSTRUCTIONS:\n"
            f"{system_prompt}\n\n"
            "USER REQUEST:\n"
            f"{user_prompt}"
        ).strip()

        # 3) Process LLM content loops through client API safely
        client = genai.Client(api_key=api_key)
        candidate_models = ["gemini-2.5-flash", "gemini-2.0-flash", "gemini-1.5-flash"]
        
        last_error: Exception | None = None
        for model_name in candidate_models:
            try:
                response = client.models.generate_content(
                    model=model_name,
                    contents=full_prompt,
                )
                text = (response.text or "").strip()
                if not text:
                    raise ValueError("Target model execution returned empty string value object.")

                return {
                    "text": text,
                    "modelUsed": model_name,
                    "attempts": 1,
                    "status": "success"
                }
            except Exception as model_error:
                last_error = model_error
                message = str(model_error).lower()

                if "api_key_invalid" in message or "api key not valid" in message:
                    raise HTTPException(
                        status_code=401,
                        detail="The authentication token specified for the Gemini integration layer is invalid.",
                    )

                if "not found for api version" in message or "is not supported" in message:
                    logger.warning("Target LLM platform fallback execution triggered for model %s: %s", model_name, message)
                    continue
                raise

        if last_error:
            raise last_error
        raise ValueError("Exhausted all eligible model iteration fallbacks without server generation success.")

    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Catastrophic interception on /api/coach scope framework processing block.")
        logger.error("Internal Traceback Context Info Dump:\n%s", traceback.format_exc())
        raise HTTPException(status_code=502, detail=f"AI Engine extraction layer failure proxy error context: {str(e)}")


if __name__ == "__main__":
    uvicorn.run("main:app", host="127.0.0.1", port=8000, reload=True)