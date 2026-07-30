import hashlib
import base64
from dotenv import load_dotenv
load_dotenv(override=True)
import json
import logging
import math
import os
import random
import traceback
import threading
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, Dict, Tuple

import cv2
import numpy as np
import uvicorn
from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
import google.genai as genai

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


def safe_float(val: Any) -> float | None:
    if val is None:
        return None
    try:
        numeric = float(val)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(numeric):
        return None
    return float(numeric)

cv2.setNumThreads(1)
cv2.ocl.setUseOpenCL(False)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SERVER_ROOT = BASE_DIR
PROJECT_ROOT = os.path.abspath(
    os.path.join(BASE_DIR, "..") if os.path.basename(BASE_DIR).lower() == "backend" else BASE_DIR
)
MODELS_DIR = os.path.abspath(os.path.join(BASE_DIR, "assets", "models"))
MEDIAPIPE_MODELS_DIR = os.path.abspath(os.path.join(SERVER_ROOT, "models"))

_PIPELINE_LOCK = threading.Lock()
_PIPELINE_READY = False
_PIPELINE_ERROR = ""
_FACE_MESH = None
_FACE_LANDMARKER = None
_FACE_DETECTOR = None
_YOLO = None


class ModelAssetManager:
    def __init__(self, models_dir: str, server_root: str):
        self.models_dir = os.path.abspath(models_dir)
        self.server_root = os.path.abspath(server_root)

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
                # Resolve relative paths from server root first, then models dir.
                search_paths.append(os.path.abspath(os.path.join(self.server_root, explicit_path)))
                search_paths.append(os.path.abspath(os.path.join(self.models_dir, explicit_path)))

        for name in candidates:
            if os.path.isabs(name):
                search_paths.append(os.path.abspath(name))
            else:
                # Support both server-root-relative and models-dir-relative layouts.
                search_paths.append(os.path.abspath(os.path.join(self.server_root, name)))
                search_paths.append(os.path.abspath(os.path.join(self.models_dir, name)))

        # Keep lookup order but avoid duplicate probes.
        deduped_paths: list[str] = []
        seen: set[str] = set()
        for path in search_paths:
            if path in seen:
                continue
            seen.add(path)
            deduped_paths.append(path)

        logger.info("Searching model assets: %s", " | ".join(deduped_paths))

        for path in deduped_paths:
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


class ModelPathResolver:
    """Resolves model files from env vars first, then project-relative model dirs."""

    def __init__(self, project_root: str):
        self.project_root = Path(project_root).resolve()
        self.search_dirs = [
            (self.project_root / "models").resolve(),
            (self.project_root / "backend" / "models").resolve(),
            (self.project_root / "assets" / "models").resolve(),
        ]

    def resolve(self, *, env_var: str, candidate_filenames: list[str], purpose: str) -> str:
        checked_paths: list[str] = []

        env_value = os.getenv(env_var, "").strip()
        if env_value:
            env_path = Path(env_value)
            if not env_path.is_absolute():
                env_path = (self.project_root / env_path).resolve()
            checked_paths.append(str(env_path))
            if env_path.exists():
                logger.info("Resolved %s from %s: %s", purpose, env_var, env_path)
                return str(env_path)

        for directory in self.search_dirs:
            for file_name in candidate_filenames:
                candidate = (directory / file_name).resolve()
                checked_paths.append(str(candidate))
                if candidate.exists():
                    logger.info("Resolved %s from fallback directories: %s", purpose, candidate)
                    return str(candidate)

        searched_dirs = "\n - " + "\n - ".join(str(d) for d in self.search_dirs)
        searched_files = "\n - " + "\n - ".join(checked_paths)
        env_hint = (
            f"Env override {env_var}={env_value!r} was provided but did not resolve to an existing file."
            if env_value
            else f"Env override {env_var} was not set."
        )
        raise FileNotFoundError(
            f"Missing model asset for {purpose}. {env_hint}\n"
            f"Checked directories:{searched_dirs}\n"
            f"Checked file paths:{searched_files}"
        )


_ASSETS = ModelAssetManager(MODELS_DIR, BASE_DIR)
_MODEL_PATH_RESOLVER = ModelPathResolver(PROJECT_ROOT)

_FACE_DETECTION_UNAVAILABLE_DETAIL = (
    "Face detection service unavailable. Please check server model files."
)


def _is_pipeline_init_error(message: str) -> bool:
    lowered = (message or "").lower()
    return (
        "analysis pipeline failed to initialize" in lowered
        or "imagepropertiescalculator" in lowered
        or "mediapipe" in lowered
        or "face detection service unavailable" in lowered
    )


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


def _extract_primary_landmarks(rgb_image: np.ndarray):
    if _FACE_LANDMARKER is not None and mp is not None:
        try:
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_image)
            task_result = _FACE_LANDMARKER.detect(mp_image)
            if task_result.face_landmarks:
                landmarks = task_result.face_landmarks[0]
                return landmarks, len(landmarks), "task"
        except Exception:
            logger.exception("MediaPipe FaceLandmarker detect failed; falling back to FaceMesh.")

    if _FACE_MESH is None:
        return None, 0, "none"

    mesh_res = _FACE_MESH.process(rgb_image)
    if not mesh_res.multi_face_landmarks:
        return None, 0, "mesh"
    face = mesh_res.multi_face_landmarks[0]
    return face.landmark, len(face.landmark), "mesh"


def ensure_pipeline_ready() -> Dict[str, str]:
    global _PIPELINE_READY, _PIPELINE_ERROR, _FACE_MESH, _FACE_LANDMARKER, _FACE_DETECTOR, _YOLO
    with _PIPELINE_LOCK:
        if _PIPELINE_READY:
            return {"status": "ready"}
        if _PIPELINE_ERROR:
            raise RuntimeError(_PIPELINE_ERROR)

        _seed_everything()
        _ASSETS.ensure_models_dir()
        os.makedirs(MEDIAPIPE_MODELS_DIR, exist_ok=True)

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

        face_detector_model_path = _MODEL_PATH_RESOLVER.resolve(
            env_var="FACE_DETECTOR_MODEL_PATH",
            candidate_filenames=[
                "face_detector.tflite",
                "face_detection_short_range.tflite",
            ],
            purpose="MediaPipe face detector",
        )
        face_landmark_model_path = _MODEL_PATH_RESOLVER.resolve(
            env_var="FACE_LANDMARK_MODEL_PATH",
            candidate_filenames=[
                "face_landmarks_detector.tflite",
                "face_landmarker.task",
                "face_landmarker_v2_with_blendshapes.task",
            ],
            purpose="MediaPipe face landmark model",
        )

        try:
            _FACE_LANDMARKER = None
            _FACE_DETECTOR = None

            try:
                from mediapipe.tasks import python as mp_python
                from mediapipe.tasks.python import vision as mp_vision

                detector_options = mp_vision.FaceDetectorOptions(
                    base_options=mp_python.BaseOptions(
                        model_asset_path=face_detector_model_path,
                    ),
                    running_mode=mp_vision.RunningMode.IMAGE,
                )
                _FACE_DETECTOR = mp_vision.FaceDetector.create_from_options(
                    detector_options
                )
                logger.info("Loaded MediaPipe face detector model from: %s", face_detector_model_path)
            except Exception:
                logger.exception(
                    "Failed to initialize task-based FaceDetector with model_asset_path=%s",
                    face_detector_model_path,
                )
                _FACE_DETECTOR = None

            # FaceLandmarker requires a .task bundle. If only .tflite is provided,
            # we keep FaceMesh as fallback for landmark extraction.
            if face_landmark_model_path.lower().endswith(".task"):
                try:
                    from mediapipe.tasks import python as mp_python
                    from mediapipe.tasks.python import vision as mp_vision

                    landmarker_options = mp_vision.FaceLandmarkerOptions(
                        base_options=mp_python.BaseOptions(
                            model_asset_path=face_landmark_model_path,
                        ),
                        running_mode=mp_vision.RunningMode.IMAGE,
                        num_faces=1,
                    )
                    _FACE_LANDMARKER = mp_vision.FaceLandmarker.create_from_options(
                        landmarker_options
                    )
                    logger.info("Loaded MediaPipe face landmarker model from: %s", face_landmark_model_path)
                except Exception:
                    logger.exception(
                        "Failed to initialize task-based FaceLandmarker with model_asset_path=%s",
                        face_landmark_model_path,
                    )
                    _FACE_LANDMARKER = None
            else:
                logger.warning(
                    "FACE_LANDMARK_MODEL_PATH resolved to non-task file '%s'. "
                    "Task landmarker will be skipped; FaceMesh fallback remains enabled.",
                    face_landmark_model_path,
                )

            try:
                _FACE_MESH = mp.solutions.face_mesh.FaceMesh(
                    static_image_mode=True,
                    max_num_faces=1,
                    refine_landmarks=False,
                    min_detection_confidence=0.5,
                )
            except Exception:
                logger.exception("MediaPipe face mesh graph initialization failed")
                _PIPELINE_ERROR = _FACE_DETECTION_UNAVAILABLE_DETAIL
                raise RuntimeError(_PIPELINE_ERROR)

            _YOLO = YOLO(yolo_path)
            logger.info("Loaded YOLO weights from: %s", yolo_path)
            _PIPELINE_READY = True
            return {"status": "ready"}
        except RuntimeError:
            raise
        except Exception:
            logger.exception("Analysis pipeline failed during model initialization")
            _PIPELINE_ERROR = _FACE_DETECTION_UNAVAILABLE_DETAIL
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

    # Stronger illumination flattening: CLAHE on L with clinically-safe limits.
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    l_eq = clahe.apply(l)

    # Reduce warm/cool cast drift so a*/b* driven metrics are more stable.
    ycrcb = cv2.cvtColor(balanced, cv2.COLOR_BGR2YCrCb)
    skin_mask = cv2.inRange(
        ycrcb,
        np.array([0, 133, 77], dtype=np.uint8),
        np.array([255, 173, 127], dtype=np.uint8),
    )
    if int(cv2.countNonZero(skin_mask)) > 1200:
        a_vals = a[skin_mask > 0].astype(np.float32)
        b_vals = b[skin_mask > 0].astype(np.float32)
    else:
        h, w = a.shape[:2]
        y0, y1 = int(h * 0.20), int(h * 0.80)
        x0, x1 = int(w * 0.20), int(w * 0.80)
        a_vals = a[y0:y1, x0:x1].astype(np.float32).reshape(-1)
        b_vals = b[y0:y1, x0:x1].astype(np.float32).reshape(-1)

    a_shift = float(np.clip(128.0 - float(np.mean(a_vals)), -6.0, 6.0))
    b_shift = float(np.clip(128.0 - float(np.mean(b_vals)), -6.0, 6.0))
    a_bal = np.clip(a.astype(np.float32) + a_shift, 0.0, 255.0).astype(np.uint8)
    b_bal = np.clip(b.astype(np.float32) + b_shift, 0.0, 255.0).astype(np.uint8)

    merged = cv2.merge((l_eq, a_bal, b_bal))
    return cv2.cvtColor(merged, cv2.COLOR_LAB2BGR)


def _compute_ssim_gray(gray_a: np.ndarray, gray_b: np.ndarray) -> float:
    if gray_a.size == 0 or gray_b.size == 0:
        return 0.0

    if gray_a.shape != gray_b.shape:
        gray_b = cv2.resize(gray_b, (gray_a.shape[1], gray_a.shape[0]), interpolation=cv2.INTER_LINEAR)

    a = gray_a.astype(np.float32)
    b = gray_b.astype(np.float32)

    c1 = (0.01 * 255.0) ** 2
    c2 = (0.03 * 255.0) ** 2

    mu_a = cv2.GaussianBlur(a, (11, 11), 1.5)
    mu_b = cv2.GaussianBlur(b, (11, 11), 1.5)

    mu_a_sq = mu_a * mu_a
    mu_b_sq = mu_b * mu_b
    mu_ab = mu_a * mu_b

    sigma_a_sq = cv2.GaussianBlur(a * a, (11, 11), 1.5) - mu_a_sq
    sigma_b_sq = cv2.GaussianBlur(b * b, (11, 11), 1.5) - mu_b_sq
    sigma_ab = cv2.GaussianBlur(a * b, (11, 11), 1.5) - mu_ab

    numerator = (2.0 * mu_ab + c1) * (2.0 * sigma_ab + c2)
    denominator = (mu_a_sq + mu_b_sq + c1) * (sigma_a_sq + sigma_b_sq + c2)
    ssim_map = numerator / (denominator + 1e-9)
    return float(np.clip(np.mean(ssim_map), 0.0, 1.0))


def _prepare_normalized_face_patch_for_ssim(bgr_image: np.ndarray) -> tuple[np.ndarray | None, int]:
    try:
        rgb = cv2.cvtColor(bgr_image, cv2.COLOR_BGR2RGB)
        landmarks, landmark_count, _ = _extract_primary_landmarks(rgb)
        if landmarks is None:
            return None, 0
        points = _landmarks_to_points(landmarks, bgr_image.shape[1], bgr_image.shape[0])
        aligned_face, _ = _align_and_crop_face(bgr_image, points)
        return normalize_lighting_and_shadows(aligned_face), int(landmark_count)
    except Exception as exc:
        logger.info("SSIM baseline preparation skipped: %s", exc)
        return None, 0


def _prepare_global_patch_for_ssim(bgr_image: np.ndarray) -> np.ndarray | None:
    try:
        if bgr_image is None or bgr_image.size == 0:
            return None
        normalized = normalize_lighting_and_shadows(bgr_image)
        gray = cv2.cvtColor(normalized, cv2.COLOR_BGR2GRAY)
        resized = cv2.resize(gray, (256, 256), interpolation=cv2.INTER_AREA)
        # Light blur reduces tiny codec/landmark-induced jitter while preserving structure.
        return cv2.GaussianBlur(resized, (3, 3), 0.5)
    except Exception as exc:
        logger.info("Global SSIM baseline preparation skipped: %s", exc)
        return None


def _downgrade_confidence_level(level: str, steps: int) -> str:
    order = ["low", "medium", "high"]
    try:
        idx = order.index(level)
    except ValueError:
        idx = 0
    return order[max(0, idx - max(steps, 0))]


def _stabilize_trend_deltas_for_near_identical_scan(
    trend_deltas: Dict[str, float],
    current_matrix: Dict[str, Any],
    baseline_matrix: Dict[str, Any],
    ssim_score: float | None,
) -> Dict[str, float]:
    if ssim_score is None or ssim_score <= 0.88:
        return trend_deltas

    stabilized = dict(trend_deltas)
    for key, original_delta in trend_deltas.items():
        curr = safe_float(current_matrix.get(key, 0.0))
        base = safe_float(baseline_matrix.get(key, 0.0))
        if curr is None or base is None:
            continue
        if not (math.isfinite(curr) and math.isfinite(base)):
            continue

        abs_diff = abs(curr - base)
        if abs_diff <= 1.5:
            stabilized[key] = 0.0
        elif abs_diff <= 3.0:
            stabilized[key] = round(float(original_delta) * 0.35, 1)

    return stabilized


def assess_and_normalize_image(image_bytes: bytes) -> Tuple[np.ndarray, Dict[str, Any]]:
    """Run image quality assessment and lighting normalization before extraction."""
    image_bgr = _decode_image_bytes(image_bytes)
    if image_bgr is None or image_bgr.size == 0:
        raise ValueError("Decoded image is empty for IQA preprocessing.")

    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    blur_score = float(cv2.Laplacian(gray, cv2.CV_64F, ksize=3).var())
    blur_threshold = float(os.getenv("IQA_BLUR_THRESHOLD", "80.0"))
    image_blurry = blur_score < blur_threshold

    wb_image = _gray_world_white_balance(image_bgr)
    wb_lab = cv2.cvtColor(wb_image, cv2.COLOR_BGR2LAB)
    l_channel, a_channel, b_channel = cv2.split(wb_lab)

    clahe = cv2.createCLAHE(clipLimit=2.2, tileGridSize=(8, 8))
    l_equalized = clahe.apply(l_channel)
    normalized_bgr = cv2.cvtColor(
        cv2.merge((l_equalized, a_channel, b_channel)),
        cv2.COLOR_LAB2BGR,
    )

    mean_l = float(np.mean(l_equalized))
    std_l = float(np.std(l_equalized))
    chroma_cast = float(
        np.sqrt(
            (float(np.mean(a_channel)) - 128.0) ** 2
            + (float(np.mean(b_channel)) - 128.0) ** 2
        )
    )

    sharpness_score = float(np.clip(blur_score / 220.0, 0.0, 1.0))
    exposure_score = float(np.clip(1.0 - (abs(mean_l - 145.0) / 95.0), 0.0, 1.0))
    contrast_score = float(np.clip(std_l / 58.0, 0.0, 1.0))
    color_balance_score = float(np.clip(1.0 - (chroma_cast / 42.0), 0.0, 1.0))
    lighting_balance_score = float(
        np.clip(
            (0.50 * exposure_score) + (0.25 * contrast_score) + (0.25 * color_balance_score),
            0.0,
            1.0,
        )
    )

    warnings: list[str] = []
    if image_blurry:
        warnings.append("Hold camera steady and retake in sharper focus.")
    if mean_l < 80.0:
        warnings.append("Lighting too dim. Move to brighter front-facing light.")
    if mean_l > 215.0:
        warnings.append("Lighting too bright. Avoid harsh direct light.")
    if chroma_cast > 20.0:
        warnings.append("Strong color cast detected. Use neutral white lighting.")

    return normalized_bgr, {
        "blur_score": round(blur_score, 2),
        "blur_threshold": round(blur_threshold, 2),
        "image_blurry": image_blurry,
        "lighting_mean_l": round(mean_l, 2),
        "lighting_std_l": round(std_l, 2),
        "chroma_cast": round(chroma_cast, 2),
        "sharpness_score": round(sharpness_score, 3),
        "lighting_balance_score": round(lighting_balance_score, 3),
        "preprocess_warnings": warnings,
    }


def _build_confidence_profile(
    quality_profile: Dict[str, Any],
    *,
    primary_landmark_count: int,
    normalized_landmark_count: int,
    landmark_alignment_score: float,
) -> Tuple[float, list[str]]:
    sharpness = float(np.clip(float(quality_profile.get("sharpness_score", 0.0)), 0.0, 1.0))
    lighting = float(np.clip(float(quality_profile.get("lighting_balance_score", 0.0)), 0.0, 1.0))
    landmark_density = float(
        np.clip(
            (float(primary_landmark_count) + float(normalized_landmark_count)) / (2.0 * 468.0),
            0.0,
            1.0,
        )
    )
    alignment = float(np.clip(landmark_alignment_score, 0.0, 1.0))

    confidence = float(
        np.clip(
            (0.35 * sharpness)
            + (0.30 * lighting)
            + (0.20 * landmark_density)
            + (0.15 * alignment),
            0.0,
            1.0,
        )
    )

    hints: list[str] = list(quality_profile.get("preprocess_warnings", []))
    if alignment < 0.55:
        hints.append("Keep your face centered and look straight into the camera.")
    if landmark_density < 0.85:
        hints.append("Move slightly closer and ensure full face is visible.")
    if confidence < 0.65 and not hints:
        hints.append("Retake in even front lighting with a steady camera for higher confidence.")

    deduped_hints: list[str] = []
    seen: set[str] = set()
    for hint in hints:
        if hint in seen:
            continue
        seen.add(hint)
        deduped_hints.append(hint)

    return round(confidence, 3), deduped_hints


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
    iterable = landmarks.landmark if hasattr(landmarks, "landmark") else landmarks
    max_x = max(int(width) - 1, 0)
    max_y = max(int(height) - 1, 0)
    pts: list[tuple[float, float]] = []
    for lm in iterable:
        # MediaPipe landmarks are normalized in [0..1]. Convert explicitly to
        # integer pixel coordinates before downstream polygon rasterization.
        px = int(float(lm.x) * float(width))
        py = int(float(lm.y) * float(height))
        px = int(np.clip(px, 0, max_x))
        py = int(np.clip(py, 0, max_y))
        pts.append((float(px), float(py)))
    return np.array(pts, dtype=np.float32)


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

    poly = np.asarray(polygon, dtype=np.float32).reshape(-1, 2)
    poly[:, 0] = np.clip(poly[:, 0], 0, w - 1)
    poly[:, 1] = np.clip(poly[:, 1], 0, h - 1)

    poly_int = np.round(poly).astype(np.int32)
    if poly_int.shape[0] < 3:
        return out

    contour = poly_int.reshape((-1, 1, 2))
    area = abs(float(cv2.contourArea(contour)))
    if area < 1.0:
        # Resolve degenerate / self-intersecting ordering by falling back to hull.
        contour = cv2.convexHull(contour)
        if contour is None or contour.shape[0] < 3:
            return out

    # OpenCV expects polygon points as int32 with shape (N, 1, 2).
    cv2.fillPoly(out, [contour.astype(np.int32)], 255)
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


def _nose_region_mask(
    shape: Tuple[int, int],
    points: np.ndarray,
    skin_mask: np.ndarray,
    *,
    apply_skin_mask: bool = True,
) -> np.ndarray:
    # Central nose bridge/tip polygon used for T-zone and diffuse flushing analysis.
    ids = [168, 6, 197, 195, 5, 4, 1, 2, 98, 327]
    valid_ids = [idx for idx in ids if 0 <= idx < points.shape[0]]
    if len(valid_ids) < 3:
        return np.zeros(shape, dtype=np.uint8)

    mask = _polygon_mask(shape, points[valid_ids])
    if not apply_skin_mask:
        return mask

    intersected = cv2.bitwise_and(mask, skin_mask)
    raw_pixels = int(cv2.countNonZero(mask))
    skin_pixels = int(cv2.countNonZero(intersected))
    if skin_pixels == 0 and raw_pixels > 100:
        # Keep the geometric ROI when color-based skin thresholds are overly strict.
        return mask
    return intersected


def _glabella_region_mask(shape: Tuple[int, int], points: np.ndarray, skin_mask: np.ndarray) -> np.ndarray:
    # Region between brows and upper nasal root for "11" line estimation.
    ids = [55, 65, 52, 168, 8, 417, 285, 295, 282]
    valid_ids = [idx for idx in ids if 0 <= idx < points.shape[0]]
    if len(valid_ids) < 3:
        return np.zeros(shape, dtype=np.uint8)
    glabella = _polygon_mask(shape, points[valid_ids])
    return cv2.bitwise_and(glabella, skin_mask)


def _under_eye_region_mask(
    shape: Tuple[int, int],
    points: np.ndarray,
    skin_mask: np.ndarray,
    *,
    side: str,
) -> np.ndarray:
    if side == "left":
        ids = [33, 133, 155, 154, 153, 145, 144, 163, 7]
    else:
        ids = [362, 263, 382, 381, 380, 374, 373, 390, 249]

    valid_ids = [idx for idx in ids if 0 <= idx < points.shape[0]]
    if len(valid_ids) < 3:
        return np.zeros(shape, dtype=np.uint8)

    eye_poly = points[valid_ids]
    center = np.mean(eye_poly, axis=0)
    expanded = eye_poly + ((eye_poly - center) * 0.12)
    expanded[:, 1] = expanded[:, 1] + (shape[0] * 0.028)
    mask = _polygon_mask(shape, expanded)
    return cv2.bitwise_and(mask, skin_mask)


def _compute_pose_pitch_yaw_from_landmarks(points: np.ndarray) -> tuple[float, float]:
    # Lightweight pose proxy from landmark geometry. Values are degrees-like.
    required_ids = [1, 33, 263, 10, 152]
    if any(idx < 0 or idx >= points.shape[0] for idx in required_ids):
        return 0.0, 0.0

    nose = points[1].astype(np.float32)
    left_eye_outer = points[33].astype(np.float32)
    right_eye_outer = points[263].astype(np.float32)
    forehead = points[10].astype(np.float32)
    chin = points[152].astype(np.float32)

    eye_mid = (left_eye_outer + right_eye_outer) * 0.5
    eye_dist = float(np.linalg.norm(right_eye_outer - left_eye_outer))
    face_height = float(abs(chin[1] - forehead[1]))

    if eye_dist < 1e-6 or face_height < 1e-6:
        return 0.0, 0.0

    yaw_ratio = float((nose[0] - eye_mid[0]) / eye_dist)
    yaw = yaw_ratio * 90.0

    vertical_ratio = float((nose[1] - eye_mid[1]) / face_height)
    pitch = (vertical_ratio - 0.18) * 240.0

    return pitch, yaw


def _build_pore_roi_masks(
    shape: Tuple[int, int],
    points: np.ndarray,
    face_bgr: np.ndarray,
    skin_mask: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    # ROI lock: full face skin (forehead, nose, cheeks, chin) from face oval.
    # Excludes non-face/background by constraining to face contour + skin signals.
    h, w = shape
    face_oval_ids = [
        10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288,
        397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136,
        172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109,
    ]
    valid_ids = [idx for idx in face_oval_ids if 0 <= idx < points.shape[0]]
    if len(valid_ids) < 3:
        empty = np.zeros((h, w), dtype=np.uint8)
        return empty, empty

    geom_mask = _polygon_mask((h, w), points[valid_ids])

    # Trim boundary noise near hairline/ears/jaw edge.
    erode_kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
    inner_face_mask = cv2.erode(geom_mask, erode_kernel, iterations=1)
    if cv2.countNonZero(inner_face_mask) <= 0:
        inner_face_mask = geom_mask

    # Exclude high-contrast non-skin facial features from pore scoring area.
    exclusion = np.zeros((h, w), dtype=np.uint8)
    left_eye_ids = [33, 133, 155, 154, 153, 145, 144, 163, 7]
    right_eye_ids = [362, 263, 382, 381, 380, 374, 373, 390, 249]
    lips_ids = [61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 308]
    for ids in (left_eye_ids, right_eye_ids, lips_ids):
        valid = [idx for idx in ids if 0 <= idx < points.shape[0]]
        if len(valid) >= 3:
            exclusion = cv2.bitwise_or(exclusion, _polygon_mask((h, w), points[valid]))

    face_skin_candidate = cv2.bitwise_and(
        inner_face_mask,
        cv2.bitwise_not(exclusion),
    )

    # Primary intersection with upstream skin mask.
    skin_locked_mask = cv2.bitwise_and(face_skin_candidate, skin_mask)
    raw_pixels = int(cv2.countNonZero(face_skin_candidate))
    intersected_pixels = int(cv2.countNonZero(skin_locked_mask))

    # Fallback when strict skin mask under-segments normal full-face photos.
    min_intersection = max(500, int(raw_pixels * 0.03))
    if intersected_pixels < min_intersection:
        # Use relaxed skin chroma bounds within face contour only.
        ycrcb = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2YCrCb)
        hsv = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2HSV)
        y = ycrcb[:, :, 0]
        cr = ycrcb[:, :, 1]
        cb = ycrcb[:, :, 2]
        sat = hsv[:, :, 1]
        val = hsv[:, :, 2]

        relaxed_skin_bool = np.logical_and.reduce([
            face_skin_candidate > 0,
            cr >= 128,
            cr <= 178,
            cb >= 78,
            cb <= 138,
            sat >= 18,
            sat <= 235,
            val >= 35,
            y >= 35,
        ])
        fallback_mask = (relaxed_skin_bool.astype(np.uint8) * 255)
        fallback_mask = cv2.morphologyEx(
            fallback_mask,
            cv2.MORPH_OPEN,
            cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3)),
        )
        fallback_mask = cv2.morphologyEx(
            fallback_mask,
            cv2.MORPH_CLOSE,
            cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5)),
        )
        fallback_mask = cv2.bitwise_and(fallback_mask, face_skin_candidate)
        fallback_pixels = int(cv2.countNonZero(fallback_mask))
        if fallback_pixels > 0:
            skin_locked_mask = fallback_mask
            intersected_pixels = fallback_pixels

    logger.info(
        "[PoreROI] full_face_pixels=%d skin_intersected_pixels=%d",
        raw_pixels,
        intersected_pixels,
    )
    return geom_mask, skin_locked_mask


def _extract_normalized_pore_roi(
    face_bgr: np.ndarray,
    points: np.ndarray,
    skin_mask: np.ndarray,
) -> tuple[np.ndarray | None, np.ndarray | None, int]:
    geom_mask, skin_locked_mask = _build_pore_roi_masks(
        face_bgr.shape[:2],
        points,
        face_bgr,
        skin_mask,
    )
    if int(cv2.countNonZero(skin_locked_mask)) <= 0:
        return None, None, 0

    ys, xs = np.where(skin_locked_mask > 0)
    if xs.size == 0 or ys.size == 0:
        return None, None, 0

    x0 = int(np.min(xs))
    x1 = int(np.max(xs)) + 1
    y0 = int(np.min(ys))
    y1 = int(np.max(ys)) + 1

    if (x1 - x0) < 3 or (y1 - y0) < 3:
        return None, None, 0

    lab = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2LAB)
    l_channel = lab[:, :, 0].astype(np.float32)

    l_crop = l_channel[y0:y1, x0:x1]
    mask_crop = skin_locked_mask[y0:y1, x0:x1]

    # Scale normalization lock for camera-distance invariance.
    l_norm = cv2.resize(l_crop, (512, 512), interpolation=cv2.INTER_AREA)
    mask_norm = cv2.resize(mask_crop, (512, 512), interpolation=cv2.INTER_NEAREST)
    mask_norm = np.where(mask_norm > 0, 255, 0).astype(np.uint8)

    return l_norm, mask_norm, int(cv2.countNonZero(mask_norm))


def _signal_conf(
    pixel_count: int,
    spread: float,
    *,
    low_spread: float,
    high_spread: float,
) -> str:
    pixel_count_value = safe_float(pixel_count)
    spread_value = safe_float(spread)
    if pixel_count_value is None or spread_value is None:
        return "low"
    if pixel_count_value >= 6000 and spread_value >= high_spread:
        return "high"
    if pixel_count_value >= 2500 and spread_value >= low_spread:
        return "medium"
    return "low"


def _pore_signal_conf(pixel_count: int, spread: float) -> str:
    pixel_count_value = safe_float(pixel_count)
    spread_value = safe_float(spread)
    if pixel_count_value is None or spread_value is None:
        return "low"
    # T-zone ROIs are naturally smaller than full-face texture ROIs.
    if pixel_count_value >= 1200 and spread_value >= 2.5:
        return "high"
    if pixel_count_value >= 500 and spread_value >= 1.2:
        return "medium"
    return "low"


def _compute_zone_based_metrics(
    face_bgr: np.ndarray,
    skin_mask: np.ndarray,
    regions: Dict[str, np.ndarray],
    points: np.ndarray,
) -> Dict[str, Any]:
    h, w = face_bgr.shape[:2]
    if h == 0 or w == 0:
        return {
            "sebum_excess_oil_gloss": 0.0,
            "pore_visibility": None,
            "pore_visibility_detected": False,
            "localized_redness": 0.0,
            "diffuse_flushing_erythema": 0.0,
            "rosacea_severity": 0.0,
            "glabellar_11_lines_depth": 0.0,
            "under_eye_texture_density": 0.0,
            "under_eye_dark_circle_density": 0.0,
        }

    hsv = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2HSV)
    lab = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2LAB)
    gray = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2GRAY)
    lap_abs = np.abs(cv2.Laplacian(gray, cv2.CV_32F, ksize=3))

    forehead = regions.get("forehead", np.zeros((h, w), dtype=np.uint8))
    nose_polygon = _nose_region_mask((h, w), points, skin_mask, apply_skin_mask=False)
    t_zone_polygon = cv2.bitwise_or(forehead, nose_polygon)
    t_zone = cv2.bitwise_and(t_zone_polygon, skin_mask)
    tzone_raw_pixels = int(cv2.countNonZero(t_zone_polygon))
    tzone_skin_pixels = int(cv2.countNonZero(t_zone))
    logger.info(
        "[TZoneFix] raw_polygon_pixels: %d, skin_intersected_pixels: %d",
        tzone_raw_pixels,
        tzone_skin_pixels,
    )
    if (tzone_skin_pixels == 0 and tzone_raw_pixels > 100) or (
        tzone_skin_pixels < 500 and tzone_raw_pixels > 500
    ):
        t_zone = t_zone_polygon
        tzone_skin_pixels = tzone_raw_pixels
    pore_t_zone_pixels = int(cv2.countNonZero(t_zone))

    # T-zone: oil gloss + pore visibility.
    sat = hsv[:, :, 1]
    val = hsv[:, :, 2]
    sebum_zone = t_zone if pore_t_zone_pixels > 0 else skin_mask.copy()
    t_zone_pixels = sebum_zone > 0
    v_threshold = float(np.percentile(val[t_zone_pixels], 94)) if np.any(t_zone_pixels) else 225.0
    specular = np.logical_and.reduce([t_zone_pixels, val >= max(220.0, v_threshold), sat <= 75])
    sebum_excess_oil_gloss = float(np.clip(np.mean(specular) * 100.0, 0.0, 100.0))

    pore_visibility = None
    pore_visibility_detected = False
    if pore_t_zone_pixels > 0:
        t_lap = lap_abs[t_zone > 0]
        if t_lap.size > 0:
            pore_spread = float(np.std(t_lap))
            pore_confidence = _pore_signal_conf(
                pore_t_zone_pixels,
                pore_spread,
            )
            if pore_confidence != "low":
                pore_signal = float(np.percentile(t_lap, 90))
                pore_visibility = round(float(np.clip(pore_signal / 2.35, 0.0, 100.0)), 1)
                pore_visibility_detected = True

    # U-zone: cheeks for redness / diffuse flushing / rosacea indicators.
    left_cheek = regions.get("left_cheek", np.zeros((h, w), dtype=np.uint8))
    right_cheek = regions.get("right_cheek", np.zeros((h, w), dtype=np.uint8))
    u_zone = cv2.bitwise_and(cv2.bitwise_or(left_cheek, right_cheek), skin_mask)
    u_zone_pixels = u_zone > 0

    a_blur = cv2.GaussianBlur(lab[:, :, 1].astype(np.float32), (0, 0), sigmaX=2.0)
    if np.any(u_zone_pixels):
        median_a = float(np.percentile(a_blur[u_zone_pixels], 50))
        p95_a = float(np.percentile(a_blur[u_zone_pixels], 95))
    else:
        median_a = 128.0
        p95_a = 128.0

    localized_redness = float(np.clip((p95_a - 128.0) * 3.1, 0.0, 100.0))
    diffuse_threshold = max(138.0, median_a + 5.0)
    diffuse_mask = np.logical_and(u_zone_pixels, a_blur >= diffuse_threshold)
    diffuse_density = float(np.clip(np.mean(diffuse_mask) * 100.0, 0.0, 100.0))
    diffuse_flushing_erythema = float(np.clip((0.70 * diffuse_density) + (0.30 * localized_redness), 0.0, 100.0))
    rosacea_severity = float(np.clip((0.65 * diffuse_flushing_erythema) + (0.35 * localized_redness), 0.0, 100.0))

    # Glabellar zone: directional line depth estimation for 11 lines.
    glabella_mask = _glabella_region_mask((h, w), points, skin_mask)
    glabella_pixels = glabella_mask > 0
    if np.any(glabella_pixels):
        gx = cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3)
        gy = cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3)
        vertical_emphasis = np.clip(np.abs(gx) - (0.35 * np.abs(gy)), 0.0, None)
        glabellar_11_lines_depth = float(
            np.clip(np.percentile(vertical_emphasis[glabella_pixels], 88) / 2.1, 0.0, 100.0)
        )
    else:
        glabellar_11_lines_depth = 0.0

    # Periorbital zone: under-eye texture + dark circle density.
    left_under_eye = _under_eye_region_mask((h, w), points, skin_mask, side="left")
    right_under_eye = _under_eye_region_mask((h, w), points, skin_mask, side="right")
    peri_mask = cv2.bitwise_or(left_under_eye, right_under_eye)
    peri_pixels = peri_mask > 0

    if np.any(peri_pixels):
        peri_texture = float(np.percentile(lap_abs[peri_pixels], 88))
        under_eye_texture_density = float(np.clip(peri_texture / 2.0, 0.0, 100.0))

        l_channel = lab[:, :, 0].astype(np.float32)
        cheek_mask = cv2.bitwise_or(left_cheek, right_cheek) > 0
        cheek_l_mean = float(np.mean(l_channel[cheek_mask])) if np.any(cheek_mask) else 150.0
        peri_l_mean = float(np.mean(l_channel[peri_pixels]))
        darkness_delta = max(0.0, cheek_l_mean - peri_l_mean)
        under_eye_dark_circle_density = float(np.clip(darkness_delta * 2.0, 0.0, 100.0))
    else:
        under_eye_texture_density = 0.0
        under_eye_dark_circle_density = 0.0

    return {
        "sebum_excess_oil_gloss": round(sebum_excess_oil_gloss, 1),
        "pore_visibility": pore_visibility,
        "pore_visibility_detected": pore_visibility_detected,
        "localized_redness": round(localized_redness, 1),
        "diffuse_flushing_erythema": round(diffuse_flushing_erythema, 1),
        "rosacea_severity": round(rosacea_severity, 1),
        "glabellar_11_lines_depth": round(glabellar_11_lines_depth, 1),
        "under_eye_texture_density": round(under_eye_texture_density, 1),
        "under_eye_dark_circle_density": round(under_eye_dark_circle_density, 1),
    }


def _compute_additional_opencv_metrics(
    face_bgr: np.ndarray,
    skin_mask: np.ndarray,
    regions: Dict[str, np.ndarray],
    points: np.ndarray,
) -> Dict[str, float]:
    h, w = face_bgr.shape[:2]
    if h == 0 or w == 0:
        logger.warning(
            "Additional OpenCV metrics skipped: empty face ROI (h=%s, w=%s).",
            h,
            w,
        )
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


def _run_yolo_detection_stats(bgr_face: np.ndarray) -> tuple[int, float]:
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
        return 0, 0.0

    result = res[0]
    boxes = getattr(result, "boxes", None)
    if boxes is None:
        logger.warning("YOLO returned no boxes container on results object: %s", type(result))
        return 0, 0.0

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
    yolo_max_conf = max(conf_values) if conf_values else 0.0
    return int(count), float(yolo_max_conf)


def _run_yolo_lesion_count(bgr_face: np.ndarray) -> int:
    count, _ = _run_yolo_detection_stats(bgr_face)
    return count


def _compute_canonical_patch_metrics(
    face_bgr: np.ndarray,
    skin_mask: np.ndarray,
    regions: Dict[str, np.ndarray],
    points: np.ndarray,
    *,
    yolo_kept: int,
    yolo_max_conf: float,
) -> tuple[Dict[str, Any], Dict[str, str], Dict[str, float]]:
    h, w = face_bgr.shape[:2]
    matrix: Dict[str, Any] = {}
    confidence: Dict[str, str] = {
        "localized_redness": "low",
        "texture_smoothness": "low",
        "pore_visibility": "low",
        "wrinkle_load": "low",
        "pigment_load": "low",
        "breakout_activity": "low",
    }
    raw_components: Dict[str, float] = {}

    if h == 0 or w == 0:
        return matrix, confidence, raw_components

    lab = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2LAB)
    gray = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2GRAY)

    glabella = _glabella_region_mask((h, w), points, skin_mask)
    face_landmarks_present = points.shape[0] > 0

    left_cheek = regions.get("left_cheek", np.zeros((h, w), dtype=np.uint8))
    right_cheek = regions.get("right_cheek", np.zeros((h, w), dtype=np.uint8))
    primary_cheek_mask = cv2.bitwise_and(cv2.bitwise_or(left_cheek, right_cheek), skin_mask)

    forehead = regions.get("forehead", np.zeros((h, w), dtype=np.uint8))
    nose_polygon = _nose_region_mask((h, w), points, skin_mask, apply_skin_mask=False)
    primary_t_zone_mask = cv2.bitwise_and(cv2.bitwise_or(forehead, nose_polygon), skin_mask)

    primary_cheek_pixels = int(cv2.countNonZero(primary_cheek_mask))
    primary_t_zone_pixels = int(cv2.countNonZero(primary_t_zone_mask))

    # Default ROI for canonical skin metrics: full-face skin contour.
    _, full_face_skin_mask = _build_pore_roi_masks((h, w), points, face_bgr, skin_mask)
    if cv2.countNonZero(full_face_skin_mask) <= 0:
        full_face_skin_mask = skin_mask.copy()
    full_face_pixels = int(cv2.countNonZero(full_face_skin_mask))
    skin_mask_pixels = int(cv2.countNonZero(skin_mask))
    skin_mask_failed = skin_mask_pixels <= 0
    raw_components["full_face_skin_pixels"] = float(full_face_pixels)
    raw_components["skin_mask_pixels"] = float(skin_mask_pixels)

    cheek_mask = primary_cheek_mask if primary_cheek_pixels > 0 else full_face_skin_mask
    texture_mask = primary_cheek_mask if primary_cheek_pixels > 0 else full_face_skin_mask
    wrinkle_mask = cv2.bitwise_or(glabella, texture_mask)

    primary_texture_pixels = int(cv2.countNonZero(texture_mask))
    primary_pigment_pixels = int(cv2.countNonZero(cheek_mask))

    fallback_used = False
    bbox_fallback_used = False
    core_roi_pixels = max(primary_texture_pixels, primary_pigment_pixels)
    sparse_primary_roi = (
        primary_t_zone_pixels <= 100
        or primary_cheek_pixels <= 100
        or core_roi_pixels < 5000
    )
    if face_landmarks_present and sparse_primary_roi:
        # Landmark bbox fallback does not depend on skin-mask success.
        min_xy = np.floor(np.min(points, axis=0)).astype(np.int32)
        max_xy = np.ceil(np.max(points, axis=0)).astype(np.int32)
        bbox_w = max(1, int(max_xy[0] - min_xy[0]))
        bbox_h = max(1, int(max_xy[1] - min_xy[1]))
        pad_x = max(1, int(round(bbox_w * 0.12)))
        pad_y = max(1, int(round(bbox_h * 0.12)))
        x0 = max(0, int(min_xy[0] - pad_x))
        y0 = max(0, int(min_xy[1] - pad_y))
        x1 = min(w, int(max_xy[0] + pad_x))
        y1 = min(h, int(max_xy[1] + pad_y))

        if x1 > x0 and y1 > y0:
            bbox_mask = np.zeros((h, w), dtype=np.uint8)
            bbox_mask[y0:y1, x0:x1] = 255
            cheek_mask = bbox_mask
            texture_mask = bbox_mask
            wrinkle_mask = cv2.bitwise_or(glabella, bbox_mask)
            fallback_used = True
            bbox_fallback_used = True

    raw_components["primary_cheek_roi_pixels"] = float(primary_cheek_pixels)
    raw_components["primary_t_zone_skin_pixels"] = float(primary_t_zone_pixels)
    raw_components["primary_texture_roi_pixels"] = float(primary_texture_pixels)
    raw_components["primary_pigment_roi_pixels"] = float(primary_pigment_pixels)
    raw_components["fallback_used"] = 1.0 if fallback_used else 0.0
    raw_components["skin_mask_failed"] = 1.0 if skin_mask_failed else 0.0
    raw_components["bbox_fallback_used"] = 1.0 if bbox_fallback_used else 0.0
    fallback_roi_pixels = int(cv2.countNonZero(texture_mask)) if fallback_used else 0
    raw_components["roi_after_fallback_pixels"] = float(fallback_roi_pixels)
    raw_components["fallback_texture_roi_pixels"] = float(fallback_roi_pixels)
    raw_components["fallback_pigment_roi_pixels"] = float(fallback_roi_pixels)
    raw_components["fallback_breakout_roi_pixels"] = float(fallback_roi_pixels)

    def _conf(pixel_count: int) -> str:
        if pixel_count >= 6000:
            return "high"
        if pixel_count >= 2000:
            return "medium"
        return "low"

    confidence_rank = {"low": 0, "medium": 1, "high": 2}

    def _max_conf(level_a: str, level_b: str) -> str:
        return level_a if confidence_rank.get(level_a, 0) >= confidence_rank.get(level_b, 0) else level_b

    a_channel = lab[:, :, 1].astype(np.float32)
    l_channel = lab[:, :, 0].astype(np.float32)
    lap_abs = np.abs(cv2.Laplacian(gray, cv2.CV_32F, ksize=3))

    cheek_pixels = int(cv2.countNonZero(cheek_mask))
    raw_components["localized_redness_roi_pixels"] = float(cheek_pixels)
    if cheek_pixels > 0:
        cheek_a = a_channel[cheek_mask > 0]
        mean_a = float(np.mean(cheek_a)) if cheek_a.size > 0 else 128.0
        redness = ((mean_a - 128.0) / 30.0) * 100.0
        matrix["localized_redness"] = round(float(np.clip(redness, 0.0, 100.0)), 1)
    confidence["localized_redness"] = _conf(cheek_pixels)

    texture_pixels = int(cv2.countNonZero(texture_mask))
    raw_components["texture_roi_pixels"] = float(texture_pixels)
    if texture_pixels > 0:
        texture_vals = gray[texture_mask > 0].astype(np.float32)
        local_mean = cv2.GaussianBlur(gray.astype(np.float32), (0, 0), 1.4)
        local_mean_sq = cv2.GaussianBlur((gray.astype(np.float32) ** 2), (0, 0), 1.4)
        local_var_map = np.clip(local_mean_sq - (local_mean ** 2), 0.0, None)
        local_var_vals = local_var_map[texture_mask > 0]
        lap_vals = lap_abs[texture_mask > 0]

        var_p80 = float(np.percentile(local_var_vals, 80)) if local_var_vals.size > 0 else 0.0
        lap_p80 = float(np.percentile(lap_vals, 80)) if lap_vals.size > 0 else 0.0
        texture_energy = (0.65 * np.sqrt(max(var_p80, 0.0))) + (0.35 * lap_p80)

        # Calibrated monotonic roughness blend to keep healthy skin in a
        # practical mid-band while still allowing low/high extremes.
        n_energy = float(np.clip((texture_energy - 8.0) / 22.0, 0.0, 1.0))
        n_var = float(np.clip((math.sqrt(max(var_p80, 0.0)) - 6.0) / 14.0, 0.0, 1.0))
        n_lap = float(np.clip((lap_p80 - 14.0) / 32.0, 0.0, 1.0))

        texture_spread = float(np.std(texture_vals)) if texture_vals.size > 0 else 0.0
        n_spread = float(np.clip((texture_spread - 18.0) / 32.0, 0.0, 1.0))

        roughness_index = (0.45 * n_energy) + (0.20 * n_var) + (0.20 * n_lap) + (0.15 * n_spread)
        roughness_index = float(np.clip(roughness_index, 0.0, 1.0))
        smoothness = 100.0 * (1.0 - math.pow(roughness_index, 1.10))
        if not math.isfinite(smoothness):
            smoothness = 100.0 * (1.0 - n_energy)
        matrix["texture_smoothness"] = round(float(np.clip(smoothness, 0.0, 100.0)), 1)

        texture_value = safe_float(matrix.get("texture_smoothness"))
        texture_signal_present = any(
            math.isfinite(float(v))
            for v in (var_p80, lap_p80, texture_energy, texture_spread)
        )
        if (texture_value is None or not math.isfinite(texture_value)) and texture_signal_present:
            fallback_energy = max(float(texture_energy), 0.0)
            smoothness_fallback = 100.0 - min(100.0, fallback_energy * 2.5)
            matrix["texture_smoothness"] = round(
                float(np.clip(smoothness_fallback, 0.0, 100.0)),
                1,
            )

        confidence["texture_smoothness"] = _signal_conf(
            texture_pixels,
            spread=texture_spread,
            low_spread=8.0,
            high_spread=16.0,
        )
        raw_components["texture_energy"] = round(float(texture_energy), 4)
        raw_components["texture_var_p80"] = round(float(var_p80), 4)
        raw_components["texture_lap_p80"] = round(float(lap_p80), 4)
        raw_components["texture_spread"] = round(float(texture_spread), 4)
        raw_components["texture_n_energy"] = round(float(n_energy), 4)
        raw_components["texture_n_var"] = round(float(n_var), 4)
        raw_components["texture_n_lap"] = round(float(n_lap), 4)
        raw_components["texture_n_spread"] = round(float(n_spread), 4)
        raw_components["texture_roughness_index"] = round(float(roughness_index), 4)
        raw_components["texture_smoothness_value"] = round(
            float(matrix.get("texture_smoothness", 0.0)),
            4,
        )
    else:
        confidence["texture_smoothness"] = "low"

    # If cheek ROI collapsed but fallback ROI has usable pixels, derive
    # localized redness from the same fallback ROI so medium/high confidence
    # does not end up with a missing value.
    if "localized_redness" not in matrix and texture_pixels > 0:
        fallback_a = a_channel[texture_mask > 0]
        if fallback_a.size > 0:
            fallback_mean_a = float(np.mean(fallback_a))
            fallback_redness = ((fallback_mean_a - 128.0) / 30.0) * 100.0
            matrix["localized_redness"] = round(
                float(np.clip(fallback_redness, 0.0, 100.0)),
                1,
            )
            confidence["localized_redness"] = _max_conf(
                confidence.get("localized_redness", "low"),
                _conf(texture_pixels),
            )

    # Pore extraction: ROI-locked, scale-normalized, and high-confidence gated.
    pose_pitch, pose_yaw = _compute_pose_pitch_yaw_from_landmarks(points)
    pose_ok = abs(pose_pitch) <= 20.0 and abs(pose_yaw) <= 18.0
    face_detected = points.shape[0] > 0
    pore_visibility_detected = False

    pore_l_norm, pore_mask_norm, pore_roi_pixels = _extract_normalized_pore_roi(
        face_bgr,
        points,
        skin_mask,
    )
    pore_fallback_used = False
    pore_fallback_pixels = 0
    raw_components["pores_roi_pixels"] = float(pore_roi_pixels)
    raw_components["pore_pose_pitch"] = round(float(pose_pitch), 4)
    raw_components["pore_pose_yaw"] = round(float(pose_yaw), 4)

    if (
        face_detected
        and pose_ok
        and pore_l_norm is not None
        and pore_mask_norm is not None
        and pore_roi_pixels > 5000
    ):
        blur_small = cv2.GaussianBlur(pore_l_norm, (0, 0), 1.0)
        blur_large = cv2.GaussianBlur(pore_l_norm, (0, 0), 2.0)
        dog = np.abs(blur_small - blur_large)
        dog_vals = dog[pore_mask_norm > 0]
        if dog_vals.size > 0:
            pore_response_mean = float(np.mean(dog_vals))
            pore_spread = float(np.std(dog_vals))
            pore_confidence = _pore_signal_conf(
                pore_roi_pixels,
                pore_spread,
            )
            confidence["pore_visibility"] = pore_confidence
            raw_components["pore_hf_energy"] = round(float(pore_response_mean), 4)
            raw_components["pore_spread"] = round(float(pore_spread), 4)

            if pore_confidence != "low":
                pores = 100.0 / (1.0 + math.exp(-(pore_response_mean - 7.5) / 1.9))
                matrix["pore_visibility"] = round(float(np.clip(pores, 0.0, 100.0)), 1)
                pore_visibility_detected = True
                logger.info(
                    "PORE SCORED value=%.1f confidence=%s roi_pixels=%d pitch=%.2f yaw=%.2f",
                    matrix["pore_visibility"],
                    pore_confidence,
                    pore_roi_pixels,
                    pose_pitch,
                    pose_yaw,
                )
            else:
                logger.info(
                    "PORE OMITTED reason=confidence_%s roi_pixels=%d",
                    pore_confidence,
                    pore_roi_pixels,
                )
        else:
            confidence["pore_visibility"] = "low"
            logger.info("PORE OMITTED reason=empty_signal")
    else:
        confidence["pore_visibility"] = "low"
        logger.info(
            "PORE OMITTED reason=gate_failed face_detected=%s pose_ok=%s roi_pixels=%d pitch=%.2f yaw=%.2f",
            face_detected,
            pose_ok,
            pore_roi_pixels,
            pose_pitch,
            pose_yaw,
        )

    # Fallback pore rescore when dedicated ROI is sparse but full-face skin ROI is usable.
    if (
        not pore_visibility_detected
        and face_landmarks_present
        and full_face_pixels >= 3000
        and pore_roi_pixels < 3000
    ):
        pore_fallback_mask = full_face_skin_mask > 0
        pore_fallback_values = lap_abs[pore_fallback_mask]
        pore_fallback_pixels = int(np.count_nonzero(pore_fallback_mask))
        if pore_fallback_values.size > 0 and pore_fallback_pixels > 0:
            pore_fallback_used = True
            pore_spread = float(np.std(pore_fallback_values))
            pore_confidence = _pore_signal_conf(pore_fallback_pixels, pore_spread)
            if pore_confidence != "low":
                pore_signal = float(np.percentile(pore_fallback_values, 90))
                pores = 100.0 / (1.0 + math.exp(-(pore_signal - 7.5) / 1.9))
                matrix["pore_visibility"] = round(float(np.clip(pores, 0.0, 100.0)), 1)
                pore_visibility_detected = True
                confidence["pore_visibility"] = _max_conf(
                    confidence.get("pore_visibility", "low"),
                    pore_confidence,
                )

    raw_components["primary_pore_roi_pixels"] = float(pore_roi_pixels)
    raw_components["fallback_pore_roi_pixels"] = float(pore_fallback_pixels if pore_fallback_used else 0)
    raw_components["pore_fallback_used"] = 1.0 if pore_fallback_used else 0.0

    wrinkle_pixels = int(cv2.countNonZero(wrinkle_mask))
    raw_components["wrinkle_roi_pixels"] = float(wrinkle_pixels)
    if wrinkle_pixels > 0:
        edges = cv2.Canny(gray, 70, 140)
        edge_ratio = float(np.count_nonzero(np.logical_and(edges > 0, wrinkle_mask > 0))) / max(float(wrinkle_pixels), 1.0)
        wrinkle = edge_ratio * 240.0
        matrix["wrinkle_load"] = round(float(np.clip(wrinkle, 0.0, 100.0)), 1)
    confidence["wrinkle_load"] = _conf(wrinkle_pixels)

    if cheek_pixels > 0:
        cheek_l = l_channel[cheek_mask > 0]
        cheek_a = lab[:, :, 1].astype(np.float32)[cheek_mask > 0]
        cheek_b = lab[:, :, 2].astype(np.float32)[cheek_mask > 0]
        if cheek_a.size > 0 and cheek_b.size > 0:
            mean_a = float(np.mean(cheek_a))
            mean_b = float(np.mean(cheek_b))
            chroma_dev = np.sqrt((cheek_a - mean_a) ** 2 + (cheek_b - mean_b) ** 2)
            pigment_dev = float(np.percentile(chroma_dev, 85)) if chroma_dev.size > 0 else 0.0
        else:
            pigment_dev = 0.0

        l_contrast = float(np.std(cheek_l)) if cheek_l.size > 0 else 0.0
        pigment_signal = (0.72 * pigment_dev) + (0.28 * l_contrast)
        # Shifted center/slope preserves rank ordering while reducing
        # high-end clustering for common skin presentations.
        pigment = 100.0 / (1.0 + math.exp(-(pigment_signal - 18.0) / 4.0))
        matrix["pigment_load"] = round(float(np.clip(pigment, 0.0, 100.0)), 1)

        confidence["pigment_load"] = _signal_conf(
            cheek_pixels,
            spread=pigment_dev,
            low_spread=4.0,
            high_spread=8.5,
        )
        raw_components["pigment_chroma_dev_p85"] = round(float(pigment_dev), 4)
        raw_components["pigment_l_contrast"] = round(float(l_contrast), 4)
        raw_components["pigment_signal"] = round(float(pigment_signal), 4)
    else:
        confidence["pigment_load"] = "low"
    raw_components["pigment_roi_pixels"] = float(cheek_pixels)

    breakout = (yolo_kept * 14.0) + (yolo_max_conf * 22.0)
    breakout_clamped = round(float(np.clip(breakout, 0.0, 100.0)), 1)
    if breakout_clamped > 0.0:
        matrix["breakout_activity"] = breakout_clamped
        confidence["breakout_activity"] = "high" if yolo_max_conf >= 0.35 else "medium"
    raw_components["yolo_kept"] = float(yolo_kept)
    raw_components["yolo_max_conf"] = round(float(yolo_max_conf), 4)
    raw_components["breakout_roi_pixels"] = float(full_face_pixels)

    if fallback_used and full_face_pixels >= 3000:
        for key in (
            "localized_redness",
            "texture_smoothness",
            "pigment_load",
            "wrinkle_load",
            "breakout_activity",
        ):
            if key not in matrix:
                continue
            if confidence.get(key) == "low":
                confidence[key] = "medium"

    if full_face_pixels >= 3000:
        if "pore_visibility" in matrix and confidence.get("pore_visibility") == "low":
            confidence["pore_visibility"] = "medium"
        if "breakout_activity" in matrix and confidence.get("breakout_activity") == "low":
            confidence["breakout_activity"] = "medium"

    return matrix, confidence, raw_components


def _coalesce_metric_aliases(metrics: Dict[str, float]) -> Dict[str, float]:
    def _maybe_float(value: Any) -> float | None:
        try:
            if value is None:
                return None
            numeric = float(value)
        except Exception:
            return None
        return numeric if math.isfinite(numeric) else None

    alias_to_canonical = {
        "redness": "localized_redness",
        "redness_score": "localized_redness",
        "localized_redness_score": "localized_redness",
        "texture": "texture_smoothness",
        "smoothness": "texture_smoothness",
        "smoothness_score": "texture_smoothness",
        "pores": "pore_visibility",
        "pore": "pore_visibility",
        "pore_score": "pore_visibility",
        "acne_score": "breakout_activity",
        "breakout_score": "breakout_activity",
        "breakouts": "breakout_activity",
        "sebum": "sebum_excess_oil_gloss",
        "sebum_score": "sebum_excess_oil_gloss",
        "flushing": "diffuse_flushing_erythema",
        "erythema": "diffuse_flushing_erythema",
        "radiance": "skin_tone_radiance_evenness",
        "evenness": "skin_tone_radiance_evenness",
        "glabellar_11_lines_depth": "glabellar_wrinkle_depth",
        "pore_contraction": "pore_contraction_index",
    }

    out = dict(metrics)
    for alias, canonical in alias_to_canonical.items():
        canonical_value = _maybe_float(out.get(canonical))
        if canonical_value is not None and canonical_value > 0.0:
            continue
        alias_value = _maybe_float(out.get(alias))
        if alias_value is not None:
            out[canonical] = alias_value

    if "glabellar_wrinkle_depth" in out:
        wrinkle_value = _maybe_float(out.get("glabellar_wrinkle_depth"))
        if wrinkle_value is not None:
          out.setdefault("glabellar_11_lines_depth", wrinkle_value)
    return out


def _ensure_valid_metric_value(
    metric_name: str,
    value: float,
    *,
    fallback_value: float,
    replace_zero_with_fallback: bool = True,
) -> float:
    candidate = value
    if not isinstance(candidate, (int, float)) or not math.isfinite(float(candidate)):
        logger.warning(
            "Metric '%s' was non-finite (%s). Using fallback %.3f.",
            metric_name,
            value,
            fallback_value,
        )
        candidate = fallback_value

    candidate = float(np.clip(float(candidate), 0.0, 100.0))
    if candidate <= 0.0 and replace_zero_with_fallback:
        logger.warning(
            "Metric '%s' resolved to %.3f. Using non-zero fallback from image signal.",
            metric_name,
            candidate,
        )
        candidate = float(np.clip(max(fallback_value, 0.1), 0.0, 100.0))
    return round(candidate, 1)


def _normalize_metric_payload_values(metrics: Dict[str, Any]) -> Dict[str, Any]:
    ten_point_keys = {
        "redness",
        "texture",
        "wrinkle",
        "wrinkles",
        "pores",
        "pore",
        "darkspots",
        "elasticity",
        "acneseverity",
        "rosaceaseverity",
        "swelling",
        "firmness",
        "fatretention",
        "overallhealingscore",
    }
    normalized: Dict[str, Any] = {}
    for key, value in metrics.items():
        if value is None:
            normalized[key] = None
            continue
        try:
            numeric = float(value)
        except Exception:
            numeric = 0.0
        if not math.isfinite(numeric):
            numeric = 0.0

        normalized_key = str(key).lower().replace("_", "")
        if normalized_key in ten_point_keys and 0.0 <= numeric <= 10.0:
            numeric *= 10.0

        normalized[key] = round(float(np.clip(numeric, 0.0, 100.0)), 1)
    return normalized


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
    return _coalesce_metric_aliases(baseline)


def _compute_trend_deltas(current_matrix: Dict[str, float], baseline_matrix: Dict[str, float]) -> Dict[str, float]:
    current_canonical = _coalesce_metric_aliases(current_matrix)
    baseline_canonical = _coalesce_metric_aliases(baseline_matrix)
    deltas: Dict[str, float] = {}
    # Metric directionality:
    # - Higher is better: positive deltas indicate improvement.
    # - Lower is better: positive deltas indicate improvement (decrease in defect load).
    higher_is_better = {
        "texture_smoothness",
        "skin_tone_radiance_evenness",
        "structural_firmness_elasticity",
    }

    for key, current_value in current_canonical.items():
        if key not in baseline_canonical:
            continue

        current = safe_float(current_value)
        baseline_value = safe_float(baseline_canonical[key])
        if current is None or baseline_value is None:
            continue

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


# Clinical advice tuning constants
ADVICE_SENSITIVITY_HIGH_THRESHOLD = 4.0
ADVICE_ACNE_HIGH_THRESHOLD = 2.0
ADVICE_SEBUM_HIGH_THRESHOLD = 40.0
ADVICE_SEBUM_MODERATE_THRESHOLD = 35.0
ADVICE_BREAKOUT_ACTIVITY_THRESHOLD = 25.0
ADVICE_STRUCTURAL_BURDEN_THRESHOLD = 20.0
ADVICE_DELTA_IMPROVING_THRESHOLD = -5.0
ADVICE_DELTA_WORSENING_THRESHOLD = 5.0

ADVICE_PRIORITY_WEIGHTS = {
    "barrier_redness_weight": 1.45,
    "barrier_compromised_bonus": 8.0,
    "barrier_sensitivity_offset": 3.0,
    "barrier_sensitivity_weight": 4.0,
    "barrier_sensitivity_multiplier": 1.35,
    "oil_breakout_weight": 1.05,
    "oil_sebum_weight": 0.95,
    "structural_weight": 0.90,
}

ADVICE_BARRIER_AVOID_INGREDIENTS = [
    "AHAs/BHAs > 2%",
    "L-Ascorbic Acid",
    "Strong Retinoids",
    "Physical Scrubs",
]

ADVICE_BARRIER_SOOTHING_ACTIVES = [
    "Centella Asiatica",
    "Azelaic Acid 10%",
    "Ceramides",
    "Panthenol",
]

ADVICE_ACNE_TARGET_ACTIVES = [
    "Salicylic Acid 2%",
    "Niacinamide 4-5%",
]


def generate_clinical_advice(
    metric_matrix: Dict[str, Any],
    trend_deltas: Dict[str, Any],
    safety_profile: Dict[str, Any],
) -> Dict[str, Any]:
    def _to_float(value: Any) -> float:
        try:
            numeric = float(value)
        except Exception:
            numeric = 0.0
        if not math.isfinite(numeric):
            return 0.0
        return float(numeric)

    metrics = _coalesce_metric_aliases(
        {
            str(key): _to_float(value)
            for key, value in (metric_matrix or {}).items()
        }
    )
    deltas = _coalesce_metric_aliases(
        {
            str(key): _to_float(value)
            for key, value in (trend_deltas or {}).items()
        }
    )

    compromised_barrier = bool(safety_profile.get("compromised_barrier", False))
    sensitivity_score = _to_float(safety_profile.get("sensitivity_score", 0.0))
    acne_score = _to_float(safety_profile.get("acne_score", 0.0))
    initial_baseline = bool(safety_profile.get("initial_baseline", False))

    localized_redness = _to_float(metrics.get("localized_redness", 0.0))
    diffuse_flushing = _to_float(metrics.get("diffuse_flushing_erythema", 0.0))
    breakout_activity = _to_float(metrics.get("breakout_activity", 0.0))
    sebum_gloss = _to_float(metrics.get("sebum_excess_oil_gloss", 0.0))
    wrinkle_load = _to_float(metrics.get("wrinkle_load", 0.0))
    glabellar_depth = _to_float(metrics.get("glabellar_wrinkle_depth", 0.0))
    pore_visibility = _to_float(metrics.get("pore_visibility", 0.0))

    redness_burden = max(localized_redness, diffuse_flushing)
    structural_burden = max(wrinkle_load, glabellar_depth, pore_visibility)
    sensitivity_multiplier = (
        ADVICE_PRIORITY_WEIGHTS["barrier_sensitivity_multiplier"]
        if (compromised_barrier or sensitivity_score >= ADVICE_SENSITIVITY_HIGH_THRESHOLD)
        else 1.0
    )

    priority_scores = {
        "barrier_reactivity": (
            redness_burden
            * ADVICE_PRIORITY_WEIGHTS["barrier_redness_weight"]
            * sensitivity_multiplier
        )
        + (
            ADVICE_PRIORITY_WEIGHTS["barrier_compromised_bonus"]
            if compromised_barrier
            else 0.0
        )
        + (
            max(
                0.0,
                sensitivity_score
                - ADVICE_PRIORITY_WEIGHTS["barrier_sensitivity_offset"],
            )
            * ADVICE_PRIORITY_WEIGHTS["barrier_sensitivity_weight"]
        ),
        "oil_breakout": (
            breakout_activity * ADVICE_PRIORITY_WEIGHTS["oil_breakout_weight"]
        ) + (sebum_gloss * ADVICE_PRIORITY_WEIGHTS["oil_sebum_weight"]),
        "structural_texture": structural_burden * ADVICE_PRIORITY_WEIGHTS["structural_weight"],
    }

    ranked_focus = sorted(
        priority_scores.items(),
        key=lambda item: item[1],
        reverse=True,
    )
    top_focus = ranked_focus[0][0] if ranked_focus else "barrier_reactivity"

    if top_focus == "barrier_reactivity":
        primary_skin_focus = (
            "Primary focus: barrier-reactive redness control and tolerance stabilization."
        )
    elif top_focus == "oil_breakout":
        primary_skin_focus = (
            "Primary focus: sebum-breakout regulation with pore-safe anti-inflammatory control."
        )
    else:
        primary_skin_focus = (
            "Primary focus: structural texture refinement and visible line/pore smoothing."
        )

    actionable_insights: list[Dict[str, Any]] = []

    base_avoid: list[str] = []
    base_actives: list[str] = []
    if compromised_barrier or sensitivity_score >= ADVICE_SENSITIVITY_HIGH_THRESHOLD:
        base_avoid.extend(ADVICE_BARRIER_AVOID_INGREDIENTS)
        base_actives.extend(ADVICE_BARRIER_SOOTHING_ACTIVES)

    if acne_score > ADVICE_ACNE_HIGH_THRESHOLD and sebum_gloss > ADVICE_SEBUM_HIGH_THRESHOLD:
        for active in ADVICE_ACNE_TARGET_ACTIVES:
            if active not in base_actives:
                base_actives.append(active)

    if top_focus == "barrier_reactivity":
        actionable_insights.append(
            {
                "title": "Barrier-First Redness De-escalation",
                "category": "high_priority",
                "summary": (
                    f"Diffuse/localized redness burden is elevated (index {redness_burden:.1f}). "
                    "Prioritize inflammation control before introducing stronger resurfacing actives."
                ),
                "recommended_actives": base_actives
                or ["Azelaic Acid 10%", "Centella Asiatica", "Ceramides"],
                "avoid_ingredients": base_avoid,
            }
        )

    if (
        breakout_activity > ADVICE_BREAKOUT_ACTIVITY_THRESHOLD
        or sebum_gloss > ADVICE_SEBUM_MODERATE_THRESHOLD
    ):
        oil_breakout_actives = ["Niacinamide 4-5%", "Zinc PCA"]
        if acne_score > ADVICE_ACNE_HIGH_THRESHOLD and sebum_gloss > ADVICE_SEBUM_HIGH_THRESHOLD:
            oil_breakout_actives = ["Salicylic Acid 2%", "Niacinamide 4-5%", "Zinc PCA"]
        actionable_insights.append(
            {
                "title": "Sebum + Breakout Control",
                "category": "secondary_priority",
                "summary": (
                    f"Breakout activity ({breakout_activity:.1f}) and oil gloss ({sebum_gloss:.1f}) "
                    "indicate comedogenic pressure. Keep pores clear with low-irritation keratolytic cadence."
                ),
                "recommended_actives": oil_breakout_actives,
                "avoid_ingredients": base_avoid,
            }
        )

    if structural_burden > ADVICE_STRUCTURAL_BURDEN_THRESHOLD:
        structural_actives = ["Peptides", "Bakuchiol", "Retinal (low strength)"]
        if compromised_barrier or sensitivity_score >= ADVICE_SENSITIVITY_HIGH_THRESHOLD:
            structural_actives = ["Peptides", "Panthenol", "Ceramides"]
        actionable_insights.append(
            {
                "title": "Structural Texture Refinement",
                "category": "tertiary_priority",
                "summary": (
                    f"Wrinkle/pore structural burden is present (index {structural_burden:.1f}). "
                    "Use gradual texture-repair cycles with barrier support to improve tolerance."
                ),
                "recommended_actives": structural_actives,
                "avoid_ingredients": base_avoid,
            }
        )

    negative_traits = {
        "localized_redness",
        "diffuse_flushing_erythema",
        "breakout_activity",
        "sebum_excess_oil_gloss",
        "pore_visibility",
        "wrinkle_load",
        "glabellar_wrinkle_depth",
        "pore_contraction_index",
    }
    pretty_names = {
        "localized_redness": "Localized Redness",
        "diffuse_flushing_erythema": "Diffuse Flushing",
        "breakout_activity": "Breakout Activity",
        "sebum_excess_oil_gloss": "Sebum & Oil Gloss",
        "pore_visibility": "Pore Visibility",
        "wrinkle_load": "Wrinkle Load",
        "glabellar_wrinkle_depth": "Glabellar Wrinkle Depth",
        "pore_contraction_index": "Pore Contraction Index",
    }

    if initial_baseline:
        actionable_insights.append(
            {
                "title": "Baseline Phase Guidance",
                "category": "baseline_phase",
                "summary": (
                    "Initial baseline captured. For the next 2-3 weeks, prioritize consistency, "
                    "barrier recovery, and gentle monitoring before escalating active intensity."
                ),
                "recommended_actives": [
                    "Ceramides",
                    "Panthenol",
                    "Niacinamide 2-4%",
                ],
                "avoid_ingredients": base_avoid,
            }
        )
    else:
        for key in negative_traits:
            if key not in deltas:
                continue
            delta = _to_float(deltas[key])
            label = pretty_names.get(key, key)
            if delta < ADVICE_DELTA_IMPROVING_THRESHOLD:
                actionable_insights.append(
                    {
                        "title": f"{label} Trend Improving",
                        "category": "delta_reinforcement",
                        "summary": (
                            f"{label} improved by {abs(delta):.1f}%. Current barrier and care cadence "
                            "appear effective; maintain consistency to consolidate gains."
                        ),
                        "recommended_actives": base_actives,
                        "avoid_ingredients": base_avoid,
                    }
                )
            elif delta > ADVICE_DELTA_WORSENING_THRESHOLD:
                summary = (
                    f"{label} increased by {delta:.1f}% - pause active exfoliants for 48 hours "
                    "and intensify barrier-repair layering before reintroducing stronger actives."
                )
                actionable_insights.append(
                    {
                        "title": f"{label} Requires Adjustment",
                        "category": "delta_troubleshooting",
                        "summary": summary,
                        "recommended_actives": base_actives
                        or ["Ceramides", "Panthenol", "Centella Asiatica"],
                        "avoid_ingredients": base_avoid,
                    }
                )

    if not actionable_insights:
        actionable_insights.append(
            {
                "title": "Balanced Maintenance Track",
                "category": "maintenance",
                "summary": (
                    "Metrics are relatively stable. Continue gentle cleansing, hydration, and UV defense "
                    "while monitoring weekly trend changes."
                ),
                "recommended_actives": base_actives or ["Ceramides", "Niacinamide 2-4%"],
                "avoid_ingredients": base_avoid,
            }
        )

    morning_steps = [
        "Low-irritation cleanser, then hydrating mist or serum.",
        "Apply targeted active for primary focus, then barrier moisturizer.",
        "Finish with broad-spectrum SPF 50 and reapply every 2-3 hours when outdoors.",
    ]
    evening_steps = [
        "Gentle cleanse without over-stripping.",
        "Use repair-focused treatment; alternate stronger actives only on tolerant nights.",
        "Seal with barrier cream; add occlusive support on high-reactivity days.",
    ]
    if initial_baseline:
        morning_steps = [
            "Use a non-foaming cleanser and hydrating serum.",
            "Apply barrier moisturizer and SPF 50 only.",
            "Avoid introducing multiple new actives in the same week.",
        ]
        evening_steps = [
            "Cleanse gently and avoid scrubbing tools.",
            "Apply ceramide/panthenol barrier repair layers.",
            "Defer strong exfoliants and high-strength retinoids until tolerance stabilizes.",
        ]

    return {
        "primary_skin_focus": primary_skin_focus,
        "actionable_insights": actionable_insights,
        "routine_adjustments": {
            "morning": {
                "focus": "Protect + calm + prevent daytime triggers",
                "steps": morning_steps,
            },
            "evening": {
                "focus": "Repair + adaptive treatment + barrier reinforcement",
                "steps": evening_steps,
            },
        },
    }


def analyze_skin_patch(
    bgr_image: np.ndarray,
    baseline_matrix: Dict[str, float] | None = None,
    quality_profile: Dict[str, Any] | None = None,
    baseline_image_bgr: np.ndarray | None = None,
) -> Dict[str, Any]:
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
    primary_landmarks, primary_landmark_count, primary_source = _extract_primary_landmarks(rgb)

    if primary_landmarks is None:
        raise RuntimeError(
            "No face detected by MediaPipe Face Mesh. Please avoid camera monitor reflection or glare noise."
        )

    logger.info(
        "MediaPipe face landmarks: source=%s faces=1 primary_landmarks=%d",
        primary_source,
        primary_landmark_count,
    )

    points = _landmarks_to_points(primary_landmarks, calibrated_image.shape[1], calibrated_image.shape[0])
    aligned_face, aligned_points = _align_and_crop_face(calibrated_image, points)
    norm = normalize_lighting_and_shadows(aligned_face)
    mask = _skin_mask(norm)

    norm_rgb = cv2.cvtColor(norm, cv2.COLOR_BGR2RGB)
    norm_landmarks, norm_landmark_count, norm_source = _extract_primary_landmarks(norm_rgb)
    if norm_landmarks is None:
        raise RuntimeError(
            "Could not derive dynamic facial regions from the normalized face patch. Retake photo in frontal lighting."
        )
    logger.info(
        "MediaPipe normalized face landmarks: source=%s faces=1 primary_landmarks=%d roi_shape=%s",
        norm_source,
        norm_landmark_count,
        tuple(norm.shape),
    )
    norm_points = _landmarks_to_points(norm_landmarks, norm.shape[1], norm.shape[0])
    regions = _region_masks(norm.shape[:2], mask, norm_points)

    baseline_ssim: float | None = None
    baseline_ssim_face: float | None = None
    baseline_ssim_global: float | None = None
    baseline_landmark_count = 0
    if baseline_image_bgr is not None and baseline_image_bgr.size > 0:
        baseline_norm, baseline_landmark_count = _prepare_normalized_face_patch_for_ssim(
            baseline_image_bgr
        )
        if baseline_norm is not None:
            baseline_ssim_face = _compute_ssim_gray(
                cv2.cvtColor(norm, cv2.COLOR_BGR2GRAY),
                cv2.cvtColor(baseline_norm, cv2.COLOR_BGR2GRAY),
            )
        current_global = _prepare_global_patch_for_ssim(calibrated_image)
        baseline_global = _prepare_global_patch_for_ssim(baseline_image_bgr)
        if current_global is not None and baseline_global is not None:
            baseline_ssim_global = _compute_ssim_gray(current_global, baseline_global)

        ssim_candidates = [v for v in [baseline_ssim_face, baseline_ssim_global] if v is not None]
        if ssim_candidates:
            baseline_ssim = float(max(ssim_candidates))
            logger.info(
                "SSIM baseline comparison=%.4f (face=%s global=%s)",
                baseline_ssim,
                "n/a" if baseline_ssim_face is None else f"{baseline_ssim_face:.4f}",
                "n/a" if baseline_ssim_global is None else f"{baseline_ssim_global:.4f}",
            )

    try:
        zone_metrics = _compute_zone_based_metrics(norm, mask, regions, norm_points)
    except Exception as exc:
        logger.warning(
            "Zone-based feature extraction failed; using fallbacks. Details: %s",
            exc,
        )
        zone_metrics = {
            "sebum_excess_oil_gloss": 0.0,
            "pore_visibility": None,
            "pore_visibility_detected": False,
            "localized_redness": 0.0,
            "diffuse_flushing_erythema": 0.0,
            "rosacea_severity": 0.0,
            "glabellar_11_lines_depth": 0.0,
            "under_eye_texture_density": 0.0,
            "under_eye_dark_circle_density": 0.0,
        }

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

    yolo_kept, yolo_max_conf = _run_yolo_detection_stats(norm)
    logger.info("YOLO lesion detector: boxes=%d max_conf=%.4f", yolo_kept, yolo_max_conf)
    acne_activity_score = float(np.clip(100.0 - (yolo_kept * 10.0), 0.0, 100.0))
    fingerprint = hashlib.sha256(norm.tobytes()).hexdigest()
    try:
        additional_metrics = _compute_additional_opencv_metrics(
            norm,
            mask,
            regions,
            norm_points,
        )
    except Exception as exc:
        logger.warning(
            "Additional feature extraction failed; using fallback values. Details: %s",
            exc,
        )
        additional_metrics = {
            "sebum_excess_oil_gloss": 0.0,
            "diffuse_flushing_erythema": 0.0,
            "skin_tone_radiance_evenness": 0.0,
        }

    try:
        structural_metrics = _compute_structural_opencv_metrics(
            norm,
            mask,
            regions,
            norm_points,
        )
    except Exception as exc:
        logger.warning(
            "Structural feature extraction failed; using fallback values. Details: %s",
            exc,
        )
        structural_metrics = {
            "glabellar_wrinkle_depth": 0.0,
            "pore_contraction_index": 0.0,
            "structural_firmness_elasticity": 0.0,
        }

    canonical_metric_matrix, metric_confidence, raw_components = _compute_canonical_patch_metrics(
        norm,
        mask,
        regions,
        norm_points,
        yolo_kept=yolo_kept,
        yolo_max_conf=yolo_max_conf,
    )

    # Confidence-aware gating using ROI support, landmark robustness, and signal sparsity.
    skin_ratio = float(cv2.countNonZero(mask)) / max(float(mask.size), 1.0)
    global_conf_downgrade = 0
    if skin_ratio < 0.16:
        global_conf_downgrade += 1
    if min(primary_landmark_count, norm_landmark_count) < 360:
        global_conf_downgrade += 1

    if float(raw_components.get("texture_spread", 0.0)) < 7.5:
        metric_confidence["texture_smoothness"] = _downgrade_confidence_level(
            metric_confidence.get("texture_smoothness", "low"),
            1,
        )
    pore_spread = raw_components.get("pore_spread")
    if pore_spread is None or float(pore_spread) < 1.0:
        metric_confidence["pore_visibility"] = _downgrade_confidence_level(
            metric_confidence.get("pore_visibility", "low"),
            1,
        )
    if float(raw_components.get("pigment_chroma_dev_p85", 0.0)) < 3.0:
        metric_confidence["pigment_load"] = _downgrade_confidence_level(
            metric_confidence.get("pigment_load", "low"),
            1,
        )

    canonical_metric_order = [
        "localized_redness",
        "texture_smoothness",
        "pigment_load",
        "pore_visibility",
        "wrinkle_load",
        "breakout_activity",
        "sebum_excess_oil_gloss",
        "diffuse_flushing_erythema",
        "skin_tone_radiance_evenness",
        "glabellar_wrinkle_depth",
        "under_eye_texture_density",
        "under_eye_dark_circle_density",
        "rosacea_severity",
        "structural_firmness_elasticity",
        "pore_contraction_index",
    ]

    confidence_rank = {"low": 0, "medium": 1, "high": 2}

    def _merge_confidence(primary: str, secondary: str) -> str:
        return primary if confidence_rank.get(primary, 0) >= confidence_rank.get(secondary, 0) else secondary

    def _conf_from_pixels_and_value(
        value: Any,
        pixel_count: int,
        *,
        high_pixels: int,
        medium_pixels: int,
    ) -> str:
        numeric = safe_float(value)
        if numeric is None or numeric <= 0.0:
            return "low"
        if pixel_count >= high_pixels:
            return "high"
        if pixel_count >= medium_pixels:
            return "medium"
        return "low"

    glabella_pixels = int(cv2.countNonZero(_glabella_region_mask(norm.shape[:2], norm_points, mask)))
    left_under_eye = _under_eye_region_mask(norm.shape[:2], norm_points, mask, side="left")
    right_under_eye = _under_eye_region_mask(norm.shape[:2], norm_points, mask, side="right")
    under_eye_pixels = int(cv2.countNonZero(cv2.bitwise_or(left_under_eye, right_under_eye)))
    full_face_pixels = int(raw_components.get("full_face_skin_pixels", cv2.countNonZero(mask)))

    supplemental_confidence = {
        "sebum_excess_oil_gloss": _conf_from_pixels_and_value(
            additional_metrics.get("sebum_excess_oil_gloss"),
            full_face_pixels,
            high_pixels=7000,
            medium_pixels=3000,
        ),
        "diffuse_flushing_erythema": _conf_from_pixels_and_value(
            additional_metrics.get("diffuse_flushing_erythema"),
            full_face_pixels,
            high_pixels=7000,
            medium_pixels=3000,
        ),
        "skin_tone_radiance_evenness": _conf_from_pixels_and_value(
            additional_metrics.get("skin_tone_radiance_evenness"),
            full_face_pixels,
            high_pixels=7000,
            medium_pixels=3000,
        ),
        "glabellar_wrinkle_depth": _conf_from_pixels_and_value(
            structural_metrics.get("glabellar_wrinkle_depth"),
            glabella_pixels,
            high_pixels=1200,
            medium_pixels=600,
        ),
        "under_eye_texture_density": _conf_from_pixels_and_value(
            zone_metrics.get("under_eye_texture_density"),
            under_eye_pixels,
            high_pixels=1500,
            medium_pixels=700,
        ),
        "under_eye_dark_circle_density": _conf_from_pixels_and_value(
            zone_metrics.get("under_eye_dark_circle_density"),
            under_eye_pixels,
            high_pixels=1500,
            medium_pixels=700,
        ),
        "rosacea_severity": _conf_from_pixels_and_value(
            zone_metrics.get("rosacea_severity"),
            full_face_pixels,
            high_pixels=7000,
            medium_pixels=3000,
        ),
        "structural_firmness_elasticity": _conf_from_pixels_and_value(
            structural_metrics.get("structural_firmness_elasticity"),
            full_face_pixels,
            high_pixels=7000,
            medium_pixels=3000,
        ),
        "pore_contraction_index": _conf_from_pixels_and_value(
            structural_metrics.get("pore_contraction_index"),
            full_face_pixels,
            high_pixels=7000,
            medium_pixels=3000,
        ),
    }

    for key, conf in supplemental_confidence.items():
        metric_confidence[key] = _merge_confidence(metric_confidence.get(key, "low"), conf)

    # Apply global confidence downgrade after all metric confidence inputs are assembled.
    for metric_key in canonical_metric_order:
        metric_confidence[metric_key] = _downgrade_confidence_level(
            metric_confidence.get(metric_key, "low"),
            global_conf_downgrade,
        )

    # Keep emitted pore confidence aligned with scorer output (high or medium).
    if "pore_visibility" in canonical_metric_matrix:
        metric_confidence["pore_visibility"] = _merge_confidence(
            metric_confidence.get("pore_visibility", "low"),
            "medium",
        )

    raw_components["skin_coverage_ratio"] = round(float(skin_ratio), 4)
    raw_components["primary_landmark_count"] = float(primary_landmark_count)
    raw_components["normalized_landmark_count"] = float(norm_landmark_count)
    if baseline_ssim is not None:
        raw_components["baseline_ssim"] = round(float(baseline_ssim), 4)
        if baseline_ssim_face is not None:
            raw_components["baseline_ssim_face"] = round(float(baseline_ssim_face), 4)
        if baseline_ssim_global is not None:
            raw_components["baseline_ssim_global"] = round(float(baseline_ssim_global), 4)
        raw_components["baseline_landmark_count"] = float(baseline_landmark_count)

    face_count = 1 if min(primary_landmark_count, norm_landmark_count) > 0 else 0
    roi_after_fallback_pixels = int(
        raw_components.get(
            "roi_after_fallback_pixels",
            raw_components.get("texture_roi_pixels", 0.0),
        )
    )

    texture_force_write = False
    texture_current = safe_float(canonical_metric_matrix.get("texture_smoothness"))
    if texture_current is None:
        var_p80 = safe_float(raw_components.get("texture_var_p80"))
        lap_p80 = safe_float(raw_components.get("texture_lap_p80"))
        texture_energy = safe_float(raw_components.get("texture_energy"))
        texture_spread = safe_float(raw_components.get("texture_spread"))
        signal_values = [v for v in (var_p80, lap_p80, texture_energy, texture_spread) if v is not None and math.isfinite(v)]
        if signal_values:
            var_term = max((var_p80 or 0.0) / 15.0, 0.0)
            lap_term = max((lap_p80 or 0.0) / 4.0, 0.0)
            smoothness = float(np.clip(100.0 - min(100.0, (var_term + lap_term) / 2.0), 0.0, 100.0))
            canonical_metric_matrix["texture_smoothness"] = round(smoothness, 1)
            texture_force_write = True
            if face_count >= 1:
                metric_confidence["texture_smoothness"] = _merge_confidence(
                    metric_confidence.get("texture_smoothness", "low"),
                    "medium",
                )

    redness_force_write = False
    redness_forced_value: float | None = None
    redness_current = safe_float(canonical_metric_matrix.get("localized_redness"))
    texture_roi_pixels = int(raw_components.get("texture_roi_pixels", 0.0))
    redness_needs_force = (
        redness_current is None
        or not math.isfinite(redness_current)
        or redness_current <= 0.0
    )
    if redness_needs_force and (roi_after_fallback_pixels > 3000 or texture_roi_pixels > 3000):
        bbox_fallback_used = bool(raw_components.get("bbox_fallback_used", 0.0) > 0.5)
        redness_roi = np.zeros(norm.shape[:2], dtype=np.uint8)
        if bbox_fallback_used and norm_points.size > 0:
            min_xy = np.floor(np.min(norm_points, axis=0)).astype(np.int32)
            max_xy = np.ceil(np.max(norm_points, axis=0)).astype(np.int32)
            bbox_w = max(1, int(max_xy[0] - min_xy[0]))
            bbox_h = max(1, int(max_xy[1] - min_xy[1]))
            pad_x = max(1, int(round(bbox_w * 0.12)))
            pad_y = max(1, int(round(bbox_h * 0.12)))
            x0 = max(0, int(min_xy[0] - pad_x))
            y0 = max(0, int(min_xy[1] - pad_y))
            x1 = min(norm.shape[1], int(max_xy[0] + pad_x))
            y1 = min(norm.shape[0], int(max_xy[1] + pad_y))
            if x1 > x0 and y1 > y0:
                redness_roi[y0:y1, x0:x1] = 255
        else:
            _, fallback_skin_mask = _build_pore_roi_masks(
                norm.shape[:2],
                norm_points,
                norm,
                mask,
            )
            redness_roi = fallback_skin_mask

        if int(cv2.countNonZero(redness_roi)) > 0:
            redness_values = a_channel[redness_roi > 0]
            if redness_values.size > 0:
                mean_a = float(np.mean(redness_values))
                redness = float(np.clip(((mean_a - 128.0) / 30.0) * 100.0, 0.0, 100.0))
                canonical_metric_matrix["localized_redness"] = round(redness, 1)
                redness_force_write = True
                redness_forced_value = canonical_metric_matrix["localized_redness"]
                if face_count >= 1:
                    metric_confidence["localized_redness"] = _merge_confidence(
                        metric_confidence.get("localized_redness", "low"),
                        "medium",
                    )

    raw_components["texture_force_write"] = 1.0 if texture_force_write else 0.0
    raw_components["redness_force_write"] = 1.0 if redness_force_write else 0.0

    candidate_values: Dict[str, Any] = {
        "localized_redness": canonical_metric_matrix.get("localized_redness"),
        "texture_smoothness": canonical_metric_matrix.get("texture_smoothness"),
        "pigment_load": canonical_metric_matrix.get("pigment_load"),
        "pore_visibility": canonical_metric_matrix.get("pore_visibility"),
        "wrinkle_load": canonical_metric_matrix.get("wrinkle_load"),
        "breakout_activity": canonical_metric_matrix.get("breakout_activity"),
        "sebum_excess_oil_gloss": additional_metrics.get("sebum_excess_oil_gloss"),
        "diffuse_flushing_erythema": additional_metrics.get("diffuse_flushing_erythema"),
        "skin_tone_radiance_evenness": additional_metrics.get("skin_tone_radiance_evenness"),
        "glabellar_wrinkle_depth": structural_metrics.get("glabellar_wrinkle_depth"),
        "under_eye_texture_density": zone_metrics.get("under_eye_texture_density"),
        "under_eye_dark_circle_density": zone_metrics.get("under_eye_dark_circle_density"),
        "rosacea_severity": zone_metrics.get("rosacea_severity"),
        "structural_firmness_elasticity": structural_metrics.get("structural_firmness_elasticity"),
        "pore_contraction_index": structural_metrics.get("pore_contraction_index"),
    }

    core_emit_keys = {
        "localized_redness",
        "texture_smoothness",
        "pigment_load",
        "pore_visibility",
        "wrinkle_load",
        "breakout_activity",
        "skin_tone_radiance_evenness",
        "rosacea_severity",
        "structural_firmness_elasticity",
    }

    if face_count >= 1 and roi_after_fallback_pixels >= 3000:
        for key in core_emit_keys:
            candidate_numeric = safe_float(candidate_values.get(key))
            if candidate_numeric is None or not math.isfinite(candidate_numeric) or candidate_numeric <= 0.0:
                continue
            if metric_confidence.get(key, "low") == "low":
                metric_confidence[key] = "medium"

    pore_visibility_detected = "pore_visibility" in canonical_metric_matrix
    metric_matrix: Dict[str, Any] = {}
    emitted_metric_keys: list[str] = []
    omitted_metric_reasons: Dict[str, str] = {}
    metric_status: Dict[str, str] = {}
    fallback_reason: Dict[str, str] = {}

    for metric_key in canonical_metric_order:
        raw_value = candidate_values.get(metric_key)
        numeric_value = safe_float(raw_value)
        confidence_level = metric_confidence.get(metric_key, "low")

        if metric_key == "pore_contraction_index" and "pore_contraction_index" not in structural_metrics:
            metric_status[metric_key] = "unavailable"
            omitted_metric_reasons[metric_key] = "formula_not_available"
            fallback_reason[metric_key] = "formula_not_available"
            continue

        if metric_key == "pore_visibility" and not pore_visibility_detected:
            metric_status[metric_key] = "unavailable"
            omitted_metric_reasons[metric_key] = "pore_gate_not_usable"
            fallback_reason[metric_key] = "pore_gate_not_usable"
            continue

        if numeric_value is None or not math.isfinite(numeric_value) or numeric_value <= 0.0:
            metric_status[metric_key] = "unavailable"
            omitted_metric_reasons[metric_key] = "non_usable_value"
            fallback_reason[metric_key] = "non_usable_value"
            continue

        is_usable_confidence = confidence_level == "high" or (
            confidence_level == "medium" and metric_key in core_emit_keys
        )
        if not is_usable_confidence:
            metric_status[metric_key] = "unavailable"
            omitted_metric_reasons[metric_key] = f"confidence_{confidence_level}"
            fallback_reason[metric_key] = f"confidence_{confidence_level}"
            continue

        rounded_value = round(float(np.clip(numeric_value, 0.0, 100.0)), 1)
        if rounded_value <= 0.0:
            metric_status[metric_key] = "unavailable"
            omitted_metric_reasons[metric_key] = "rounded_to_floor"
            fallback_reason[metric_key] = "rounded_to_floor"
            continue

        metric_matrix[metric_key] = rounded_value
        emitted_metric_keys.append(metric_key)
        metric_status[metric_key] = "computed"
        fallback_reason[metric_key] = f"confidence_{confidence_level}"

    metric_matrix = _normalize_metric_payload_values(metric_matrix)
    trend_metric_matrix = {
        key: value
        for key, value in metric_matrix.items()
        if key in canonical_metric_order
    }
    normalized_baseline_matrix = _normalize_metric_payload_values(
        baseline_matrix or {}
    )
    trend_deltas = _compute_trend_deltas(trend_metric_matrix, normalized_baseline_matrix)
    trend_deltas = _stabilize_trend_deltas_for_near_identical_scan(
        trend_deltas,
        trend_metric_matrix,
        normalized_baseline_matrix,
        baseline_ssim,
    )

    normalized_top_level_metrics = _normalize_metric_payload_values(
        {
            "calibrated_redness_score": calibrated_redness_score,
            "calibrated_smoothness_score": calibrated_smoothness_score,
            "acne_activity_score": acne_activity_score,
            "raw_pore_density": float(yolo_kept * 4),
            **trend_metric_matrix,
        }
    )
    metrics_raw_log = {
        "texture": {
            "roi_pixels": int(raw_components.get("texture_roi_pixels", 0.0)),
            "energy": raw_components.get("texture_energy"),
            "var_p80": raw_components.get("texture_var_p80"),
            "lap_p80": raw_components.get("texture_lap_p80"),
            "spread": raw_components.get("texture_spread"),
            "smoothness": metric_matrix.get("texture_smoothness"),
        },
        "pores": {
            "roi_pixels": int(raw_components.get("pores_roi_pixels", 0.0)),
            "hf_energy": raw_components.get("pore_hf_energy"),
            "spread": raw_components.get("pore_spread"),
        },
        "pigment": {
            "roi_pixels": int(raw_components.get("pigment_roi_pixels", 0.0)),
            "chroma_dev_p85": raw_components.get("pigment_chroma_dev_p85"),
            "l_contrast": raw_components.get("pigment_l_contrast"),
            "signal": raw_components.get("pigment_signal"),
        },
    }
    metrics_matrix_log = {
        k: metric_matrix.get(k)
        for k in canonical_metric_order
        if k in metric_matrix
    }
    metrics_conf_log = {
        k: metric_confidence.get(k, "low")
        for k in canonical_metric_order
    }

    logger.info("METRICS emitted_keys=%s", emitted_metric_keys)
    logger.info("METRICS omitted_keys=%s", omitted_metric_reasons)
    logger.info(
        "METRICS roi_debug skin_mask_failed=%s bbox_fallback_used=%s roi_after_fallback=%d primary_roi_pixels={cheek:%d,tzone:%d,texture:%d,pigment:%d,pore:%d,breakout:%d} fallback_used=%s fallback_roi_pixels={texture:%d,pigment:%d,pore:%d,breakout:%d} smoothness=%s emitted_keys=%s matrix_keys=%s",
        bool(raw_components.get("skin_mask_failed", 0.0) > 0.5),
        bool(raw_components.get("bbox_fallback_used", 0.0) > 0.5),
        int(raw_components.get("roi_after_fallback_pixels", 0.0)),
        int(raw_components.get("primary_cheek_roi_pixels", 0.0)),
        int(raw_components.get("primary_t_zone_skin_pixels", 0.0)),
        int(raw_components.get("primary_texture_roi_pixels", 0.0)),
        int(raw_components.get("primary_pigment_roi_pixels", 0.0)),
        int(raw_components.get("primary_pore_roi_pixels", 0.0)),
        int(raw_components.get("breakout_roi_pixels", 0.0)),
        bool(raw_components.get("fallback_used", 0.0) > 0.5),
        int(raw_components.get("fallback_texture_roi_pixels", 0.0)),
        int(raw_components.get("fallback_pigment_roi_pixels", 0.0)),
        int(raw_components.get("fallback_pore_roi_pixels", 0.0)),
        int(raw_components.get("fallback_breakout_roi_pixels", 0.0)),
        metric_matrix.get("texture_smoothness"),
        emitted_metric_keys,
        list(metric_matrix.keys()),
    )
    logger.info(
        "METRICS core_confidence=%s",
        {
            key: metric_confidence.get(key, "low")
            for key in (
                "localized_redness",
                "texture_smoothness",
                "pigment_load",
                "pore_visibility",
                "wrinkle_load",
                "breakout_activity",
                "skin_tone_radiance_evenness",
                "rosacea_severity",
                "structural_firmness_elasticity",
            )
        },
    )
    logger.info(
        "METRICS force_write texture_force_write=%s redness_force_write=%s redness_value=%s smoothness=%s",
        bool(raw_components.get("texture_force_write", 0.0) > 0.5),
        bool(raw_components.get("redness_force_write", 0.0) > 0.5),
        redness_forced_value,
        metric_matrix.get("texture_smoothness"),
    )
    logger.info(
        "METRICS core_add_flags redness_added=%s texture_added=%s smoothness=%s texture_force_write=%s redness_force_write=%s",
        "localized_redness" in metric_matrix,
        "texture_smoothness" in metric_matrix,
        metric_matrix.get("texture_smoothness"),
        bool(raw_components.get("texture_force_write", 0.0) > 0.5),
        bool(raw_components.get("redness_force_write", 0.0) > 0.5),
    )

    logger.info(
        "METRICS raw_components=%s",
        metrics_raw_log,
    )
    logger.info(
        "METRICS texture_raw_components=%s",
        metrics_raw_log.get("texture", {}),
    )
    logger.info(
        "METRICS matrix=%s",
        metrics_matrix_log,
    )
    logger.info(
        "METRICS texture_matrix=%s",
        {"texture_smoothness": metric_matrix.get("texture_smoothness")},
    )
    logger.info(
        "METRICS confidence=%s",
        metrics_conf_log,
    )

    low_conf_count = sum(1 for v in metrics_conf_log.values() if v == "low")
    low_confidence_majority = low_conf_count >= 4

    eye_tilt_degrees = float(
        abs(
            math.degrees(
                math.atan2(
                    float(points[263][1] - points[33][1]),
                    max(float(points[263][0] - points[33][0]), 1e-6),
                )
            )
        )
    )
    landmark_alignment_score = float(np.clip(1.0 - (eye_tilt_degrees / 28.0), 0.0, 1.0))

    confidence_score, confidence_hints = _build_confidence_profile(
        quality_profile or {},
        primary_landmark_count=primary_landmark_count,
        normalized_landmark_count=norm_landmark_count,
        landmark_alignment_score=landmark_alignment_score,
    )

    response_payload = {
        "calibrated_redness_score": normalized_top_level_metrics[
            "calibrated_redness_score"
        ],
        "calibrated_smoothness_score": normalized_top_level_metrics[
            "calibrated_smoothness_score"
        ],
        "acne_activity_score": normalized_top_level_metrics["acne_activity_score"],
        "raw_pore_density": normalized_top_level_metrics["raw_pore_density"],
        "metric_confidence": metric_confidence,
        "metric_status": metric_status,
        "fallback_reason": fallback_reason,
        "confidence_score": confidence_score,
        "confidence_hints": confidence_hints if confidence_score < 0.65 else [],
        "image_quality": quality_profile or {},
        "fingerprint": fingerprint,
        "calibration": calibration,
        "metric_matrix": metric_matrix,
        "trend_deltas": trend_deltas,
        "low_confidence_majority": low_confidence_majority,
        "low_confidence_count": low_conf_count,
        "model_debug": {
            "face_detected": True,
            "face_mesh_landmarks": int(primary_landmark_count),
            "normalized_face_mesh_landmarks": int(norm_landmark_count),
            "yolo_boxes": int(yolo_kept),
            "yolo_max_conf": round(float(yolo_max_conf), 4),
            "baseline_ssim": None if baseline_ssim is None else round(float(baseline_ssim), 4),
            "baseline_ssim_face": None if baseline_ssim_face is None else round(float(baseline_ssim_face), 4),
            "baseline_ssim_global": None if baseline_ssim_global is None else round(float(baseline_ssim_global), 4),
            "landmark_alignment_score": round(landmark_alignment_score, 3),
            "aligned_point_count": int(aligned_points.shape[0]),
        },
    }

    for key in (
        "localized_redness",
        "texture_smoothness",
        "pigment_load",
        "pore_visibility",
        "wrinkle_load",
        "breakout_activity",
        "sebum_excess_oil_gloss",
        "diffuse_flushing_erythema",
        "skin_tone_radiance_evenness",
        "glabellar_wrinkle_depth",
        "under_eye_texture_density",
        "under_eye_dark_circle_density",
        "rosacea_severity",
        "structural_firmness_elasticity",
        "pore_contraction_index",
    ):
        if key in normalized_top_level_metrics:
            response_payload[key] = normalized_top_level_metrics.get(key)

    return response_payload


@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        ensure_pipeline_ready()
        logger.info("Deterministic analysis pipeline initialized (YOLO + MediaPipe + OpenCV)")
    except FileNotFoundError as exc:
        logger.error("Analysis pipeline startup check failed: %s", exc)
        logger.error(
            "Startup action required: place the missing face model files in one of these directories: "
            "models/, backend/models/, or assets/models/ under project root (%s).",
            PROJECT_ROOT,
        )
        logger.error(
            "You can also set FACE_DETECTOR_MODEL_PATH and FACE_LANDMARK_MODEL_PATH to absolute file paths."
        )
        logger.error(
            "Expected detector files: face_detector.tflite or face_detection_short_range.tflite; "
            "expected landmark files: face_landmarks_detector.tflite or face_landmarker.task."
        )
    except Exception as exc:
        logger.error("Analysis pipeline startup check failed: %s", exc)
        logger.error(
            "Startup troubleshooting: verify MediaPipe installation, model file permissions, and configured "
            "FACE_DETECTOR_MODEL_PATH / FACE_LANDMARK_MODEL_PATH values."
        )
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
    min_face_fill_ratio = 0.15
    max_face_fill_ratio = 0.80
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
    primary_landmarks, _, _ = _extract_primary_landmarks(rgb)
    if primary_landmarks is None:
        raise HTTPException(
            status_code=400,
            detail=(
                "Camera hardware QA failed: no face could be localized in the incoming frame. "
                "Clinical troubleshooting: center your full face, remove glare, and avoid profile angles."
            ),
        )

    pts = _landmarks_to_points(primary_landmarks, w, h)
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

    # Enforces distance control. If the face takes up less than ~15% of the
    # frame, the user is too far for reliable signal. Allow up to 80% so
    # tighter framing (for example ratio ~= 0.707) can pass QA.
    face_area_ratio = float(((x1 - x0) * (y1 - y0)) / total_area)
    if face_area_ratio < min_face_fill_ratio or face_area_ratio > max_face_fill_ratio:
        logger.warning(
            "Camera hardware QA face-fill reject: ratio=%.3f min=%.2f max=%.2f",
            face_area_ratio,
            min_face_fill_ratio,
            max_face_fill_ratio,
        )
        raise HTTPException(
            status_code=400,
            detail=(
                f"Camera hardware QA failed: face fill ratio is out of range (ratio={face_area_ratio:.3f}, expected={min_face_fill_ratio:.2f}-{max_face_fill_ratio:.2f}). "
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
        baseline_image_b64 = (
            body.get("baselineImageBytes")
            or body.get("baseline_image_bytes")
            or body.get("baselineImage")
            or body.get("baseline_image")
        )
        baseline_matrix = _parse_baseline_metric_matrix(
            body.get("baselineMetricMatrix") or body.get("baseline_metric_matrix") or body.get("baselineMetrics")
        )

        if not image_b64:
            raise HTTPException(status_code=422, detail="Missing image data (imageBytes / image_bytes / image)")

        image_data = base64.b64decode(image_b64)
        logger.info("Photo received: size=%.1f KB", len(image_data) / 1024)

        baseline_image_bgr: np.ndarray | None = None
        if baseline_image_b64:
            try:
                baseline_raw = str(baseline_image_b64)
                if "," in baseline_raw and "base64" in baseline_raw[:40].lower():
                    baseline_raw = baseline_raw.split(",", 1)[1]
                baseline_bytes = base64.b64decode(baseline_raw)
                baseline_image_bgr = _decode_image_bytes(baseline_bytes)
            except Exception as exc:
                logger.info("Baseline image decode skipped for SSIM guard: %s", exc)

        normalized_image, quality_profile = assess_and_normalize_image(image_data)
        logger.info("/api/analyze-skin request matrix accepted for inference.")
        validate_camera_hardware_qa(normalized_image)
        result = analyze_skin_patch(
            normalized_image,
            baseline_matrix=baseline_matrix,
            quality_profile=quality_profile,
            baseline_image_bgr=baseline_image_bgr,
        )
        debug = result.get("model_debug", {})
        logger.info(
            "/api/analyze-skin model outputs: yolo_boxes=%s face_landmarks=%s normalized_landmarks=%s",
            debug.get("yolo_boxes"),
            debug.get("face_mesh_landmarks"),
            debug.get("normalized_face_mesh_landmarks"),
        )

        if "error" in result:
            raise RuntimeError(result["error"])

        opencv_metrics = {}
        for key in (
            "sebum_excess_oil_gloss",
            "diffuse_flushing_erythema",
            "skin_tone_radiance_evenness",
            "glabellar_wrinkle_depth",
            "pore_contraction_index",
            "structural_firmness_elasticity",
        ):
            raw_value = result.get(key)
            numeric_value = safe_float(raw_value)
            if numeric_value is None or not math.isfinite(numeric_value):
                continue
            rounded_value = round(float(np.clip(numeric_value, 0.0, 100.0)), 1)
            if rounded_value <= 0.0:
                continue
            opencv_metrics[key] = rounded_value

        response = {
            "status": "success",
            "text": "Deterministic skin analysis complete.",
            "modelUsed": "yolo+mediapipe+opencv-deterministic-v2",
            "confidence_score": result.get("confidence_score", 0.0),
            "confidence_hints": result.get("confidence_hints", []),
            "image_quality": result.get("image_quality", quality_profile),
            "metrics": result,
            "opencv_metrics": opencv_metrics,
        }
        # Compatibility shim for existing Flutter readers expecting top-level keys.
        response.update(result)
        return response

    except HTTPException:
        raise
    except RuntimeError as e:
        logger.error(f"Analysis runtime error: {e}")
        message = str(e)
        if _is_pipeline_init_error(message):
            raise HTTPException(status_code=400, detail=_FACE_DETECTION_UNAVAILABLE_DETAIL)
        raise HTTPException(
            status_code=503,
            detail=(
                "Skin analysis model pipeline unavailable. "
                f"Action: verify MediaPipe + YOLO model load. Details: {e}"
            ),
        )
    except Exception as e:
        logger.error(f"Analysis error: {e}")
        if _is_pipeline_init_error(str(e)):
            raise HTTPException(status_code=400, detail=_FACE_DETECTION_UNAVAILABLE_DETAIL)
        raise HTTPException(status_code=400, detail=str(e))


@app.post("/api/skin/analyze-single")
async def analyze_skin_single(
    image: UploadFile = File(...),
    baseline_image: UploadFile | None = File(None),
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
            img_bgr, quality_profile = assess_and_normalize_image(contents)
        except Exception as exc:
            raise HTTPException(status_code=400, detail="Corrupted image encoding matrix parameters.") from exc

        logger.info("/api/skin/analyze-single request matrix accepted for inference.")

        validate_camera_hardware_qa(img_bgr)

        baseline_image_bgr: np.ndarray | None = None
        if baseline_image is not None:
            try:
                baseline_contents = await baseline_image.read()
                if baseline_contents:
                    baseline_image_bgr = _decode_image_bytes(baseline_contents)
            except Exception as exc:
                logger.info("Baseline file decode skipped for SSIM guard: %s", exc)

        results = analyze_skin_patch(
            img_bgr,
            baseline_matrix=parsed_baseline_matrix,
            quality_profile=quality_profile,
            baseline_image_bgr=baseline_image_bgr,
        )
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
            "initial_baseline": len(parsed_baseline_matrix) == 0,
        }
        filtered = filter_safe_skin_routine(safety_metrics, recommended_products)
        advice = generate_clinical_advice(
            results.get("metric_matrix", {}),
            results.get("trend_deltas", {}),
            safety_metrics,
        )

        opencv_metrics = {}
        for key in (
            "sebum_excess_oil_gloss",
            "diffuse_flushing_erythema",
            "skin_tone_radiance_evenness",
            "glabellar_wrinkle_depth",
            "pore_contraction_index",
            "structural_firmness_elasticity",
        ):
            raw_value = results.get(key)
            numeric_value = safe_float(raw_value)
            if numeric_value is None or not math.isfinite(numeric_value):
                continue
            rounded_value = round(float(np.clip(numeric_value, 0.0, 100.0)), 1)
            if rounded_value <= 0.0:
                continue
            opencv_metrics[key] = rounded_value

        logger.info(
            "/api/skin/analyze-single completed: status=200 emitted_keys=%s matrix_keys=%s",
            list((results.get("metric_matrix") or {}).keys()),
            list((results.get("metric_matrix") or {}).keys()),
        )

        return {
            "status": "success",
            "confidence_score": results.get("confidence_score", 0.0),
            "confidence_hints": results.get("confidence_hints", []),
            "image_quality": results.get("image_quality", quality_profile),
            "face_detected": bool(results.get("model_debug", {}).get("face_detected", True)),
            "metrics": results,
            "metric_confidence": results.get("metric_confidence", {}),
            "metric_status": results.get("metric_status", {}),
            "fallback_reason": results.get("fallback_reason", {}),
            "metric_matrix": results.get("metric_matrix", {}),
            "trend_deltas": results.get("trend_deltas", {}),
            "yolo_boxes": int(results.get("model_debug", {}).get("yolo_boxes", 0)),
            "yolo_max_conf": float(results.get("model_debug", {}).get("yolo_max_conf", 0.0)),
            "opencv_metrics": opencv_metrics,
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
            "advice": advice,
        }

    except HTTPException:
        raise
    except RuntimeError as exc:
        message = str(exc)
        if _is_pipeline_init_error(message):
            raise HTTPException(status_code=400, detail=_FACE_DETECTION_UNAVAILABLE_DETAIL)
        status_code = 400 if "face" in message.lower() or "landmark" in message.lower() else 503
        raise HTTPException(status_code=status_code, detail=message)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        logger.error("Single-image analysis error: %s", exc)
        if _is_pipeline_init_error(str(exc)):
            raise HTTPException(status_code=400, detail=_FACE_DETECTION_UNAVAILABLE_DETAIL)
        raise HTTPException(status_code=400, detail=str(exc))


@app.post("/api/ai-coach")
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