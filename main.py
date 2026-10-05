import hashlib
import base64
import hmac
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
from fastapi.responses import JSONResponse
import google.genai as genai

from scin_experimental_models import ScinExperimentalModels

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

MIN_USABLE_CHEEK_PIXELS = 2000
MIN_USABLE_TEXTURE_ROI_PIXELS = MIN_USABLE_CHEEK_PIXELS
MIN_USABLE_TZONE_PIXELS = 1500

# apply_white_balance_calibration searches the outer image margin for a
# bright, low-chroma patch and treats it as a neutral color reference.
# Investigation (2026-08-07) against real casual selfies found it fires on
# <10% of frames and, when it does, can lock onto scene background
# (patterned fabric, hair) rather than a true neutral object -- injecting
# uncontrolled cross-scan noise into the exact metrics this pipeline is
# meant to keep clean. Disabled for the live capture/analyze path; the
# pre-capture lighting-quality gate (guided-capture face-ROI luma
# sampling) remains the sole mechanism for catching bad lighting. Kept as
# a flag (not deleted) in case a future guided flow with a real physical
# reference object wants to re-enable it.
ENABLE_WHITE_BALANCE_CALIBRATION = False


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
_SCIN_EXPERIMENTAL_MODELS: ScinExperimentalModels | None = None
_YUNET_FACE_DETECTOR_MODEL_PATH: str | None = None
_BODY_POSE_LANDMARKER = None
_BODY_SEGMENTATION_MODEL = None
_BODY_SEGMENTATION_MODEL_KIND = "none"
_BODY_PIPELINE_READY = False
_BODY_PIPELINE_ERROR = ""

# Body segmentation quality thresholds derived from the real validation set:
# valid legacy masks had ROI coverage >= 43.2% and centered foreground; the
# hard-negative candidate_body_7 mask had 38.5% coverage and foreground center
# x=70.5%. The uncertainty threshold is deliberately rounded below the
# custom-model hard-negative observation (10.83%) while leaving the legacy
# references, which had no material ROI uncertainty, unaffected.
BODY_SEGMENTATION_MIN_ROI_COVERAGE = 0.40
BODY_SEGMENTATION_MIN_FOREGROUND_CENTER_X = 0.35
BODY_SEGMENTATION_MAX_FOREGROUND_CENTER_X = 0.65
BODY_SEGMENTATION_MAX_UNCERTAINTY_FRACTION = 0.10

YUNET_PRECISE_LANDMARKS_MESSAGE = "We detected a face outline but couldn't get precise landmarks."
YUNET_PARTIAL_FACE_MESSAGE = "We found only a partial or obstructed face outline."
_YUNET_MIN_REASONABLE_FACE_AREA_FRACTION = 0.007
_YUNET_MIN_CENTER_X = 0.20
_YUNET_MAX_CENTER_X = 0.80
_YUNET_MIN_CENTER_Y = 0.08
_YUNET_MAX_CENTER_Y = 0.85


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


def _resolve_yunet_model_path() -> str | None:
    env_path = os.getenv("OPENCV_YUNET_MODEL_PATH", "").strip()
    candidates = []
    if env_path:
        candidates.append(Path(env_path))
    candidates.extend(
        [
            Path(PROJECT_ROOT) / "backend" / "models" / "face_detection_yunet_2023mar.onnx",
            Path(PROJECT_ROOT) / "assets" / "models" / "face_detection_yunet_2023mar.onnx",
            Path(PROJECT_ROOT) / "diagnostics" / "opencv_yunet" / "face_detection_yunet_2023mar.onnx",
        ]
    )
    for candidate in candidates:
        path = candidate if candidate.is_absolute() else Path(PROJECT_ROOT) / candidate
        if path.is_file():
            return str(path.resolve())
    return None


def _classify_yunet_face_outline(box: list[float], image_width: int, image_height: int) -> str:
    x0, y0, x1, y1 = box
    area_fraction = ((x1 - x0) * (y1 - y0)) / max(float(image_width * image_height), 1.0)
    center_x = (x0 + x1) / max(float(image_width) * 2.0, 1.0)
    center_y = (y0 + y1) / max(float(image_height) * 2.0, 1.0)
    if (
        area_fraction >= _YUNET_MIN_REASONABLE_FACE_AREA_FRACTION
        and _YUNET_MIN_CENTER_X <= center_x <= _YUNET_MAX_CENTER_X
        and _YUNET_MIN_CENTER_Y <= center_y <= _YUNET_MAX_CENTER_Y
    ):
        return "reasonable"
    return "partial"


def _detect_yunet_face_outline(bgr_image: np.ndarray) -> str | None:
    if not hasattr(cv2, "FaceDetectorYN_create"):
        return None
    model_path = _resolve_yunet_model_path()
    if model_path is None:
        return None
    if bgr_image is None or bgr_image.size == 0:
        return None
    h, w = bgr_image.shape[:2]
    try:
        detector = cv2.FaceDetectorYN_create(model_path, "", (w, h), 0.6, 0.3, 5000)
        _, faces = detector.detect(bgr_image)
    except Exception:
        logger.exception("OpenCV YuNet fallback face detection failed")
        return None
    if faces is None or len(faces) == 0:
        return None
    face = max(faces, key=lambda row: float(row[2] * row[3]))
    x, y, width, height = map(float, face[:4])
    return _classify_yunet_face_outline([x, y, x + width, y + height], w, h)


def _media_pipe_no_face_message(bgr_image: np.ndarray) -> str:
    outline = _detect_yunet_face_outline(bgr_image)
    if outline == "reasonable":
        return YUNET_PRECISE_LANDMARKS_MESSAGE
    if outline == "partial":
        return YUNET_PARTIAL_FACE_MESSAGE
    return "No face detected by MediaPipe Face Mesh. Please avoid camera monitor reflection or glare noise."


def ensure_body_pipeline_ready() -> Dict[str, str]:
    global _BODY_POSE_LANDMARKER, _BODY_SEGMENTATION_MODEL, _BODY_SEGMENTATION_MODEL_KIND, _BODY_PIPELINE_READY, _BODY_PIPELINE_ERROR

    if _BODY_PIPELINE_READY:
        return {"status": "ready"}

    if _BODY_PIPELINE_ERROR:
        raise RuntimeError(_BODY_PIPELINE_ERROR)

    if mp is None:
        _BODY_PIPELINE_ERROR = "MediaPipe is not installed. Run 'pip install mediapipe'."
        raise RuntimeError(_BODY_PIPELINE_ERROR)

    try:
        from mediapipe.tasks import python as mp_python
        from mediapipe.tasks.python import vision as mp_vision

        pose_candidates = [
            "pose_landmarker_lite.task",
            "pose_landmarker_full.task",
            "pose_landmarker_heavy.task",
        ]
        pose_model_path = None
        for candidate in pose_candidates:
            try:
                pose_model_path = _MODEL_PATH_RESOLVER.resolve(
                    env_var="POSE_LANDMARKER_MODEL_PATH",
                    candidate_filenames=[candidate],
                    purpose="MediaPipe body pose landmark model",
                )
                break
            except FileNotFoundError:
                continue

        if pose_model_path is not None:
            pose_options = mp_vision.PoseLandmarkerOptions(
                base_options=mp_python.BaseOptions(model_asset_path=pose_model_path),
                running_mode=mp_vision.RunningMode.IMAGE,
                num_poses=1,
            )
            _BODY_POSE_LANDMARKER = mp_vision.PoseLandmarker.create_from_options(pose_options)
            logger.info("Loaded MediaPipe pose landmarker model from: %s", pose_model_path)
        else:
            logger.warning(
                "No pose_landmarker *.task asset found for body tracking. "
                "Set POSE_LANDMARKER_MODEL_PATH to a downloaded MediaPipe pose task file."
            )
            _BODY_POSE_LANDMARKER = None

        segmentation_mode = os.getenv("BODY_SEGMENTATION_MODEL_MODE", "legacy").strip().lower()
        if segmentation_mode == "legacy":
            _BODY_SEGMENTATION_MODEL = mp.solutions.selfie_segmentation.SelfieSegmentation(
                model_selection=1,
            )
            _BODY_SEGMENTATION_MODEL_KIND = "legacy_landscape_builtin"
            logger.warning(
                "Initialized legacy built-in MediaPipe selfie segmentation "
                "(model_selection=1) for comparison mode."
            )
        else:
            segmentation_candidates = [
                "selfie_segmenter.tflite",
                "selfie_segmenter_v2.tflite",
            ]
            segmentation_model_path = None
            for candidate in segmentation_candidates:
                try:
                    segmentation_model_path = _MODEL_PATH_RESOLVER.resolve(
                        env_var="SELFIE_SEGMENTER_MODEL_PATH",
                        candidate_filenames=[candidate],
                        purpose="MediaPipe selfie segmentation model",
                    )
                    break
                except FileNotFoundError:
                    continue

            if segmentation_model_path is None:
                raise FileNotFoundError(
                    "No custom selfie segmentation model found. "
                    "Set SELFIE_SEGMENTER_MODEL_PATH or provide backend/models/selfie_segmenter.tflite."
                )
            segmenter_options = mp_vision.ImageSegmenterOptions(
                base_options=mp_python.BaseOptions(
                    model_asset_path=segmentation_model_path,
                ),
                running_mode=mp_vision.RunningMode.IMAGE,
                output_confidence_masks=True,
                output_category_mask=False,
            )
            _BODY_SEGMENTATION_MODEL = mp_vision.ImageSegmenter.create_from_options(
                segmenter_options,
            )
            _BODY_SEGMENTATION_MODEL_KIND = "custom_asset"
            logger.info(
                "Loaded custom MediaPipe selfie segmenter through Tasks API: %s",
                segmentation_model_path,
            )
        logger.info(
            "Initialized MediaPipe selfie segmentation for body silhouette masking kind=%s.",
            _BODY_SEGMENTATION_MODEL_KIND,
        )
        _BODY_PIPELINE_READY = True
        return {"status": "ready"}
    except Exception:
        logger.exception("Body silhouette pipeline failed during model initialization")
        _BODY_PIPELINE_ERROR = (
            "Body silhouette tracking unavailable. "
            "Download a MediaPipe pose task model and ensure mediapipe/selfie segmentation is installed."
        )
        raise RuntimeError(_BODY_PIPELINE_ERROR)


def ensure_pipeline_ready() -> Dict[str, str]:
    global _PIPELINE_READY, _PIPELINE_ERROR, _FACE_MESH, _FACE_LANDMARKER, _FACE_DETECTOR, _YOLO, _SCIN_EXPERIMENTAL_MODELS
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
            _SCIN_EXPERIMENTAL_MODELS = ScinExperimentalModels(PROJECT_ROOT)
            _SCIN_EXPERIMENTAL_MODELS.load()
            if _SCIN_EXPERIMENTAL_MODELS.available:
                logger.info("Loaded experimental SCIN classifiers")
            else:
                logger.warning(
                    "Experimental SCIN classifiers unavailable: %s",
                    _SCIN_EXPERIMENTAL_MODELS.load_error,
                )
            _PIPELINE_READY = True
            return {"status": "ready"}
        except RuntimeError:
            raise
        except Exception:
            logger.exception("Analysis pipeline failed during model initialization")
            _PIPELINE_ERROR = _FACE_DETECTION_UNAVAILABLE_DETAIL
            raise RuntimeError(_PIPELINE_ERROR)


def _body_pose_landmarks_for_image(rgb_image: np.ndarray):
    if _BODY_POSE_LANDMARKER is None:
        return None
    try:
        from mediapipe.tasks.python import vision as mp_vision
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_image)
        result = _BODY_POSE_LANDMARKER.detect(mp_image)
        if result.pose_landmarks:
            return result.pose_landmarks[0]
        return None
    except Exception:
        logger.exception("PoseLandmarker detection failed for body silhouette analysis")
        return None


def _silhouette_mask_from_image(
    rgb_image: np.ndarray,
    *,
    return_confidence: bool = False,
) -> np.ndarray | tuple[np.ndarray, np.ndarray]:
    if _BODY_SEGMENTATION_MODEL is None:
        empty = np.zeros(rgb_image.shape[:2], dtype=np.float32)
        return (empty.astype(np.uint8), empty) if return_confidence else empty.astype(np.uint8)

    try:
        if _BODY_SEGMENTATION_MODEL_KIND == "custom_asset":
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_image)
            result = _BODY_SEGMENTATION_MODEL.segment(mp_image)
            if not result.confidence_masks:
                empty = np.zeros(rgb_image.shape[:2], dtype=np.float32)
                return (empty.astype(np.uint8), empty) if return_confidence else empty.astype(np.uint8)
            mask = result.confidence_masks[0].numpy_view().astype(np.float32)
        else:
            result = _BODY_SEGMENTATION_MODEL.process(rgb_image)
            if result.segmentation_mask is None:
                empty = np.zeros(rgb_image.shape[:2], dtype=np.float32)
                return (empty.astype(np.uint8), empty) if return_confidence else empty.astype(np.uint8)
            mask = result.segmentation_mask.astype(np.float32)
        thresholded = (mask > 0.5).astype(np.uint8)
        return (thresholded, mask) if return_confidence else thresholded
    except Exception:
        logger.exception("Selfie segmentation failed for body silhouette analysis")
        empty = np.zeros(rgb_image.shape[:2], dtype=np.float32)
        return (empty.astype(np.uint8), empty) if return_confidence else empty.astype(np.uint8)


def _body_segmentation_quality_gate(
    mask: np.ndarray,
    confidence: np.ndarray,
    roi_bounds: tuple[int, int, int, int],
) -> tuple[bool, str, Dict[str, float]]:
    x0, y0, x1, y1 = roi_bounds
    roi_mask = mask[y0:y1, x0:x1] > 0
    roi_confidence = confidence[y0:y1, x0:x1]
    roi_area = max(int(roi_mask.size), 1)
    coverage = float(np.mean(roi_mask))
    uncertainty_fraction = float(
        np.mean((roi_confidence >= 0.4) & (roi_confidence <= 0.6))
    )
    ys, xs = np.where(roi_mask)
    foreground_center_x = 0.5
    if len(xs) > 0:
        foreground_center_x = float((xs.min() + xs.max()) / (2.0 * max(roi_mask.shape[1], 1)))

    stats = {
        "roi_coverage": coverage,
        "uncertainty_fraction": uncertainty_fraction,
        "foreground_center_x": foreground_center_x,
        "roi_pixels": float(roi_area),
    }
    reasons: list[str] = []
    if uncertainty_fraction > BODY_SEGMENTATION_MAX_UNCERTAINTY_FRACTION:
        reasons.append("segmentation confidence was ambiguous")
    if coverage < BODY_SEGMENTATION_MIN_ROI_COVERAGE:
        reasons.append("segmented foreground did not cover a plausible body region")
    if not BODY_SEGMENTATION_MIN_FOREGROUND_CENTER_X <= foreground_center_x <= BODY_SEGMENTATION_MAX_FOREGROUND_CENTER_X:
        reasons.append("segmented foreground was not centered in the body framing")
    if reasons:
        return False, "; ".join(reasons), stats
    return True, "", stats


def analyze_body_silhouette(image_bgr: np.ndarray, *, roi_name: str = "hip_buttock") -> Dict[str, Any]:
    ensure_body_pipeline_ready()

    rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)
    pose_landmarks = _body_pose_landmarks_for_image(rgb)
    if pose_landmarks is None or len(pose_landmarks) < 33:
        raise ValueError("Pose Landmarker could not detect a full body pose for silhouette analysis.")

    pose_points = np.array(
        [[lm.x, lm.y, getattr(lm, 'visibility', 0.0)] for lm in pose_landmarks],
        dtype=np.float32,
    )

    if pose_points.shape[0] < 33:
        raise ValueError("Detected pose has fewer than 33 landmarks; body silhouette analysis is not reliable.")

    image_h, image_w = image_bgr.shape[:2]
    pose_points_px = pose_points.copy()
    pose_points_px[:, 0] = pose_points[:, 0] * image_w
    pose_points_px[:, 1] = pose_points[:, 1] * image_h

    left_shoulder = pose_points_px[11]
    right_shoulder = pose_points_px[12]
    left_hip = pose_points_px[23]
    right_hip = pose_points_px[24]

    shoulder_mid = (left_shoulder[:2] + right_shoulder[:2]) / 2.0
    hip_mid = (left_hip[:2] + right_hip[:2]) / 2.0
    scale_reference_pixels = max(float(np.linalg.norm(shoulder_mid - hip_mid) * 1.25), 30.0)

    roi_y0 = int(max(0, min(left_hip[1], right_hip[1]) - 0.35 * scale_reference_pixels))
    roi_y1 = int(min(image_bgr.shape[0], max(left_hip[1], right_hip[1]) + 0.85 * scale_reference_pixels))
    roi_x0 = int(max(0, min(left_hip[0], right_hip[0]) - 0.50 * scale_reference_pixels))
    roi_x1 = int(min(image_bgr.shape[1], max(left_hip[0], right_hip[0]) + 0.50 * scale_reference_pixels))

    if roi_y1 <= roi_y0 or roi_x1 <= roi_x0:
        raise ValueError("Body silhouette ROI could not be derived from detected pose landmarks.")

    silhouette_mask, silhouette_confidence = _silhouette_mask_from_image(
        rgb,
        return_confidence=True,
    )
    gate_passed, gate_reason, gate_stats = _body_segmentation_quality_gate(
        silhouette_mask,
        silhouette_confidence,
        (roi_x0, roi_y0, roi_x1, roi_y1),
    )
    if not gate_passed:
        raise ValueError(
            "Unable to confirm full-body framing: "
            f"{gate_reason}. "
            f"roi_coverage={gate_stats['roi_coverage']:.3f}, "
            f"uncertainty_fraction={gate_stats['uncertainty_fraction']:.3f}, "
            f"foreground_center_x={gate_stats['foreground_center_x']:.3f}"
        )
    roi_mask = silhouette_mask[roi_y0:roi_y1, roi_x0:roi_x1]
    roi_pixel_count = int(np.count_nonzero(roi_mask > 0.5))
    normalized_area_index = float(roi_pixel_count / max(scale_reference_pixels, 1.0))

    visibility_scores = [
        float(pose_points[11][2]),
        float(pose_points[12][2]),
        float(pose_points[23][2]),
        float(pose_points[24][2]),
    ]
    confidence = float(np.clip(np.mean(visibility_scores), 0.0, 1.0))
    if np.count_nonzero(roi_mask) == 0:
        confidence *= 0.75

    logger.info(
        "BODY_SILHOUETTE_LOG roi=%s scale_reference_pixels=%.2f roi_pixel_count=%d normalized_area_index=%.4f confidence=%.4f image_size=%sx%s",
        roi_name,
        scale_reference_pixels,
        roi_pixel_count,
        normalized_area_index,
        confidence,
        image_bgr.shape[1],
        image_bgr.shape[0],
    )
    return {
        "status": "success",
        "roi_name": roi_name,
        "normalized_area_index": round(normalized_area_index, 6),
        "scale_reference_pixels": round(float(scale_reference_pixels), 2),
        "roi_pixel_count": roi_pixel_count,
        "confidence": round(confidence, 6),
        "body_pose_detected": True,
        "landmark_count": int(len(pose_landmarks)),
        "segmentation_quality": gate_stats,
    }


def normalize_lighting_and_shadows(bgr_image: np.ndarray) -> np.ndarray:
    # Deliberately no gray-world/chroma correction here: this runs on a
    # face-dominated crop, so "the average color is mostly warm skin tone"
    # is not a cast to neutralize (same failure mode the a*/b* recenter
    # step used to have). Only luminance (shadow/exposure) is flattened;
    # a*/b* pass through untouched so genuine redness survives.
    lab = cv2.cvtColor(bgr_image, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)

    # Stronger illumination flattening: CLAHE on L with clinically-safe limits.
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    l_eq = clahe.apply(l)

    merged = cv2.merge((l_eq, a, b))
    return cv2.cvtColor(merged, cv2.COLOR_LAB2BGR)


def _apply_capture_white_balance_correction(bgr_image: np.ndarray) -> Tuple[np.ndarray, Dict[str, Any]]:
    """Apply a restrained LAB neutral-axis correction before metric extraction."""
    if bgr_image is None or bgr_image.size == 0:
        return bgr_image, {
            "applied": False,
            "reason": "empty_image",
        }

    lab = cv2.cvtColor(bgr_image, cv2.COLOR_BGR2LAB)
    l_channel = lab[:, :, 0]
    a_channel = lab[:, :, 1].astype(np.float32)
    b_channel = lab[:, :, 2].astype(np.float32)
    chroma = np.sqrt((a_channel - 128.0) ** 2 + (b_channel - 128.0) ** 2)

    l_low = float(np.percentile(l_channel, 35))
    l_high = float(np.percentile(l_channel, 98))
    chroma_ceiling = min(18.0, float(np.percentile(chroma, 35)) + 4.0)
    candidates = np.logical_and.reduce(
        [
            l_channel >= l_low,
            l_channel <= l_high,
            chroma <= chroma_ceiling,
        ]
    )

    minimum_pixels = max(800, int(bgr_image.shape[0] * bgr_image.shape[1] * 0.01))
    candidate_count = int(np.count_nonzero(candidates))
    if candidate_count < minimum_pixels:
        return bgr_image.copy(), {
            "applied": False,
            "reason": "insufficient_neutral_pixels",
            "candidate_pixels": candidate_count,
            "minimum_pixels": minimum_pixels,
        }

    a_offset = float(np.median(a_channel[candidates]) - 128.0)
    b_offset = float(np.median(b_channel[candidates]) - 128.0)
    a_adjustment = float(np.clip(a_offset * 0.70, -8.0, 8.0))
    b_adjustment = float(np.clip(b_offset * 0.70, -8.0, 8.0))

    corrected_lab = lab.copy().astype(np.float32)
    corrected_lab[:, :, 1] = np.clip(corrected_lab[:, :, 1] - a_adjustment, 0.0, 255.0)
    corrected_lab[:, :, 2] = np.clip(corrected_lab[:, :, 2] - b_adjustment, 0.0, 255.0)
    corrected_bgr = cv2.cvtColor(corrected_lab.astype(np.uint8), cv2.COLOR_LAB2BGR)

    return corrected_bgr, {
        "applied": abs(a_adjustment) >= 0.25 or abs(b_adjustment) >= 0.25,
        "method": "lab_low_chroma_neutral_axis",
        "candidate_pixels": candidate_count,
        "a_adjustment": round(a_adjustment, 3),
        "b_adjustment": round(b_adjustment, 3),
    }


# Optional gray-card calibration. A user-marked card region's mean LAB is
# measured against a neutral target to produce a correction (delta_a,
# delta_b, l_gain) that a future integration can apply to a SEPARATE copy
# of the analyzed image before redness/rosacea/pigment scoring. This must
# never be applied to (or derived from) the image used by
# assess_and_normalize_image()'s quality_profile (lighting_mean_l,
# lighting_balance_score, confidence) — that signal has to keep reflecting
# the true, uncorrected capture, or a genuinely dim photo could have its
# low-light confidence downgrade masked by the very correction meant to fix
# its color, not its exposure gate. Whatever integration consumes this must
# insert its correction strictly after assess_and_normalize_image() returns
# and before analyze_skin_patch()/_compute_canonical_patch_metrics() runs.
#
# Target: OpenCV's 8-bit LAB encodes neutral chroma as a*=b*=128 by
# definition. A standard 18%-reflectance gray card measures L*≈49-50 under
# correct neutral exposure, which is 49.5 * 255/100 ≈ 126 — close enough to
# the same 128 midpoint already used for a*/b* elsewhere in this file that
# anchoring all three channels to 128 is a reasonable, consistent target
# rather than a separate constant to justify.
GRAY_CARD_NEUTRAL_TARGET = 128.0

# A user-drawn card region is a small, deliberately-cropped box (unlike the
# whole-frame neutral-pixel search in _apply_capture_white_balance_correction,
# which needs 800+ pixels out of a full photo) — 200 px is enough to average
# out sensor noise/JPEG blocking in a region that small without requiring an
# unreasonably large card mark.
GRAY_CARD_MIN_REGION_PIXELS = 200

# _apply_capture_white_balance_correction caps ITS correction at ±8 a*/b*
# units because it only nudges gently for ordinary ambient variation. A
# gray-card correction is meant to fix stronger casts than that pass already
# handles, so it must tolerate a much bigger measured offset. But it still
# needs a ceiling to reject a region that isn't a neutral card at all: skin
# tone commonly reads well off neutral (a*~140-150, b*~145-160 in this
# encoding, i.e. offset magnitude ~30-48), so 45 sits just below typical
# mis-marked-skin offsets while still accepting strong-but-real colored-light
# casts on an actual gray card (published incandescent/mixed-lighting neutral
# shifts commonly stay within this range).
GRAY_CARD_MAX_CHROMA_OFFSET = 45.0

# Reject a region that reads as crushed-black or blown-out-white: the mean
# color in either extreme is unreliable/clipped, and any gain computed from
# it would be untrustworthy regardless of the chroma check above.
GRAY_CARD_MIN_MEASURED_L = 20.0
GRAY_CARD_MAX_MEASURED_L = 240.0

# Even for an accepted region, clamp the resulting exposure gain itself.
# Requiring more than roughly half-to-double brightness scaling is a sign of
# a badly exposed or misidentified region rather than a fixable lighting
# cast, so the gain is clamped (not the whole correction rejected) to avoid
# an aggressive correction distorting the redness/pigment signal more than
# it fixes it.
GRAY_CARD_MIN_L_GAIN = 0.5
GRAY_CARD_MAX_L_GAIN = 2.0


def compute_gray_card_correction(card_region_lab: np.ndarray) -> Dict[str, Any]:
    """Measures a user-marked gray-card region's mean LAB (OpenCV's 0-255
    encoding) and returns the correction to apply toward a neutral target,
    or a rejection reason if the region doesn't plausibly look like a
    photographed neutral card. Pure measurement — does not touch any image
    pixels itself.
    """
    if card_region_lab is None or card_region_lab.size == 0:
        return {"accepted": False, "reason": "empty_region"}

    flat = card_region_lab.reshape(-1, 3).astype(np.float32)
    pixel_count = int(flat.shape[0])
    if pixel_count < GRAY_CARD_MIN_REGION_PIXELS:
        return {
            "accepted": False,
            "reason": "insufficient_region_pixels",
            "region_pixels": pixel_count,
            "minimum_pixels": GRAY_CARD_MIN_REGION_PIXELS,
        }

    measured_l = float(np.mean(flat[:, 0]))
    measured_a = float(np.mean(flat[:, 1]))
    measured_b = float(np.mean(flat[:, 2]))

    if measured_l < GRAY_CARD_MIN_MEASURED_L or measured_l > GRAY_CARD_MAX_MEASURED_L:
        return {
            "accepted": False,
            "reason": "implausible_exposure",
            "measured_l": round(measured_l, 2),
            "min_measured_l": GRAY_CARD_MIN_MEASURED_L,
            "max_measured_l": GRAY_CARD_MAX_MEASURED_L,
        }

    chroma_offset = float(
        math.sqrt(
            (measured_a - GRAY_CARD_NEUTRAL_TARGET) ** 2
            + (measured_b - GRAY_CARD_NEUTRAL_TARGET) ** 2
        )
    )
    if chroma_offset > GRAY_CARD_MAX_CHROMA_OFFSET:
        return {
            "accepted": False,
            "reason": "implausible_card_color",
            "measured_a": round(measured_a, 2),
            "measured_b": round(measured_b, 2),
            "chroma_offset": round(chroma_offset, 2),
            "max_chroma_offset": GRAY_CARD_MAX_CHROMA_OFFSET,
        }

    delta_a = GRAY_CARD_NEUTRAL_TARGET - measured_a
    delta_b = GRAY_CARD_NEUTRAL_TARGET - measured_b
    raw_l_gain = GRAY_CARD_NEUTRAL_TARGET / max(measured_l, 1e-6)
    l_gain = float(np.clip(raw_l_gain, GRAY_CARD_MIN_L_GAIN, GRAY_CARD_MAX_L_GAIN))

    return {
        "accepted": True,
        "region_pixels": pixel_count,
        "measured_l": round(measured_l, 2),
        "measured_a": round(measured_a, 2),
        "measured_b": round(measured_b, 2),
        "chroma_offset": round(chroma_offset, 2),
        "delta_a": round(float(delta_a), 3),
        "delta_b": round(float(delta_b), 3),
        "raw_l_gain": round(float(raw_l_gain), 4),
        "l_gain": round(l_gain, 4),
    }


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


def _signed_lab_value(value: float | None) -> float | None:
    """OpenCV 8-bit LAB stores a*/b* offset by +128; report them signed
    (neutral = 0, positive a* = red, positive b* = yellow)."""
    if value is None or not math.isfinite(float(value)):
        return None
    return round(float(value) - 128.0, 3)


def assess_and_normalize_image(image_bytes: bytes) -> Tuple[np.ndarray, Dict[str, Any]]:
    """Run image quality assessment and lighting normalization before extraction."""
    normalized_bgr, quality_profile, _ = _assess_and_normalize_image_with_pre_white_balance(
        image_bytes
    )
    return normalized_bgr, quality_profile


def _assess_and_normalize_image_with_pre_white_balance(
    image_bytes: bytes,
) -> Tuple[np.ndarray, Dict[str, Any], np.ndarray]:
    """Same as assess_and_normalize_image, plus a diagnostic-only copy of the
    image with the identical luminance normalization but no white balance.
    The third value never feeds a metric; it only lets analyze_skin_patch
    log the redness cheek's p95 a* as it was before white balance."""
    image_bgr = _decode_image_bytes(image_bytes)
    if image_bgr is None or image_bgr.size == 0:
        raise ValueError("Decoded image is empty for IQA preprocessing.")

    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    blur_score = float(cv2.Laplacian(gray, cv2.CV_64F, ksize=3).var())
    blur_threshold = float(os.getenv("IQA_BLUR_THRESHOLD", "80.0"))
    image_blurry = blur_score < blur_threshold

    pre_wb_lab = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2LAB)
    pre_wb_l, pre_wb_a, pre_wb_b = cv2.split(pre_wb_lab)

    white_balanced_bgr, white_balance_profile = _apply_capture_white_balance_correction(image_bgr)
    lab = cv2.cvtColor(white_balanced_bgr, cv2.COLOR_BGR2LAB)
    l_channel, a_channel, b_channel = cv2.split(lab)

    clahe = cv2.createCLAHE(clipLimit=2.2, tileGridSize=(8, 8))
    l_equalized = clahe.apply(l_channel)
    normalized_bgr = cv2.cvtColor(
        cv2.merge((l_equalized, a_channel, b_channel)),
        cv2.COLOR_LAB2BGR,
    )
    pre_wb_clahe = cv2.createCLAHE(clipLimit=2.2, tileGridSize=(8, 8))
    pre_white_balance_bgr = cv2.cvtColor(
        cv2.merge((pre_wb_clahe.apply(pre_wb_l), pre_wb_a, pre_wb_b)),
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

    # Diagnostic-only: the a*/b* shift _apply_capture_white_balance_correction
    # subtracted (after its +/-8 clip), 0.0 when it skipped correction.
    wb_a_post_clip = float(white_balance_profile.get("a_adjustment", 0.0) or 0.0)
    wb_b_post_clip = float(white_balance_profile.get("b_adjustment", 0.0) or 0.0)

    return normalized_bgr, {
        "blur_score": round(blur_score, 2),
        "blur_threshold": round(blur_threshold, 2),
        "image_blurry": image_blurry,
        "lighting_mean_l": round(mean_l, 2),
        "lighting_std_l": round(std_l, 2),
        "chroma_cast": round(chroma_cast, 2),
        "sharpness_score": round(sharpness_score, 3),
        "lighting_balance_score": round(lighting_balance_score, 3),
        "white_balance_profile": white_balance_profile,
        "preprocess_warnings": warnings,
        "color_lab_units": "signed_a_b_neutral_0",
        "whole_image_mean_a_before_wb": _signed_lab_value(float(np.mean(pre_wb_a))),
        "whole_image_mean_b_before_wb": _signed_lab_value(float(np.mean(pre_wb_b))),
        "whole_image_mean_a_after_wb": _signed_lab_value(float(np.mean(a_channel))),
        "whole_image_mean_b_after_wb": _signed_lab_value(float(np.mean(b_channel))),
        "wb_a_adjustment_post_clip": round(wb_a_post_clip, 3),
        "wb_b_adjustment_post_clip": round(wb_b_post_clip, 3),
    }, pre_white_balance_bgr


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
            chroma_distance <= 12.0,
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
    minimum_area = max(900.0, float(h * w) * 0.004)
    if contour_area < minimum_area:
        return image.copy(), {
            "reference_found": False,
            "reason": "reference_too_small",
            "detected_area": round(contour_area, 2),
            "minimum_area": round(minimum_area, 2),
        }

    x, y, bw, bh = cv2.boundingRect(contour)
    short_side = float(max(1, min(bw, bh)))
    long_side = float(max(bw, bh))
    aspect_ratio = long_side / short_side
    if aspect_ratio > 4.0:
        logger.info(
            "WB calibration skipped: reason=reference_aspect_ratio_invalid bbox=%s aspect_ratio=%.3f",
            [int(x), int(y), int(bw), int(bh)],
            aspect_ratio,
        )
        return image.copy(), {
            "reference_found": False,
            "reason": "reference_aspect_ratio_invalid",
            "reference_bbox": [int(x), int(y), int(bw), int(bh)],
            "reference_aspect_ratio": round(aspect_ratio, 4),
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
    raw_rgb_gains = 245.0 / np.maximum(ref_bgr_mean, 1.0)
    raw_rgb_corrected = np.clip(image.astype(np.float32) * raw_rgb_gains.reshape(1, 1, 3), 0, 255).astype(np.uint8)
    raw_corrected_lab = cv2.cvtColor(raw_rgb_corrected, cv2.COLOR_BGR2LAB).astype(np.float32)
    raw_reference_lab = raw_corrected_lab[reference_pixels]
    raw_lab_shift = np.array(
        [
            245.0 - float(raw_reference_lab[:, 0].mean()),
            128.0 - float(raw_reference_lab[:, 1].mean()),
            128.0 - float(raw_reference_lab[:, 2].mean()),
        ],
        dtype=np.float32,
    )
    raw_gain_min = float(np.min(raw_rgb_gains))
    raw_gain_max = float(np.max(raw_rgb_gains))
    if raw_gain_min < 0.85 or raw_gain_max > 1.15 or float(np.max(np.abs(raw_lab_shift))) > 8.0:
        logger.info(
            "WB calibration skipped: reason=reference_requires_extreme_correction bbox=%s raw_rgb_gains_bgr=%s raw_lab_shift=%s",
            [int(x), int(y), int(bw), int(bh)],
            [round(float(v), 4) for v in raw_rgb_gains.tolist()],
            [round(float(v), 4) for v in raw_lab_shift.tolist()],
        )
        return image.copy(), {
            "reference_found": False,
            "reason": "reference_requires_extreme_correction",
            "reference_bbox": [int(x), int(y), int(bw), int(bh)],
            "raw_rgb_gains_bgr": [round(float(v), 4) for v in raw_rgb_gains.tolist()],
            "raw_lab_shift": [round(float(v), 4) for v in raw_lab_shift.tolist()],
        }

    rgb_gains = np.clip(raw_rgb_gains, 0.82, 1.18)
    rgb_corrected = np.clip(image.astype(np.float32) * rgb_gains.reshape(1, 1, 3), 0, 255).astype(np.uint8)

    corrected_lab = cv2.cvtColor(rgb_corrected, cv2.COLOR_BGR2LAB).astype(np.float32)
    reference_lab = corrected_lab[reference_pixels]
    lab_shift = np.array(
        [
            np.clip(raw_lab_shift[0], -12.0, 12.0),
            np.clip(raw_lab_shift[1], -10.0, 10.0),
            np.clip(raw_lab_shift[2], -10.0, 10.0),
        ],
        dtype=np.float32,
    )
    corrected_lab[:, :, 0] = np.clip(corrected_lab[:, :, 0] + lab_shift[0], 0, 255)
    corrected_lab[:, :, 1] = np.clip(corrected_lab[:, :, 1] + lab_shift[1], 0, 255)
    corrected_lab[:, :, 2] = np.clip(corrected_lab[:, :, 2] + lab_shift[2], 0, 255)
    calibrated = cv2.cvtColor(corrected_lab.astype(np.uint8), cv2.COLOR_LAB2BGR)

    return calibrated, {
        "reference_found": True,
        "reference_bbox": [int(x), int(y), int(bw), int(bh)],
        "reference_area_ratio": round(contour_area / max(float(h * w), 1.0), 5),
        "raw_rgb_gains_bgr": [round(float(v), 4) for v in raw_rgb_gains.tolist()],
        "rgb_gains_bgr": [round(float(v), 4) for v in rgb_gains.tolist()],
        "raw_lab_shift": [round(float(v), 4) for v in raw_lab_shift.tolist()],
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


def _as_binary_mask(mask: np.ndarray, shape: Tuple[int, int] | None = None) -> np.ndarray:
    out = np.asarray(mask)
    if out.ndim == 3:
        out = out[:, :, 0]
    if shape is not None and tuple(out.shape[:2]) != tuple(shape):
        out = cv2.resize(out, (shape[1], shape[0]), interpolation=cv2.INTER_NEAREST)
    return np.where(out > 0, 255, 0).astype(np.uint8)


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


def _expanded_polygon_points(
    polygon: np.ndarray,
    shape: Tuple[int, int],
    *,
    scale: float = 0.12,
) -> np.ndarray:
    h, w = shape
    poly = np.asarray(polygon, dtype=np.float32).reshape(-1, 2)
    if poly.shape[0] < 3:
        return poly

    center = np.mean(poly, axis=0)
    expanded = center + ((poly - center) * (1.0 + scale))
    expanded[:, 0] = np.clip(expanded[:, 0], 0, w - 1)
    expanded[:, 1] = np.clip(expanded[:, 1], 0, h - 1)
    return expanded.astype(np.float32)


def _face_oval_mask(shape: Tuple[int, int], points: np.ndarray) -> np.ndarray:
    face_oval_ids = [
        10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288,
        397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136,
        172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109,
    ]
    valid_ids = [idx for idx in face_oval_ids if 0 <= idx < points.shape[0]]
    if len(valid_ids) < 3:
        return np.zeros(shape, dtype=np.uint8)
    return _polygon_mask(shape, points[valid_ids])


def _expand_mask_from_contour(
    mask: np.ndarray,
    shape: Tuple[int, int],
    *,
    scale: float = 0.12,
    dilate_px: int = 5,
) -> np.ndarray:
    binary_mask = _as_binary_mask(mask, shape)
    contours, _ = cv2.findContours(binary_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    expanded = np.zeros(shape, dtype=np.uint8)
    for contour in contours:
        if contour is None or contour.shape[0] < 3:
            continue
        expanded_points = _expanded_polygon_points(contour.reshape(-1, 2), shape, scale=scale)
        expanded = cv2.bitwise_or(expanded, _polygon_mask(shape, expanded_points))

    if dilate_px > 0:
        kernel = cv2.getStructuringElement(
            cv2.MORPH_ELLIPSE,
            (dilate_px * 2 + 1, dilate_px * 2 + 1),
        )
        expanded = cv2.dilate(expanded, kernel, iterations=1)
    return expanded


def _build_tzone_roi(
    shape: Tuple[int, int],
    points: np.ndarray,
    forehead_mask: np.ndarray,
    skin_mask: np.ndarray,
    face_skin_mask: np.ndarray,
) -> tuple[np.ndarray, Dict[str, Any]]:
    h, w = shape
    forehead_mask = _as_binary_mask(forehead_mask, (h, w))
    skin_mask = _as_binary_mask(skin_mask, (h, w))
    face_skin_mask = _as_binary_mask(face_skin_mask, (h, w))
    face_oval = _face_oval_mask((h, w), points)
    face_clip_mask = face_oval if cv2.countNonZero(face_oval) > 0 else np.full((h, w), 255, dtype=np.uint8)

    nose_polygon = _nose_region_mask((h, w), points, skin_mask, apply_skin_mask=False)
    raw_tzone = cv2.bitwise_or(forehead_mask, nose_polygon)
    tzone_raw_pixels = int(cv2.countNonZero(raw_tzone))

    dilate_px = int(np.clip(round(min(h, w) * 0.008), 3, 7))
    expanded_tzone = _expand_mask_from_contour(
        raw_tzone,
        (h, w),
        scale=0.12,
        dilate_px=dilate_px,
    )
    expanded_tzone = cv2.bitwise_and(expanded_tzone, face_clip_mask)
    after_expand_pixels = int(cv2.countNonZero(expanded_tzone))

    preferred_skin_mask = face_skin_mask if cv2.countNonZero(face_skin_mask) > 0 else skin_mask
    tzone_after_skin = cv2.bitwise_and(expanded_tzone, preferred_skin_mask)
    after_skin_pixels = int(cv2.countNonZero(tzone_after_skin))

    if after_skin_pixels >= MIN_USABLE_TZONE_PIXELS:
        final_tzone = tzone_after_skin
        path = "primary_roi"
    else:
        final_tzone = expanded_tzone
        path = "tzone_landmark_fallback" if after_skin_pixels == 0 and tzone_raw_pixels > 100 else "tzone_face_fallback"

    if path == "tzone_face_fallback" and after_skin_pixels < 500:
        final_tzone = expanded_tzone
        path = "tzone_face_fallback_expanded"

    final_pixels = int(cv2.countNonZero(final_tzone))
    if final_pixels < 200 and cv2.countNonZero(expanded_tzone) > 0:
        boosted_tzone = expanded_tzone.copy()
        boost_kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
        for _ in range(3):
            if int(cv2.countNonZero(boosted_tzone)) >= 200:
                break
            boosted_tzone = cv2.dilate(boosted_tzone, boost_kernel, iterations=1)
            boosted_tzone = cv2.bitwise_and(boosted_tzone, face_clip_mask)
        final_tzone = boosted_tzone

    final_pixels = int(cv2.countNonZero(final_tzone))
    logger.info(
        "TZONE_ROI_BUILD raw=%d after_expand=%d after_skin=%d final=%d path=%s",
        tzone_raw_pixels,
        after_expand_pixels,
        after_skin_pixels,
        final_pixels,
        path,
    )
    return final_tzone, {
        "raw_pixels": tzone_raw_pixels,
        "after_expand_pixels": after_expand_pixels,
        "after_skin_pixels": after_skin_pixels,
        "final_pixels": final_pixels,
        "path": path,
    }


def _region_masks(shape: Tuple[int, int], skin_mask: np.ndarray, points: np.ndarray) -> Dict[str, np.ndarray]:
    h, w = shape
    skin_mask = _as_binary_mask(skin_mask, (h, w))
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
    face_oval = _face_oval_mask((h, w), points)
    face_clip_mask = face_oval if cv2.countNonZero(face_oval) > 0 else np.full((h, w), 255, dtype=np.uint8)
    dilate_px = int(np.clip(round(min(h, w) * 0.01), 3, 7))
    dilate_kernel = cv2.getStructuringElement(
        cv2.MORPH_ELLIPSE,
        (dilate_px * 2 + 1, dilate_px * 2 + 1),
    )

    left_cheek_ids = [33, 130, 205, 50, 234, 132, 172, 136, 98]
    right_cheek_ids = [263, 359, 425, 280, 454, 361, 397, 365, 327]

    left_raw = _polygon_mask((h, w), points[left_cheek_ids])
    right_raw = _polygon_mask((h, w), points[right_cheek_ids])

    left_expanded = cv2.dilate(
        _polygon_mask((h, w), _expanded_polygon_points(points[left_cheek_ids], (h, w))),
        dilate_kernel,
        iterations=1,
    )
    right_expanded = cv2.dilate(
        _polygon_mask((h, w), _expanded_polygon_points(points[right_cheek_ids], (h, w))),
        dilate_kernel,
        iterations=1,
    )

    left_expanded = cv2.bitwise_and(left_expanded, face_clip_mask)
    right_expanded = cv2.bitwise_and(right_expanded, face_clip_mask)

    union_raw = cv2.bitwise_or(left_raw, right_raw)
    union_after_expand = cv2.bitwise_or(left_expanded, right_expanded)
    union_after_expand_pixels = int(cv2.countNonZero(union_after_expand))

    left_after_skin = cv2.bitwise_and(left_expanded, skin_mask)
    right_after_skin = cv2.bitwise_and(right_expanded, skin_mask)
    union_after_skin = cv2.bitwise_or(left_after_skin, right_after_skin)

    after_skin_pixels = int(cv2.countNonZero(union_after_skin))
    left_after_skin_pixels = int(cv2.countNonZero(left_after_skin))
    right_after_skin_pixels = int(cv2.countNonZero(right_after_skin))

    # Asymmetric recovery: salvage a single good cheek when the other collapses.
    if left_after_skin_pixels >= 800 and right_after_skin_pixels < 200:
        mirror_kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))
        mirrored = cv2.flip(left_after_skin, 1)
        mirrored = cv2.dilate(mirrored, mirror_kernel, iterations=1)
        mirrored = cv2.bitwise_and(mirrored, right_expanded)
        right_after_skin = cv2.bitwise_or(right_after_skin, mirrored)
        union_after_skin = cv2.bitwise_or(left_after_skin, right_after_skin)
        after_skin_pixels = int(cv2.countNonZero(union_after_skin))
        logger.info("CHEEK_ROI_ASYM kept=left pixels=%d", left_after_skin_pixels)
    elif right_after_skin_pixels >= 800 and left_after_skin_pixels < 200:
        mirror_kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))
        mirrored = cv2.flip(right_after_skin, 1)
        mirrored = cv2.dilate(mirrored, mirror_kernel, iterations=1)
        mirrored = cv2.bitwise_and(mirrored, left_expanded)
        left_after_skin = cv2.bitwise_or(left_after_skin, mirrored)
        union_after_skin = cv2.bitwise_or(left_after_skin, right_after_skin)
        after_skin_pixels = int(cv2.countNonZero(union_after_skin))
        logger.info("CHEEK_ROI_ASYM kept=right pixels=%d", right_after_skin_pixels)

    # Lightweight skin-mask assist for under-segmented cheeks in otherwise large cheek unions.
    if after_skin_pixels < 1200 and union_after_expand_pixels >= 15000:
        face_bbox = cv2.bitwise_or(left_expanded, right_expanded)
        assist_skin = cv2.bitwise_and(skin_mask, face_bbox)
        assist_skin = cv2.morphologyEx(
            assist_skin,
            cv2.MORPH_CLOSE,
            cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3)),
            iterations=1,
        )
        left_assist = cv2.bitwise_and(left_expanded, assist_skin)
        right_assist = cv2.bitwise_and(right_expanded, assist_skin)
        assist_union = cv2.bitwise_or(left_assist, right_assist)
        assist_after_skin_pixels = int(cv2.countNonZero(assist_union))
        logger.info(
            "SKIN_MASK_ASSIST before=%d after=%d",
            after_skin_pixels,
            assist_after_skin_pixels,
        )
        if assist_after_skin_pixels > after_skin_pixels:
            left_after_skin = left_assist
            right_after_skin = right_assist
            union_after_skin = assist_union
            after_skin_pixels = assist_after_skin_pixels

    force_skin_intersect_for_scoring = False
    if after_skin_pixels < 2000 and union_after_expand_pixels >= 15000:
        extra_dilate_px = int(np.clip(dilate_px, 5, 7))
        extra_kernel = cv2.getStructuringElement(
            cv2.MORPH_ELLIPSE,
            (extra_dilate_px * 2 + 1, extra_dilate_px * 2 + 1),
        )
        left_expanded = cv2.dilate(left_expanded, extra_kernel, iterations=1)
        right_expanded = cv2.dilate(right_expanded, extra_kernel, iterations=1)
        left_expanded = cv2.bitwise_and(left_expanded, face_clip_mask)
        right_expanded = cv2.bitwise_and(right_expanded, face_clip_mask)
        left_after_skin = cv2.bitwise_and(left_expanded, skin_mask)
        right_after_skin = cv2.bitwise_and(right_expanded, skin_mask)
        expanded_union_after_skin = cv2.bitwise_or(left_after_skin, right_after_skin)
        expanded_after_skin_pixels = int(cv2.countNonZero(expanded_union_after_skin))
        logger.info(
            "CHEEK_ROI_EXPAND before_skin=%d after_skin=%d union_before_skin=%d",
            after_skin_pixels,
            expanded_after_skin_pixels,
            union_after_expand_pixels,
        )
        union_after_skin = expanded_union_after_skin
        after_skin_pixels = expanded_after_skin_pixels
        force_skin_intersect_for_scoring = True

    cheek_no_skin_fallback_used = False
    if after_skin_pixels < 500 and union_after_expand_pixels >= 15000:
        region["left_cheek"] = left_expanded
        region["right_cheek"] = right_expanded
        cheek_no_skin_fallback_used = True
        logger.info(
            "CHEEK_ROI_NO_SKIN_FALLBACK pixels=%d",
            int(cv2.countNonZero(cv2.bitwise_or(left_expanded, right_expanded))),
        )

    else:
        min_usable_cheek_pixels = (
            1200 if union_after_expand_pixels >= 15000 else MIN_USABLE_CHEEK_PIXELS
        )
        if after_skin_pixels >= min_usable_cheek_pixels or force_skin_intersect_for_scoring:
            region["left_cheek"] = left_after_skin
            region["right_cheek"] = right_after_skin
        else:
            region["left_cheek"] = left_expanded
            region["right_cheek"] = right_expanded

    final_union = cv2.bitwise_or(region["left_cheek"], region["right_cheek"])
    final_left_pixels = int(cv2.countNonZero(region["left_cheek"]))
    final_right_pixels = int(cv2.countNonZero(region["right_cheek"]))
    final_union_pixels = int(cv2.countNonZero(final_union))
    usable = final_union_pixels >= MIN_USABLE_CHEEK_PIXELS
    logger.info(
        "CHEEK_ROI_BUILD left=%d right=%d union=%d after_expand=%d after_skin=%d usable=%s",
        final_left_pixels,
        final_right_pixels,
        final_union_pixels,
        union_after_expand_pixels,
        after_skin_pixels,
        usable,
    )
    if cheek_no_skin_fallback_used:
        logger.info("CHEEK_ROI_BUILD path=cheek_expand_no_skin")

    for key in region.keys():
        if key == "forehead":
            region[key] = cv2.bitwise_and(region[key], skin_mask)
        else:
            region[key] = cv2.bitwise_and(region[key], face_clip_mask)
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

    print(
        f'[BACKEND POSE PROXY] pitch={pitch:.2f} yaw={yaw:.2f} eye_dist={eye_dist:.2f} face_height={face_height:.2f}',
        flush=True,
    )
    return pitch, yaw


def _landmark_bbox_mask(
    shape: Tuple[int, int],
    points: np.ndarray,
    *,
    pad_ratio: float = 0.12,
) -> np.ndarray:
    h, w = shape
    bbox_mask = np.zeros((h, w), dtype=np.uint8)
    if points.size == 0:
        return bbox_mask

    min_xy = np.floor(np.min(points, axis=0)).astype(np.int32)
    max_xy = np.ceil(np.max(points, axis=0)).astype(np.int32)
    bbox_w = max(1, int(max_xy[0] - min_xy[0]))
    bbox_h = max(1, int(max_xy[1] - min_xy[1]))
    pad_x = max(1, int(round(bbox_w * pad_ratio)))
    pad_y = max(1, int(round(bbox_h * pad_ratio)))
    x0 = max(0, int(min_xy[0] - pad_x))
    y0 = max(0, int(min_xy[1] - pad_y))
    x1 = min(w, int(max_xy[0] + pad_x))
    y1 = min(h, int(max_xy[1] + pad_y))
    if x1 <= x0 or y1 <= y0:
        return bbox_mask

    bbox_mask[y0:y1, x0:x1] = 255
    return bbox_mask


class _RequestRoiCache:
    """Request-scoped cache for expensive per-face ROI masks.

    This is intentionally kept local to a single analysis request so we do not
    persist computed masks across requests or stale scan results.
    """

    def __init__(self) -> None:
        self._face_skin_cache: Dict[tuple[object, ...], tuple[np.ndarray, np.ndarray]] = {}
        self._tzone_cache: Dict[tuple[object, ...], tuple[np.ndarray, Dict[str, Any]]] = {}

    def get_face_skin_mask(
        self,
        shape: Tuple[int, int],
        points: np.ndarray,
        skin_mask: np.ndarray,
    ) -> tuple[np.ndarray, np.ndarray]:
        key = (
            tuple(shape),
            id(points),
            id(skin_mask),
        )
        cached = self._face_skin_cache.get(key)
        if cached is not None:
            return cached

        result = _build_face_skin_mask(shape, points, skin_mask)
        self._face_skin_cache[key] = result
        return result

    def get_tzone_mask(
        self,
        shape: Tuple[int, int],
        points: np.ndarray,
        forehead_mask: np.ndarray,
        skin_mask: np.ndarray,
        face_skin_mask: np.ndarray,
    ) -> tuple[np.ndarray, Dict[str, Any]]:
        key = (
            tuple(shape),
            id(points),
            id(forehead_mask),
            id(skin_mask),
            id(face_skin_mask),
        )
        cached = self._tzone_cache.get(key)
        if cached is not None:
            return cached

        result = _build_tzone_roi(shape, points, forehead_mask, skin_mask, face_skin_mask)
        self._tzone_cache[key] = result
        return result


def _build_face_skin_mask(
    shape: Tuple[int, int],
    points: np.ndarray,
    skin_mask: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
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
    face_skin_mask = cv2.bitwise_and(
        face_skin_candidate,
        _as_binary_mask(skin_mask, (h, w)),
    )
    return geom_mask, face_skin_mask


def _build_pore_roi_masks(
    shape: Tuple[int, int],
    points: np.ndarray,
    face_skin_mask: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    h, w = shape
    geom_mask = _face_oval_mask((h, w), points)
    if cv2.countNonZero(geom_mask) <= 0:
        empty = np.zeros((h, w), dtype=np.uint8)
        return empty, empty
    pore_roi_mask = _as_binary_mask(face_skin_mask, (h, w))

    # Restrict the pore mask to the true T-zone: nose bridge + immediate inner
    # cheeks/paranasal zone. This avoids ingesting the forehead, outer cheeks,
    # and jawline, which would otherwise inflate the ROI to near whole-face
    # dimensions and trip the pore gate unnecessarily.
    tzone_ids = [1, 33, 133, 263, 362, 61, 291, 234, 454, 152, 296, 300]
    valid_tzone_ids = [idx for idx in tzone_ids if 0 <= idx < points.shape[0]]
    if len(valid_tzone_ids) < 5:
        return geom_mask, np.zeros((h, w), dtype=np.uint8)
    center = np.mean(points[valid_tzone_ids], axis=0).astype(np.float32)
    cx = int(np.clip(round(float(center[0])), 0, w - 1))
    cy = int(np.clip(round(float(center[1])), 0, h - 1))
    # Keep pore measurement tightly centered on the nose/inner-cheek area.
    band_w = int(np.clip(min(w * 0.18, 120.0), 80.0, 120.0))
    band_h = int(np.clip(min(h * 0.22, 100.0), 70.0, 100.0))
    x0 = max(0, cx - band_w // 2)
    x1 = min(w, cx + band_w // 2)
    y0 = max(0, cy - band_h // 2)
    y1 = min(h, cy + band_h // 2)
    tzone_window = np.zeros((h, w), dtype=np.uint8)
    tzone_window[y0:y1, x0:x1] = 255
    pore_roi_mask = cv2.bitwise_and(pore_roi_mask, tzone_window)

    return geom_mask, pore_roi_mask


def _build_chin_pore_mask(
    shape: Tuple[int, int],
    points: np.ndarray,
    face_skin_mask: np.ndarray,
) -> np.ndarray:
    h, w = shape
    chin_ids = [
        61, 58, 172, 136, 150, 149, 176, 148, 152, 377, 400, 378,
        379, 365, 397, 288, 361, 291, 375, 321, 314, 17, 84, 181, 91, 146,
    ]
    valid_ids = [idx for idx in chin_ids if 0 <= idx < points.shape[0]]
    if len(valid_ids) < 5:
        return np.zeros((h, w), dtype=np.uint8)

    chin_mask = _polygon_mask((h, w), points[valid_ids])
    mouth_ids = [61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 308]
    valid_mouth_ids = [idx for idx in mouth_ids if 0 <= idx < points.shape[0]]
    if len(valid_mouth_ids) >= 3:
        mouth_mask = _polygon_mask((h, w), points[valid_mouth_ids])
        chin_mask = cv2.bitwise_and(chin_mask, cv2.bitwise_not(mouth_mask))

    chin_mask = cv2.bitwise_and(chin_mask, _as_binary_mask(face_skin_mask, (h, w)))
    if cv2.countNonZero(chin_mask) <= 0:
        return np.zeros((h, w), dtype=np.uint8)
    return chin_mask


def _extract_native_resolution_pore_roi(
    face_bgr: np.ndarray,
    points: np.ndarray,
    face_skin_mask: np.ndarray,
) -> tuple[np.ndarray | None, np.ndarray | None, int]:
    geom_mask, skin_locked_mask = _build_pore_roi_masks(
        face_bgr.shape[:2], points, face_skin_mask
    )
    if int(cv2.countNonZero(skin_locked_mask)) <= 0:
        return None, None, 0

    h, w = face_bgr.shape[:2]
    pore_ids = [1, 33, 133, 263, 362, 61, 291, 234, 454, 152, 296, 300]
    valid_ids = [idx for idx in pore_ids if 0 <= idx < points.shape[0]]
    if len(valid_ids) >= 5:
        pore_points = points[valid_ids].astype(np.float32)
        center = np.mean(pore_points, axis=0).astype(np.float32)
        cx = int(np.clip(round(float(center[0])), 0, w - 1))
        cy = int(np.clip(round(float(center[1])), 0, h - 1))
        box_w = int(np.clip(min(w * 0.18, 120.0), 80.0, 120.0))
        box_h = int(np.clip(min(h * 0.22, 100.0), 70.0, 100.0))
        x0 = max(0, cx - box_w // 2)
        x1 = min(w, cx + box_w // 2)
        y0 = max(0, cy - box_h // 2)
        y1 = min(h, cy + box_h // 2)
        if x1 > x0 and y1 > y0:
            tzone_mask = np.zeros((h, w), dtype=np.uint8)
            tzone_mask[y0:y1, x0:x1] = 255
            skin_locked_mask = cv2.bitwise_and(skin_locked_mask, tzone_mask)

    mask_pixels = int(cv2.countNonZero(skin_locked_mask))
    if mask_pixels <= 0:
        return None, None, 0

    # Final explicit cap: nose/inner-cheek pores should remain in a compact
    # T-zone window, not a whole-face mask.
    if mask_pixels > 25000:
        ys, xs = np.where(skin_locked_mask > 0)
        if xs.size > 0 and ys.size > 0:
            cx = int(np.mean(xs))
            cy = int(np.mean(ys))
            box_w = int(np.clip(min(w * 0.14, 100.0), 60.0, 100.0))
            box_h = int(np.clip(min(h * 0.18, 90.0), 50.0, 90.0))
            x0 = max(0, cx - box_w // 2)
            x1 = min(w, cx + box_w // 2)
            y0 = max(0, cy - box_h // 2)
            y1 = min(h, cy + box_h // 2)
            tight_mask = np.zeros((h, w), dtype=np.uint8)
            tight_mask[y0:y1, x0:x1] = 255
            skin_locked_mask = cv2.bitwise_and(skin_locked_mask, tight_mask)
            mask_pixels = int(cv2.countNonZero(skin_locked_mask))
            if mask_pixels <= 0:
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
    mask_crop = np.where(skin_locked_mask[y0:y1, x0:x1] > 0, 255, 0).astype(np.uint8)

    # Frequency analysis must run on native-resolution pixels: upsampling this
    # small crop to a fixed canvas (as a prior version did) destroys the
    # pore-scale detail the DoG filter is meant to measure, and made the pixel
    # count below meaningless as a real-detail gate.
    return l_crop, mask_crop, int(cv2.countNonZero(mask_crop))


def _extract_native_resolution_chin_pore_roi(
    face_bgr: np.ndarray,
    points: np.ndarray,
    face_skin_mask: np.ndarray,
) -> tuple[np.ndarray | None, np.ndarray | None, int]:
    chin_mask = _build_chin_pore_mask(face_bgr.shape[:2], points, face_skin_mask)
    if cv2.countNonZero(chin_mask) <= 0:
        return None, None, 0

    ys, xs = np.where(chin_mask > 0)
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
    mask_crop = np.where(chin_mask[y0:y1, x0:x1] > 0, 255, 0).astype(np.uint8)
    return l_crop, mask_crop, int(cv2.countNonZero(mask_crop))


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


# under_eye_dark_circle_density dead-zone: raw darkness_delta (mean cheek
# L minus mean under-eye L, in OpenCV's 0-255 LAB units) below this is
# treated as normal anatomical eye-socket shadow, not a dark circle, and
# scores 0. This is a first-pass estimate reasoned from the shape of the
# problem (a flat multiplier with no dead-zone means ANY shadow starts
# accumulating score immediately), not derived from real paired-scan data
# yet. Revisit once real photos with known, human-rated dark-circle
# severity are available to calibrate against.
UNDER_EYE_DARK_CIRCLE_DEAD_ZONE_L_UNITS = 8.0

# Score multiplier applied to the dead-zone-adjusted delta. Provisional,
# same caveat as the dead zone above. NOTE this was re-derived DOWN from
# the pre-dead-zone value of 2.0, not up: investigation showed 8 of 11
# real test photos already saturated to a 100.0 score under the old
# formula (multiplier=2.0, no dead zone), meaning raw deltas of >=50
# L-units are common from anatomical shadow and lighting/angle alone, not
# genuine pigment. An 8-unit dead zone barely dents deltas that large, so
# widening the multiplier (the naive "compensate for the dead zone"
# move) would have made the saturation worse, not better. 1.2 is chosen
# so a photo needs a clearly larger post-dead-zone delta before reaching
# the 40-80 "visible" range, rather than nearly every casual selfie
# maxing out at 100.
UNDER_EYE_DARK_CIRCLE_SCORE_MULTIPLIER = 1.2

# PROVISIONAL pigment-load calibration (second pass).
#
# The previous constants (dead_zone=12.0, center=35.0, slope=10.0) were tuned
# against a pigment_signal that carried two pigment-independent pedestals:
#   1. l_contrast, measured at 1.01x discrimination between a visually clear
#      face and a visibly pigmented one (56.27 vs 57.09) while supplying 54%
#      of a clear face's total raw signal.
#   2. chroma deviation measured from fixed grey (128,128), which scores
#      ordinary skin-tone warmth as pigmentation - a clear face's cheek mean
#      alone sat 13.33 units from grey before any unevenness was measured.
# Together they put a hard ~12.7 floor under the scale, so genuinely clear
# skin could not score low.
#
# Re-derived against a 17-photo set (20-portrait diverse batch plus the two
# named evidence photos) on the rebaselined self-mean signal, whose observed
# range is 0.05-36.76 with p10 5.80 / p90 15.61. Still provisional: it has not
# been validated against same-person paired captures, and the batch remains
# small and fixed. Revisit once real CALIBRATION_LOG data accumulates.
PIGMENT_LOAD_DEAD_ZONE_SIGNAL = 4.0
PIGMENT_LOAD_SCORE_CENTER = 13.5
PIGMENT_LOAD_SCORE_SLOPE = 3.6

# PROVISIONAL. Set to 0.0 because measured l_contrast discrimination between
# clear and pigmented cheeks was 1.01x - it tracks anatomical shading, not
# pigment. Kept as a named weight (not deleted) so the term can be restored if
# a future ROI makes it genuinely informative.
PIGMENT_LOAD_L_CONTRAST_WEIGHT = 0.0

# PROVISIONAL localized-redness calibration. First scans use each photo's own
# least-red cheek band (p10) as the reference for its p95 hot-spot signal,
# eliminating the fixed-neutral a*=128 pedestal. Across the real reference
# set, max per-cheek p95-p10 was 9.55 (clear), 10.61 (nikki2), 11.76
# (nikki3), and 19.19 (severe st1). A 9.0-unit dead zone and 8.34 multiplier
# map those to approximately 4.6, 13.5, 23.0, and 85.0. Revisit when a larger
# set of human-rated redness references is available.
LOCALIZED_REDNESS_SELF_BASELINE_PERCENTILE = 10.0
LOCALIZED_REDNESS_DEAD_ZONE_A_UNITS = 9.0
LOCALIZED_REDNESS_SCORE_MULTIPLIER = 8.34

# PROVISIONAL follow-up calibration. Return visits compare cheek p95 to the
# prior scan's cheek p95, never p95 to mean. The adjustment is anchored to the
# prior canonical score so an unchanged follow-up preserves absolute severity.
LOCALIZED_REDNESS_FOLLOWUP_DEAD_ZONE_A_UNITS = 1.0
LOCALIZED_REDNESS_FOLLOWUP_MULTIPLIER = 2.55


# ─────────────────────────────────────────────────────────────────────────
# Pure scoring-formula extractions
#
# These take plain scalar inputs (already-reduced pixel statistics) rather
# than image arrays, so they're unit-testable in isolation without the
# ROI/landmark pipeline. Behavior-preserving extractions of math that used
# to be inlined at each call site — see test_scoring_formulas.py.
# ─────────────────────────────────────────────────────────────────────────


def compute_localized_redness_and_rosacea(
    p95_a,
    baseline_a_ref,
    diffuse_density,
    *,
    dead_zone=LOCALIZED_REDNESS_DEAD_ZONE_A_UNITS,
    multiplier=LOCALIZED_REDNESS_SCORE_MULTIPLIER,
    baseline_score=0.0,
):
    """Pure extraction of the localized_redness / rosacea_severity formula
    from _compute_zone_based_metrics. Inputs are already-reduced cheek-ROI
    statistics (95th-percentile LAB 'a' channel, personal baseline 'a'
    reference, and diffuse-flushing pixel density), not image arrays.
    Returns a dict: localized_redness, diffuse_flushing_erythema,
    rosacea_before, rosacea_severity, rosacea_reason.
    """
    delta = float(p95_a) - float(baseline_a_ref)
    if baseline_score > 0.0:
        signed_effective_delta = math.copysign(
            max(0.0, abs(delta) - dead_zone),
            delta,
        )
        localized_redness = float(
            np.clip(baseline_score + (signed_effective_delta * multiplier), 0.0, 100.0)
        )
    else:
        effective_delta = max(0.0, delta - dead_zone)
        localized_redness = float(np.clip(effective_delta * multiplier, 0.0, 100.0))
    diffuse_flushing_erythema = float(
        np.clip((0.70 * diffuse_density) + (0.30 * localized_redness), 0.0, 100.0)
    )
    rosacea_before = float(
        np.clip((0.65 * diffuse_flushing_erythema) + (0.35 * localized_redness), 0.0, 100.0)
    )
    rosacea_severity = rosacea_before
    rosacea_reason = "unchanged"
    rosacea_cap = max(
        localized_redness + 20.0, localized_redness * 2.5, diffuse_density * 0.45
    )
    if localized_redness <= 25.0 and rosacea_before > rosacea_cap:
        rosacea_severity = float(np.clip(rosacea_cap, 0.0, 100.0))
        rosacea_reason = "cap_low_redness_divergence"
    return {
        "localized_redness": localized_redness,
        "diffuse_flushing_erythema": diffuse_flushing_erythema,
        "rosacea_before": rosacea_before,
        "rosacea_severity": rosacea_severity,
        "rosacea_reason": rosacea_reason,
    }


def compute_pigment_load(
    pigment_signal,
    dead_zone=PIGMENT_LOAD_DEAD_ZONE_SIGNAL,
    center=PIGMENT_LOAD_SCORE_CENTER,
    slope=PIGMENT_LOAD_SCORE_SLOPE,
):
    """Pure extraction of the pigment_load dead-zone/sigmoid formula from
    _compute_zone_based_metrics. [pigment_signal] is the already-combined
    chroma-deviation + L-contrast statistic, not an image array.
    """
    effective_signal = max(0.0, pigment_signal - dead_zone)
    pigment = 100.0 / (
        1.0 + math.exp(-(effective_signal - (center - dead_zone)) / slope)
    )
    return float(np.clip(pigment, 0.0, 100.0))


def compute_under_eye_dark_circle_density(
    darkness_delta,
    dead_zone=UNDER_EYE_DARK_CIRCLE_DEAD_ZONE_L_UNITS,
    multiplier=UNDER_EYE_DARK_CIRCLE_SCORE_MULTIPLIER,
):
    """Pure extraction of the under_eye_dark_circle_density dead-zone
    formula from _compute_zone_based_metrics. [darkness_delta] is the
    already-computed cheek-minus-under-eye mean L-channel delta (clamped
    to >= 0), not an image array.
    """
    effective_delta = max(0.0, darkness_delta - dead_zone)
    return float(np.clip(effective_delta * multiplier, 0.0, 100.0))


def _is_missing_metric_value(value: float | None) -> bool:
    """True only when a metric value represents "never measured" -- absent,
    NaN, or infinite. A finite value of exactly 0.0 (or a negative raw
    value that clips to 0.0) is a genuine reading -- "no visible redness",
    "no detected breakouts" -- and must be emitted, not treated as missing.
    Only a producer that truly could not measure (ROI too small, an
    exception during extraction) should ever route a metric here; those
    paths must represent that with None, never with a fabricated 0.0.
    """
    return value is None or not math.isfinite(value)


def is_redness_unset(current_value):
    """True when localized_redness is missing/invalid/non-positive and is
    therefore eligible for the mean-based cheek-ROI fallback in
    _compute_canonical_patch_metrics to fill in. This is the exact guard
    that was broken before: a valid canonical value must make this False,
    so the fallback block (gated on this being True) never overwrites it.
    """
    return (
        current_value is None
        or not math.isfinite(current_value)
        or current_value <= 0.0
    )


CHEEK_SIDE_CONVENTION = "subject_anatomical"


def _subject_anatomical_cheek_side(internal_side: str) -> str:
    if internal_side == "left":
        return "right"
    if internal_side == "right":
        return "left"
    return internal_side


def _compute_zone_based_metrics(
    face_bgr: np.ndarray,
    skin_mask: np.ndarray,
    regions: Dict[str, np.ndarray],
    points: np.ndarray,
    *,
    baseline_matrix: Dict[str, Any] | None = None,
    roi_cache: _RequestRoiCache | None = None,
    redness_diagnostics: Dict[str, Any] | None = None,
) -> Dict[str, Any]:
    # PRODUCER AUDIT (see CANONICAL_METRIC_ORDER registry below): this helper
    # returns only the three zone metrics consumed by analyze_skin_patch.
    # [redness_diagnostics], when given, is filled with read-only logging of
    # which localized_redness branch ran and the exact cheek pixels it used;
    # nothing in it feeds back into any score.
    h, w = face_bgr.shape[:2]
    if h == 0 or w == 0:
        return {
            "rosacea_severity": 0.0,
            "under_eye_texture_density": 0.0,
            "under_eye_dark_circle_density": 0.0,
        }

    lab = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2LAB)
    gray = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2GRAY)
    lap_abs = np.abs(cv2.Laplacian(gray, cv2.CV_32F, ksize=3))

    skin_mask = _as_binary_mask(skin_mask, (h, w))
    # U-zone: cheeks for redness / diffuse flushing / rosacea indicators.
    left_cheek = regions.get("left_cheek", np.zeros((h, w), dtype=np.uint8))
    right_cheek = regions.get("right_cheek", np.zeros((h, w), dtype=np.uint8))
    u_zone = cv2.bitwise_and(cv2.bitwise_or(left_cheek, right_cheek), skin_mask)
    u_zone_pixels = u_zone > 0
    if redness_diagnostics is not None:
        redness_diagnostics["u_zone_pixels"] = int(np.count_nonzero(u_zone_pixels))

    a_blur = cv2.GaussianBlur(lab[:, :, 1].astype(np.float32), (0, 0), sigmaX=2.0)
    if np.any(u_zone_pixels):
        median_a = float(np.percentile(a_blur[u_zone_pixels], 50))
        p95_a = float(np.percentile(a_blur[u_zone_pixels], 95))
    else:
        median_a = 128.0
        p95_a = 128.0
    if redness_diagnostics is not None and np.any(u_zone_pixels):
        redness_diagnostics["u_zone_p95_a_after_wb"] = p95_a

    diffuse_threshold = max(138.0, median_a + 5.0)
    diffuse_mask = np.logical_and(u_zone_pixels, a_blur >= diffuse_threshold)
    diffuse_density = float(
        np.clip(
            (np.count_nonzero(diffuse_mask) / max(np.count_nonzero(u_zone_pixels), 1))
            * 100.0,
            0.0,
            100.0,
        )
    )
    side_spreads: list[float] = []
    side_names: list[str] = []
    side_masks: list[np.ndarray] = []
    side_p95s: list[float] = []
    for side_name, cheek_mask in (("left", left_cheek), ("right", right_cheek)):
        side_pixels = cv2.bitwise_and(cheek_mask, skin_mask) > 0
        if not np.any(side_pixels):
            continue
        side_values = a_blur[side_pixels]
        side_p95 = float(np.percentile(side_values, 95))
        side_spreads.append(
            side_p95
            - float(
                np.percentile(
                    side_values,
                    LOCALIZED_REDNESS_SELF_BASELINE_PERCENTILE,
                )
            )
        )
        side_names.append(_subject_anatomical_cheek_side(side_name))
        side_masks.append(side_pixels)
        side_p95s.append(side_p95)
    if redness_diagnostics is not None:
        redness_diagnostics["both_cheeks_in_dead_zone"] = (
            len(side_spreads) == 2
            and all(
                spread <= LOCALIZED_REDNESS_DEAD_ZONE_A_UNITS
                for spread in side_spreads
            )
        )
    personal_lab_baseline = _coalesce_personal_lab_baseline(baseline_matrix or {})
    baseline_a_p95 = safe_float(personal_lab_baseline.get("a_p95"))
    if baseline_a_p95 is not None:
        baseline_score = safe_float((baseline_matrix or {}).get("localized_redness")) or 0.0
        _redness_result = compute_localized_redness_and_rosacea(
            p95_a,
            baseline_a_p95,
            diffuse_density,
            dead_zone=LOCALIZED_REDNESS_FOLLOWUP_DEAD_ZONE_A_UNITS,
            multiplier=LOCALIZED_REDNESS_FOLLOWUP_MULTIPLIER,
            baseline_score=baseline_score,
        )
        redness_signal = p95_a - baseline_a_p95
        redness_reference_source = "personal_p95"
        if redness_diagnostics is not None:
            redness_diagnostics.update(
                branch="baseline_p95_anchor",
                cheek_side="both",
                mask=u_zone_pixels,
                p95_a_after_wb=p95_a,
                baseline_p95_a=baseline_a_p95,
            )
    else:
        redness_signal = max(side_spreads, default=0.0)
        if redness_diagnostics is not None:
            redness_diagnostics["branch"] = "within_cheek_spread"
            redness_diagnostics["baseline_p95_a"] = None
            if side_spreads:
                # max() keeps the first maximum, so ties resolve to the same
                # cheek (left before right) the formula's value came from.
                winner = side_spreads.index(redness_signal)
                redness_diagnostics.update(
                    cheek_side=side_names[winner],
                    mask=side_masks[winner],
                    p95_a_after_wb=side_p95s[winner],
                )
        _redness_result = compute_localized_redness_and_rosacea(
            redness_signal,
            0.0,
            diffuse_density,
        )
        redness_reference_source = "self_cheek_p10"
    if redness_diagnostics is not None:
        diag_mask = redness_diagnostics.get("mask")
        diag_pixels = int(np.count_nonzero(diag_mask)) if diag_mask is not None else 0
        redness_diagnostics["cheek_roi_pixels"] = diag_pixels
        if diag_pixels > 0:
            redness_diagnostics["p10_a_after_wb"] = float(
                np.percentile(
                    a_blur[diag_mask],
                    LOCALIZED_REDNESS_SELF_BASELINE_PERCENTILE,
                )
            )
            redness_diagnostics["mean_a_after_wb"] = float(
                np.mean(lab[:, :, 1].astype(np.float32)[diag_mask])
            )
            redness_diagnostics["mean_b_after_wb"] = float(
                np.mean(lab[:, :, 2].astype(np.float32)[diag_mask])
            )
    localized_redness = _redness_result["localized_redness"]
    diffuse_flushing_erythema = _redness_result["diffuse_flushing_erythema"]
    rosacea_before = _redness_result["rosacea_before"]
    rosacea_severity = _redness_result["rosacea_severity"]
    rosacea_reason = _redness_result["rosacea_reason"]
    logger.info(
        "ROSACEA_CALIB signal=%.2f reference=%s redness=%.1f rosacea_before=%.1f rosacea_after=%.1f reason=%s",
        redness_signal,
        redness_reference_source,
        localized_redness,
        rosacea_before,
        rosacea_severity,
        rosacea_reason,
    )

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
        # FIRST-PASS FIX, NOT A FINISHED SCALE: the dead zone + multiplier
        # below are reasoned starting points (see the constants' comments
        # above _compute_zone_based_metrics), not a clinically-validated
        # mapping from L-channel delta to dark-circle severity. Revisit
        # both once real paired scans with known visible severity exist —
        # use the UNDER_EYE_DARK_CIRCLE log line below to gather that data
        # instead of re-deriving the formula from scratch.
        effective_delta = max(
            0.0, darkness_delta - UNDER_EYE_DARK_CIRCLE_DEAD_ZONE_L_UNITS
        )
        under_eye_dark_circle_density = compute_under_eye_dark_circle_density(darkness_delta)
        logger.info(
            "UNDER_EYE_DARK_CIRCLE raw_delta=%.2f dead_zone=%.1f effective_delta=%.2f score=%.1f",
            darkness_delta,
            UNDER_EYE_DARK_CIRCLE_DEAD_ZONE_L_UNITS,
            effective_delta,
            under_eye_dark_circle_density,
        )
    else:
        under_eye_texture_density = 0.0
        under_eye_dark_circle_density = 0.0

    return {
        "localized_redness": round(localized_redness, 1),
        "rosacea_severity": round(rosacea_severity, 1),
        "under_eye_texture_density": round(under_eye_texture_density, 1),
        "under_eye_dark_circle_density": round(under_eye_dark_circle_density, 1),
    }


def _compute_additional_opencv_metrics(
    face_bgr: np.ndarray,
    skin_mask: np.ndarray,
    regions: Dict[str, np.ndarray],
    points: np.ndarray,
    *,
    roi_cache: _RequestRoiCache | None = None,
    mask_diagnostics: Dict[str, Any] | None = None,
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

    skin_mask = _as_binary_mask(skin_mask, (h, w))
    if roi_cache is not None:
        _, face_skin_mask = roi_cache.get_face_skin_mask((h, w), points, skin_mask)
    else:
        _, face_skin_mask = _build_face_skin_mask((h, w), points, skin_mask)
    if cv2.countNonZero(face_skin_mask) <= 0:
        return {
            "sebum_excess_oil_gloss": None,
            "diffuse_flushing_erythema": None,
            "skin_tone_radiance_evenness": None,
        }
    forehead = _as_binary_mask(regions.get("forehead", np.zeros((h, w), dtype=np.uint8)), (h, w))
    if roi_cache is not None:
        t_zone, _ = roi_cache.get_tzone_mask((h, w), points, forehead, skin_mask, face_skin_mask)
    else:
        t_zone, _ = _build_tzone_roi((h, w), points, forehead, skin_mask, face_skin_mask)
    nose = _nose_region_mask((h, w), points, skin_mask)
    if cv2.countNonZero(t_zone) == 0:
        t_zone = face_skin_mask

    t_zone_pixels = val[t_zone > 0]
    v_threshold = 220.0
    if t_zone_pixels.size > 0:
        v_threshold = max(220.0, float(np.percentile(t_zone_pixels, 95)))
    specular_mask = np.logical_and.reduce([t_zone > 0, val >= v_threshold, sat <= 70]).astype(np.uint8) * 255
    small_kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    specular_mask = cv2.morphologyEx(specular_mask, cv2.MORPH_OPEN, small_kernel)
    specular_mask = cv2.morphologyEx(specular_mask, cv2.MORPH_CLOSE, small_kernel)
    sebum_gloss_pct = (float(cv2.countNonZero(specular_mask)) / max(float(cv2.countNonZero(t_zone)), 1.0)) * 100.0

    left_cheek = regions.get("left_cheek", np.zeros((h, w), dtype=np.uint8))
    right_cheek = regions.get("right_cheek", np.zeros((h, w), dtype=np.uint8))
    flush_roi = cv2.bitwise_or(cv2.bitwise_or(left_cheek, right_cheek), nose)
    flush_roi = cv2.bitwise_and(flush_roi, face_skin_mask)
    flush_area = max(int(cv2.countNonZero(flush_roi)), 1)
    if mask_diagnostics is not None:
        mask_diagnostics["diffuse_flushing_erythema_mask_kind"] = "u_zone_nose_face_skin"
        mask_diagnostics["diffuse_flushing_erythema_mask_pixels"] = int(
            cv2.countNonZero(flush_roi)
        )
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
        if int(stats[label_id, cv2.CC_STAT_AREA]) >= min_component_area:
            diffuse_mask[labels == label_id] = 255
    diffuse_density = (float(cv2.countNonZero(diffuse_mask)) / max(float(flush_area), 1.0)) * 100.0
    diffuse_pixels = a_blur[diffuse_mask > 0]
    if diffuse_pixels.size > 0:
        normalized_excess = np.clip((diffuse_pixels - red_threshold) / max(170.0 - red_threshold, 1.0), 0.0, 1.0)
        diffuse_intensity = float(np.mean(normalized_excess) * 100.0)
    else:
        diffuse_intensity = 0.0
    diffuse_flushing_score = (0.65 * diffuse_density) + (0.35 * diffuse_intensity)

    healthy_skin = skin_mask > 0
    red_lesion_like = np.logical_and.reduce([healthy_skin, np.logical_or(hue <= 12, hue >= 170), sat >= 90, val >= 60])
    lap_abs = np.abs(cv2.Laplacian(gray, cv2.CV_32F, ksize=3))
    healthy_lap = lap_abs[healthy_skin]
    texture_threshold = float(np.percentile(healthy_lap, 90)) if healthy_lap.size > 0 else 9999.0
    high_texture = np.logical_and(healthy_skin, lap_abs >= texture_threshold)
    refined_healthy = np.logical_and(healthy_skin, ~red_lesion_like)
    refined_healthy = np.logical_and(refined_healthy, ~high_texture)
    refined_healthy = np.logical_and(refined_healthy, ~(specular_mask > 0))
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
    *,
    roi_cache: _RequestRoiCache | None = None,
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
        # 75th (was 82nd): the glabella ROI is small, and genuinely real
        # "11 lines" are frequently only 1-2px wide -- an 82nd-percentile cut
        # left the opening step below almost nothing to preserve on a
        # meaningful share of real photos, zeroing the metric outright
        # rather than just scoring it low. See GLABELLAR_ZERO_OUT_FIX below.
        threshold = float(np.percentile(response_values, 75)) if response_values.size > 0 else 9999.0
        wrinkle_binary = np.logical_and(glabella_mask > 0, vertical_response >= threshold).astype(np.uint8) * 255
        # GLABELLAR_ZERO_OUT_FIX: (3,5) required a blob ~3px wide to survive
        # this opening at all, which erased thin-but-real furrow responses
        # entirely (not just down-scored them) on ~26-32% of real photos.
        # (2,4) still removes true single-pixel noise specks while letting a
        # genuinely thin vertical furrow survive.
        wrinkle_binary = cv2.morphologyEx(
            wrinkle_binary,
            cv2.MORPH_OPEN,
            cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2, 4)),
        )

        contours, _ = cv2.findContours(wrinkle_binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        widths: list[float] = []
        intensities: list[float] = []
        # 5 (was a floor of 8): 8px was almost always the binding constraint
        # on this small ROI (glabella_area * 0.0012 rarely exceeds it),
        # pruning legitimate small-but-real components more aggressively
        # than this metric's own small scale warrants.
        min_component_area = max(5, int(glabella_area * 0.0012))
        for contour in contours:
            area = float(cv2.contourArea(contour))
            if area < min_component_area:
                continue
            x, y, bw, bh = cv2.boundingRect(contour)
            # GLABELLAR_WIDTH_QUANTIZATION_FIX: cv2.boundingRect returns
            # integer pixel width, so on this small crop avg_width could
            # only ever land on a handful of achievable values (each unit of
            # bw swings width_norm by ~8.3 points). minAreaRect fits a
            # rotated rectangle to the contour's convex hull, which yields a
            # continuous, sub-pixel-precision size even for an
            # axis-aligned blob -- the narrower of its two dimensions is the
            # furrow's width (the longer dimension is its length along the
            # line), giving smooth rather than stair-stepped output.
            (_, _), (rect_w, rect_h), _ = cv2.minAreaRect(contour)
            widths.append(float(min(rect_w, rect_h)))
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
    pore_area = int(cv2.countNonZero(pore_roi))
    pore_contraction_index: float | None
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
        pore_contraction_index = None

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

    result = {
        "glabellar_wrinkle_depth": round(float(np.clip(glabellar_wrinkle_depth, 0.0, 100.0)), 1),
        "structural_firmness_elasticity": round(float(np.clip(structural_firmness, 0.0, 100.0)), 1),
    }
    if pore_contraction_index is not None:
        result["pore_contraction_index"] = round(
            float(np.clip(pore_contraction_index, 0.0, 100.0)), 1
        )
    return result


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
    baseline_matrix: Dict[str, Any] | None = None,
    roi_cache: _RequestRoiCache | None = None,
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
    personal_lab_baseline = _resolve_personal_lab_ctx(baseline_matrix)

    if h == 0 or w == 0:
        return matrix, confidence, raw_components

    skin_mask = _as_binary_mask(skin_mask, (h, w))
    lab = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2LAB)
    gray = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2GRAY)

    glabella = _glabella_region_mask((h, w), points, skin_mask)
    if roi_cache is not None:
        _, full_face_skin_mask = roi_cache.get_face_skin_mask((h, w), points, skin_mask)
    else:
        _, full_face_skin_mask = _build_face_skin_mask((h, w), points, skin_mask)
    full_face_skin_mask = _as_binary_mask(full_face_skin_mask, (h, w))
    full_face_pixels = int(cv2.countNonZero(full_face_skin_mask))
    skin_mask_pixels = int(cv2.countNonZero(skin_mask))
    skin_mask_failed = skin_mask_pixels <= 0
    raw_components["full_face_skin_pixels"] = float(full_face_pixels)
    raw_components["skin_mask_pixels"] = float(skin_mask_pixels)

    left_cheek = _as_binary_mask(regions.get("left_cheek", np.zeros((h, w), dtype=np.uint8)), (h, w))
    right_cheek = _as_binary_mask(regions.get("right_cheek", np.zeros((h, w), dtype=np.uint8)), (h, w))
    primary_cheek_mask = cv2.bitwise_or(left_cheek, right_cheek)

    forehead = _as_binary_mask(regions.get("forehead", np.zeros((h, w), dtype=np.uint8)), (h, w))
    forehead_skin_mask = cv2.bitwise_and(forehead, full_face_skin_mask)
    nose_polygon = _nose_region_mask((h, w), points, skin_mask, apply_skin_mask=False)
    primary_t_zone_polygon = cv2.bitwise_or(forehead, nose_polygon)
    primary_t_zone_mask_before_fix = cv2.bitwise_and(primary_t_zone_polygon, skin_mask)
    if roi_cache is not None:
        primary_t_zone_mask, tzone_meta = roi_cache.get_tzone_mask(
            (h, w),
            points,
            forehead,
            skin_mask,
            full_face_skin_mask,
        )
    else:
        primary_t_zone_mask, tzone_meta = _build_tzone_roi(
            (h, w),
            points,
            forehead,
            skin_mask,
            full_face_skin_mask,
        )
    primary_cheek_pixels = int(cv2.countNonZero(primary_cheek_mask))
    primary_cheek_skin_pixels = int(cv2.countNonZero(cv2.bitwise_and(primary_cheek_mask, skin_mask)))
    cheek_expand_no_skin_used = (
        primary_cheek_skin_pixels < 500 and primary_cheek_pixels >= 15000
    )
    if cheek_expand_no_skin_used:
        logger.info("CHEEK_ROI_NO_SKIN_FALLBACK pixels=%d", primary_cheek_pixels)
    primary_t_zone_pixels_before_fix = int(cv2.countNonZero(primary_t_zone_mask_before_fix))
    primary_t_zone_pixels = int(tzone_meta["final_pixels"])

    logger.info(
        "[TZoneFix] before_fix tzone_raw=%d skin_intersect=%d",
        int(cv2.countNonZero(primary_t_zone_polygon)),
        primary_t_zone_pixels_before_fix,
    )
    logger.info(
        "[TZoneFix] after_fix tzone_raw=%d skin_intersect=%d",
        int(cv2.countNonZero(primary_t_zone_polygon)),
        primary_t_zone_pixels,
    )

    tzone_path = str(tzone_meta.get("path", "tzone_face_fallback"))
    tzone_primary_used = tzone_path == "primary_roi" and primary_t_zone_pixels >= MIN_USABLE_TZONE_PIXELS
    tzone_landmark_fallback_used = tzone_path == "tzone_landmark_fallback"
    tzone_face_fallback_used = tzone_path in {"tzone_face_fallback", "tzone_face_fallback_expanded"}

    cheek_union_after_expand_pixels = 0
    if points.shape[0] > 0:
        cheek_dilate_px = int(np.clip(round(min(h, w) * 0.01), 3, 7))
        cheek_dilate_kernel = cv2.getStructuringElement(
            cv2.MORPH_ELLIPSE,
            (cheek_dilate_px * 2 + 1, cheek_dilate_px * 2 + 1),
        )
        cheek_face_oval = _face_oval_mask((h, w), points)
        cheek_face_clip = (
            cheek_face_oval
            if cv2.countNonZero(cheek_face_oval) > 0
            else np.full((h, w), 255, dtype=np.uint8)
        )
        left_cheek_ids = [33, 130, 205, 50, 234, 132, 172, 136, 98]
        right_cheek_ids = [263, 359, 425, 280, 454, 361, 397, 365, 327]
        left_cheek_expanded = cv2.dilate(
            _polygon_mask((h, w), _expanded_polygon_points(points[left_cheek_ids], (h, w))),
            cheek_dilate_kernel,
            iterations=1,
        )
        right_cheek_expanded = cv2.dilate(
            _polygon_mask((h, w), _expanded_polygon_points(points[right_cheek_ids], (h, w))),
            cheek_dilate_kernel,
            iterations=1,
        )
        left_cheek_expanded = cv2.bitwise_and(left_cheek_expanded, cheek_face_clip)
        right_cheek_expanded = cv2.bitwise_and(right_cheek_expanded, cheek_face_clip)
        cheek_union_after_expand_pixels = int(
            cv2.countNonZero(cv2.bitwise_or(left_cheek_expanded, right_cheek_expanded))
        )

    cheek_reject_min = 1200 if cheek_union_after_expand_pixels >= 15000 else MIN_USABLE_CHEEK_PIXELS
    cheek_primary_usable = primary_cheek_pixels >= cheek_reject_min
    if primary_cheek_pixels < cheek_reject_min:
        logger.info(
            "CHEEK_ROI_REJECT pixels=%d min=%d -> using fallback",
            primary_cheek_pixels,
            cheek_reject_min,
        )

    forehead_pixels = int(cv2.countNonZero(forehead_skin_mask))
    texture_primary_usable = False
    texture_roi_source = "large_roi_fallback"
    if forehead_pixels >= MIN_USABLE_TEXTURE_ROI_PIXELS:
        texture_mask = forehead_skin_mask
        texture_primary_usable = True
        texture_roi_source = "primary_roi"
        texture_mask_kind = "forehead_skin"
    elif cheek_primary_usable:
        texture_mask = primary_cheek_mask
        texture_primary_usable = True
        texture_roi_source = "cheek_expand_no_skin" if cheek_expand_no_skin_used else "primary_roi"
        texture_mask_kind = "u_zone"
    else:
        texture_mask = full_face_skin_mask.copy()
        texture_mask_kind = "face_skin"

    if cheek_primary_usable:
        redness_roi_source = (
            "cheek_primary_no_skin_mask"
            if cheek_expand_no_skin_used
            else "cheek_primary"
        )
        pigment_roi_source = (
            "cheek_primary_no_skin_mask"
            if cheek_expand_no_skin_used
            else "cheek_primary"
        )
    else:
        redness_roi_source = "full_face_fallback"
        pigment_roi_source = "full_face_fallback"
    cheek_mask = primary_cheek_mask if cheek_primary_usable else full_face_skin_mask.copy()
    wrinkle_mask = cv2.bitwise_or(glabella, texture_mask)

    primary_texture_pixels = int(cv2.countNonZero(texture_mask))
    primary_pigment_pixels = int(cv2.countNonZero(cheek_mask))
    large_roi_fallback_used = (
        redness_roi_source != "cheek_primary"
        or texture_roi_source != "primary_roi"
    )

    fallback_used = large_roi_fallback_used
    bbox_fallback_used = False

    raw_components["primary_t_zone_skin_pixels_before_fix"] = float(primary_t_zone_pixels_before_fix)
    raw_components["primary_t_zone_after_expand_pixels"] = float(tzone_meta.get("after_expand_pixels", 0))
    raw_components["primary_t_zone_after_skin_pixels"] = float(tzone_meta.get("after_skin_pixels", 0))
    raw_components["tzone_landmark_fallback_used"] = 1.0 if tzone_landmark_fallback_used else 0.0
    raw_components["tzone_face_fallback_used"] = 1.0 if tzone_face_fallback_used else 0.0
    raw_components["tzone_primary_used"] = 1.0 if tzone_primary_used else 0.0

    raw_components["primary_cheek_roi_pixels"] = float(primary_cheek_pixels)
    raw_components["primary_cheek_skin_roi_pixels"] = float(primary_cheek_skin_pixels)
    raw_components["cheek_primary_usable"] = 1.0 if cheek_primary_usable else 0.0
    raw_components["cheek_expand_no_skin_used"] = 1.0 if cheek_expand_no_skin_used else 0.0
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
    raw_components["localized_redness_cheek_primary_used"] = 1.0 if redness_roi_source == "cheek_primary" else 0.0
    raw_components["localized_redness_cheek_primary_no_skin_mask_used"] = 1.0 if redness_roi_source == "cheek_primary_no_skin_mask" else 0.0
    raw_components["localized_redness_full_face_fallback_used"] = 1.0 if redness_roi_source == "full_face_fallback" else 0.0
    raw_components["localized_redness_primary_used"] = 1.0 if redness_roi_source == "cheek_primary" else 0.0
    raw_components["localized_redness_cheek_expand_no_skin_used"] = 1.0 if redness_roi_source == "cheek_primary_no_skin_mask" else 0.0
    raw_components["localized_redness_bbox_fallback_used"] = 1.0 if (redness_roi_source == "full_face_fallback" and bbox_fallback_used) else 0.0
    raw_components["localized_redness_large_fallback_used"] = 1.0 if (redness_roi_source == "full_face_fallback" and not bbox_fallback_used) else 0.0
    raw_components["pigment_cheek_primary_used"] = 1.0 if pigment_roi_source == "cheek_primary" else 0.0
    raw_components["pigment_cheek_primary_no_skin_mask_used"] = 1.0 if pigment_roi_source == "cheek_primary_no_skin_mask" else 0.0
    raw_components["pigment_full_face_fallback_used"] = 1.0 if pigment_roi_source == "full_face_fallback" else 0.0
    raw_components["texture_primary_used"] = 1.0 if texture_roi_source == "primary_roi" else 0.0
    raw_components["texture_forehead_skin_used"] = 1.0 if texture_mask_kind == "forehead_skin" else 0.0
    raw_components["texture_u_zone_used"] = 1.0 if texture_mask_kind == "u_zone" else 0.0
    raw_components["texture_cheek_expand_no_skin_used"] = 1.0 if texture_roi_source == "cheek_expand_no_skin" else 0.0
    raw_components["texture_bbox_fallback_used"] = 1.0 if texture_roi_source == "approximate_face_bbox" else 0.0
    raw_components["texture_large_fallback_used"] = 1.0 if texture_roi_source == "large_roi_fallback" else 0.0

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
        raw_components["mean_cheek_redness_proxy"] = round(
            float(np.clip(redness, 0.0, 100.0)),
            1,
        )
    confidence["localized_redness"] = _conf(cheek_pixels)
    if cheek_expand_no_skin_used and confidence["localized_redness"] == "high":
        confidence["localized_redness"] = "medium"

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
        if (
            texture_value is None
            or not math.isfinite(texture_value)
            or texture_value <= 0.0
        ) and texture_signal_present:
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
            fallback_redness = ((fallback_mean_a - personal_lab_baseline.get("a_mean", 128.0)) / 30.0) * 100.0
            clipped_fallback_redness = float(np.clip(fallback_redness, 0.0, 100.0))
            if clipped_fallback_redness > 0.0:
                matrix["localized_redness"] = round(
                    clipped_fallback_redness,
                    1,
                )
                confidence["localized_redness"] = _max_conf(
                    confidence.get("localized_redness", "low"),
                    _conf(texture_pixels),
                )
                if cheek_expand_no_skin_used and confidence["localized_redness"] == "high":
                    confidence["localized_redness"] = "medium"

    # Pore extraction: ROI-locked, scale-normalized, and high-confidence gated.
    pose_pitch, pose_yaw = _compute_pose_pitch_yaw_from_landmarks(points)
    pose_ok = abs(pose_pitch) <= 20.0 and abs(pose_yaw) <= 18.0
    face_detected = points.shape[0] > 0
    pore_visibility_detected = False

    pore_l_crop, pore_mask_crop, pore_roi_pixels = _extract_native_resolution_pore_roi(
        face_bgr,
        points,
        full_face_skin_mask,
    )
    raw_components["pores_roi_pixels"] = float(pore_roi_pixels)
    raw_components["pore_pose_pitch"] = round(float(pose_pitch), 4)
    raw_components["pore_pose_yaw"] = round(float(pose_yaw), 4)
    raw_components["pore_visibility_face_detected"] = 1.0 if face_detected else 0.0
    raw_components["pore_visibility_pose_ok"] = 1.0 if pose_ok else 0.0
    raw_components["pore_visibility_crop_available"] = (
        1.0 if pore_l_crop is not None and pore_mask_crop is not None else 0.0
    )
    raw_components["pore_visibility_dog_spread_failed"] = 0.0

    if (
        face_detected
        and pose_ok
        and pore_l_crop is not None
        and pore_mask_crop is not None
        and pore_roi_pixels > 5000
    ):
        blur_small = cv2.GaussianBlur(pore_l_crop, (0, 0), 1.0)
        blur_large = cv2.GaussianBlur(pore_l_crop, (0, 0), 2.0)
        dog = np.abs(blur_small - blur_large)
        dog_vals = dog[pore_mask_crop > 0]
        if dog_vals.size > 0:
            pore_response_mean = float(np.mean(dog_vals))
            pore_spread = float(np.std(dog_vals))
            if not np.isfinite(pore_response_mean) or not np.isfinite(pore_spread):
                confidence["pore_visibility"] = "low"
                logger.info(
                    "PORE OMITTED reason=non_finite_stats roi_pixels=%d mean=%s spread=%s",
                    pore_roi_pixels,
                    pore_response_mean,
                    pore_spread,
                )
            else:
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
                    raw_components["pore_visibility_dog_spread_failed"] = 1.0
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

    chin_l_crop, chin_mask_crop, chin_pore_roi_pixels = _extract_native_resolution_chin_pore_roi(
        face_bgr,
        points,
        full_face_skin_mask,
    )
    raw_components["chin_pore_roi_pixels"] = float(chin_pore_roi_pixels)
    raw_components["chin_pore_visibility_mask_kind"] = "chin_pore"
    raw_components["chin_pore_visibility_mask_pixels"] = float(chin_pore_roi_pixels)
    if (
        face_detected
        and pose_ok
        and chin_l_crop is not None
        and chin_mask_crop is not None
        and chin_pore_roi_pixels > 5000
    ):
        blur_small = cv2.GaussianBlur(chin_l_crop, (0, 0), 1.0)
        blur_large = cv2.GaussianBlur(chin_l_crop, (0, 0), 2.0)
        dog = np.abs(blur_small - blur_large)
        dog_vals = dog[chin_mask_crop > 0]
        if dog_vals.size > 0:
            chin_response_mean = float(np.mean(dog_vals))
            chin_spread = float(np.std(dog_vals))
            if not np.isfinite(chin_response_mean) or not np.isfinite(chin_spread):
                confidence["chin_pore_visibility"] = "low"
                logger.info(
                    "CHIN_PORE OMITTED reason=non_finite_stats roi_pixels=%d mean=%s spread=%s",
                    chin_pore_roi_pixels,
                    chin_response_mean,
                    chin_spread,
                )
            else:
                chin_confidence = _pore_signal_conf(chin_pore_roi_pixels, chin_spread)
                confidence["chin_pore_visibility"] = chin_confidence
                raw_components["chin_pore_hf_energy"] = round(float(chin_response_mean), 4)
                raw_components["chin_pore_spread"] = round(float(chin_spread), 4)
                if chin_confidence != "low":
                    pores = 100.0 / (1.0 + math.exp(-(chin_response_mean - 7.5) / 1.9))
                    matrix["chin_pore_visibility"] = round(float(np.clip(pores, 0.0, 100.0)), 1)
                    logger.info(
                        "CHIN_PORE SCORED value=%.1f confidence=%s roi_pixels=%d pitch=%.2f yaw=%.2f",
                        matrix["chin_pore_visibility"],
                        chin_confidence,
                        chin_pore_roi_pixels,
                        pose_pitch,
                        pose_yaw,
                    )
                else:
                    logger.info(
                        "CHIN_PORE OMITTED reason=confidence_%s roi_pixels=%d",
                        chin_confidence,
                        chin_pore_roi_pixels,
                    )
        else:
            confidence["chin_pore_visibility"] = "low"
            logger.info("CHIN_PORE OMITTED reason=empty_signal")
    else:
        confidence["chin_pore_visibility"] = "low"
        logger.info(
            "CHIN_PORE OMITTED reason=gate_failed face_detected=%s pose_ok=%s roi_pixels=%d pitch=%.2f yaw=%.2f",
            face_detected,
            pose_ok,
            chin_pore_roi_pixels,
            pose_pitch,
            pose_yaw,
        )

    raw_components["primary_pore_roi_pixels"] = float(pore_roi_pixels)
    raw_components["fallback_pore_roi_pixels"] = 0.0
    raw_components["pore_fallback_used"] = 0.0

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
            # Deviation is measured from this cheek's own mean colour rather
            # than a fixed grey point, which scored skin-tone warmth as pigment.
            chroma_dev = np.sqrt((cheek_a - mean_a) ** 2 + (cheek_b - mean_b) ** 2)
            pigment_dev = float(np.percentile(chroma_dev, 85)) if chroma_dev.size > 0 else 0.0
        else:
            pigment_dev = 0.0

        l_contrast = float(np.std(cheek_l)) if cheek_l.size > 0 else 0.0
        pigment_signal = pigment_dev + (PIGMENT_LOAD_L_CONTRAST_WEIGHT * l_contrast)
        pre_adjustment = 100.0 / (1.0 + math.exp(-(pigment_signal - PIGMENT_LOAD_SCORE_CENTER) / 4.0))
        effective_signal = max(0.0, pigment_signal - PIGMENT_LOAD_DEAD_ZONE_SIGNAL)
        # Provisional stretch: the old sigmoid compressed most real-world skin
        # variation into the 88-100 band. A small dead zone and a wider slope
        # preserve ranking while allowing actual differences to register.
        pigment = compute_pigment_load(pigment_signal)
        logger.info(
            "PIGMENT_LOAD raw_signal=%.2f dead_zone=%.1f effective_signal=%.2f pre_adjustment=%.1f final=%.1f",
            pigment_signal,
            PIGMENT_LOAD_DEAD_ZONE_SIGNAL,
            effective_signal,
            pre_adjustment,
            pigment,
        )
        matrix["pigment_load"] = round(float(np.clip(pigment, 0.0, 100.0)), 1)

        confidence["pigment_load"] = _signal_conf(
            cheek_pixels,
            spread=pigment_dev,
            low_spread=4.0,
            high_spread=8.5,
        )
        if cheek_expand_no_skin_used and confidence["pigment_load"] == "high":
            confidence["pigment_load"] = "medium"
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
        raw_key = str(key).strip().lower()
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
        # Rosacea severity is already emitted on a calibrated 0-100 scale.
        if normalized_key in ten_point_keys and 0.0 <= numeric <= 10.0 and raw_key != "rosacea_severity":
            numeric *= 10.0

        normalized[key] = round(float(np.clip(numeric, 0.0, 100.0)), 1)
    return normalized


CANONICAL_METRIC_ORDER = [
    # PRODUCER REGISTRY (single-canonical-producer rule, audited 2026-09-21):
    # every key below must be sourced from exactly ONE producer in the
    # candidate_values dict built in analyze_skin_patch. If you add a new
    # metric or change which dict a key reads from, update both
    # candidate_values AND test_canonical_metric_producer_registry.py in the
    # same change - that test fails loudly on any silent drift.
    #   localized_redness              -> canonical_metric_matrix (_compute_canonical_patch_metrics)
    #   texture_smoothness             -> canonical_metric_matrix (_compute_canonical_patch_metrics)
    #   pigment_load                   -> canonical_metric_matrix (_compute_canonical_patch_metrics)
    #   pore_visibility                -> canonical_metric_matrix (_compute_canonical_patch_metrics)
    #   wrinkle_load                   -> canonical_metric_matrix (_compute_canonical_patch_metrics)
    #   breakout_activity              -> canonical_metric_matrix (_compute_canonical_patch_metrics)
    #   sebum_excess_oil_gloss         -> additional_metrics (_compute_additional_opencv_metrics)
    #   diffuse_flushing_erythema      -> additional_metrics (_compute_additional_opencv_metrics)
    #   skin_tone_radiance_evenness    -> additional_metrics (_compute_additional_opencv_metrics)
    #   glabellar_wrinkle_depth        -> structural_metrics (_compute_structural_opencv_metrics)
    #   structural_firmness_elasticity -> structural_metrics (_compute_structural_opencv_metrics)
    #   pore_contraction_index         -> structural_metrics (_compute_structural_opencv_metrics)
    #   under_eye_texture_density      -> zone_metrics (_compute_zone_based_metrics)
    #   under_eye_dark_circle_density  -> zone_metrics (_compute_zone_based_metrics)
    #   rosacea_severity               -> zone_metrics (_compute_zone_based_metrics)
    #   skin_hydration                 -> NO PRODUCER (declared canonical, never computed;
    #                                      always omitted as "non_usable_value" - known gap,
    #                                      not a competing-producer issue)
    # zone_metrics retains localized_redness for the live baseline-alias
    # compatibility path; the other former dead/shadowed calculations were
    # removed after the producer audit. See _compute_zone_based_metrics.
    "localized_redness",
    "texture_smoothness",
    "pigment_load",
    "pore_visibility",
    "chin_pore_visibility",
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
    "skin_hydration",
]

HIGHER_IS_WORSE_METRICS = {
    "rosacea_severity",
    "localized_redness",
    "diffuse_flushing_erythema",
    "pigment_load",
    "pore_visibility",
    "chin_pore_visibility",
    "wrinkle_load",
    "glabellar_wrinkle_depth",
    "breakout_activity",
    "sebum_excess_oil_gloss",
}

HIGHER_IS_BETTER_METRICS = {
    "skin_tone_radiance_evenness",
    "structural_firmness_elasticity",
    "texture_smoothness",
    "skin_hydration",
}

HONESTY_STABLE_BAND_PCT = 8.0

# PROVISIONAL, two-session calibration. Measured via
# tool/analyze_repeatability.py from TWO separate 5-scan repeatability runs:
# same person, same device (iPhone), back-to-back captures within each
# session. Each value is the MAX of the two sessions' own 2-SD figures, not
# an average -- picking the larger of two small samples is itself a
# conservative choice, but it is still just two data points per metric.
# This is a single-subject/single-device noise estimate, NOT a validated
# population constant -- it has not been checked across different people,
# skin tones, other devices (Android cameras in particular may differ
# substantially), or lighting conditions, and must be re-measured on other
# devices/lighting before being treated as general.
#
# The two sessions themselves disagreed more than a single-session snapshot
# would suggest: the under-eye metrics roughly DOUBLED between sessions
# (under_eye_dark_circle_density 7.6 -> 14.1, under_eye_texture_density
# 3.2 -> 6.0) and are the least settled figures in this table -- treat them
# as the most likely to move again on a third session. More broadly, the
# metrics' own absolute readings shifted substantially between the two
# sessions (e.g. texture_smoothness's mean moved from roughly 28.2 to 47.9),
# so it is NOT established that the two sessions are even measuring
# comparable conditions (lighting/framing/skin state could differ) -- these
# floors should be read as "the largest noise observed so far", not as
# values known to be cross-session comparable. Revisit once more
# repeatability sessions (ideally multiple subjects and devices) accumulate.
# Values are 2 standard deviations of a session's 5 scan means, in each
# metric's own 0-100 units -- see _trend_delta_and_status's use of this
# table for how it gates trend claims.
METRIC_NOISE_FLOOR_2SD: Dict[str, float] = {
    "localized_redness": 6.8,
    "rosacea_severity": 3.9,
    "glabellar_wrinkle_depth": 6.4,
    "texture_smoothness": 5.4,
    "wrinkle_load": 3.7,
    "under_eye_dark_circle_density": 14.1,
    "under_eye_texture_density": 6.0,
    "structural_firmness_elasticity": 3.0,
    "pigment_load": 2.0,
    "skin_tone_radiance_evenness": 1.1,
    "pore_visibility": 1.0,
    "breakout_activity": 13.1,
}

# Human-judgment call, not derived from a formula: these metrics' measured
# noise floors are comparable to or larger than the range most real users
# ever show -- this app's own "calm" reference band uses
# localized_redness=5.0 / rosacea_severity=4.0 (see
# TestLocalizedRednessAndRosacea in test_scoring_formulas.py), prior
# real-log evidence showed rosacea staying <=3.8 across frames, and
# breakout_activity's own measured floor (13.1) is comparable to its whole
# observed range in real logs (near-zero to the low teens for most
# non-severe scans) -- unlike e.g. glabellar_wrinkle_depth or
# under_eye_dark_circle_density, whose floors are similarly sized in
# absolute terms but small relative to their own much wider typical
# population range (wrinkle depth in particular spans near-0 to 40+ across
# a real population). Revisit per-metric as real usage data accumulates;
# this is a curated set, not an automatic ratio, because "useful range" is
# a domain judgment no existing constant encodes.
TREND_NOISE_FLOOR_EXCEEDS_USEFUL_RANGE = {
    "localized_redness",
    "rosacea_severity",
    "breakout_activity",
}

# For a metric in TREND_NOISE_FLOOR_EXCEEDS_USEFUL_RANGE, a delta must
# exceed this many multiples of its measured 2-SD noise floor before any
# directional (improved/worsened) claim is made; below that the comparison
# is reported as insufficient_signal, never "stable" -- for these metrics
# "stable" is itself an overconfident claim, since their floor already
# swallows most of the range real users show, so an ordinary below-floor
# reading would report "stable" for nearly everyone, always, regardless of
# whether the true value moved.
#
# 3x is deliberately conservative. 2 SD alone only bounds ~95% of a single
# scan-to-scan comparison's noise under a normal-distribution assumption --
# and that assumption itself rests on a 5-scan sample, whose own estimate of
# the true standard deviation carries real sampling uncertainty at that size
# (a 5-sample stdev can easily be off by 30-40% from the true population
# value). Requiring 3x the measured floor, rather than 1x, pushes the
# effective margin well past that estimation error specifically for the two
# metrics whose usable signal is already the narrowest -- at the deliberate
# cost of also requiring a materially larger real change before either can
# ever report a directional trend at all.
TREND_NOISE_FLOOR_EXCLUDED_MULTIPLIER = 3.0

# Registry of scoring-formula changes, per metric. Empty until a metric's
# formula actually changes -- every metric implicitly starts at version 1
# (see _metric_formula_version), so nothing needs an entry here just to
# exist. When a metric's scoring formula changes (e.g. a future fix to
# texture_smoothness's or glabellar_wrinkle_depth's amplification), bump
# its entry here in the SAME change. That is what lets
# _trend_delta_and_status / _trend_lock_reason detect that a baseline
# score and a current score for that metric were produced by different
# formulas -- and are therefore not comparable -- even though capture
# quality, extraction path, and resolution all match. This registry does
# NOT itself change any formula; it only lets the trend gate react once a
# future change bumps an entry.
METRIC_FORMULA_VERSION: Dict[str, int] = {
    "localized_redness": 3,
    # v3 uses the Laplacian fallback path exclusively; v2 primary-ROI values
    # are not comparable with the single-path metric.
    "texture_smoothness": 3,
    "pigment_load": 2,
    "wrinkle_load": 2,
    "sebum_excess_oil_gloss": 2,
    "diffuse_flushing_erythema": 2,
    # v3: the U-zone formula is the only producer. The post-emission
    # recomputation from emitted redness + diffuse flushing is gone, so a
    # scan whose zone formula did not emit now omits rosacea instead.
    "rosacea_severity": 3,
    "pore_visibility": 3,
    "chin_pore_visibility": 1,
    "pore_contraction_index": 2,
    # v2: fixed avg_width quantization (boundingRect integer px -> minAreaRect
    # continuous size) and the 26-32%-of-photos zero-out (82nd-percentile
    # threshold + (3,5) opening kernel erasing thin-but-real furrow
    # responses entirely). See the GLABELLAR_ZERO_OUT_FIX /
    # GLABELLAR_WIDTH_QUANTIZATION_FIX comments in
    # _compute_structural_opencv_metrics.
    "glabellar_wrinkle_depth": 2,
    # v2: both are omitted when their shared under-eye mask is below
    # MIN_USABLE_TZONE_PIXELS, so a previously emitted value can be absent.
    # Neither formula changed.
    "under_eye_texture_density": 2,
    "under_eye_dark_circle_density": 2,
}


def _metric_formula_version(metric_key: str) -> int:
    return METRIC_FORMULA_VERSION.get(metric_key, 1)

# Body silhouette comparisons are materially noisier than face metrics: in real validation,
# two different full-body stock photos varied by ~56% in normalized_area_index purely due to
# different people, poses, and framing. This means a body-area trend cannot be treated like a
# face metric with a small 8% honesty band. The threshold below is intentionally conservative
# and is a placeholder only.
# IMPORTANT: this 60% band is calibrated from CROSS-PERSON noise, not real same-person
# before/after variance. It is measuring "how much random unrelated photos differ" rather than
# "how much a genuine healing change typically moves this metric." As a result, it is likely
# far too conservative for detecting real change and may suppress legitimate trends entirely
# until real same-person paired scan data exists. This is deliberately chosen to guarantee safety
# (no false positives) at the likely cost of never showing a real trend at all until better data
# is collected and re-calibrated.
BODY_SILHOUETTE_HONESTY_BAND_PCT = 60.0
# HARD gate: if the scale reference changes by more than 20%, the framing distance/pose is too
# different to compare area meaningfully. This is stricter than a soft signal because body area
# inherently drifts with capture distance and composition.
BODY_SILHOUETTE_SCALE_MISMATCH_RATIO = 0.20
BODY_SILHOUETTE_MIN_CONFIDENCE = 0.65
BODY_SILHOUETTE_REQUIRED_CONSISTENT_SCANS = 2
# PROVISIONAL: source dimensions above this per-axis difference are treated as
# a different measurement setup until same-person resolution stability data exists.
SOURCE_RESOLUTION_MISMATCH_RATIO = 0.20


def _normalize_extraction_path_label(value: Any) -> str:
    if value is None:
        return "unknown"
    text = str(value).strip().lower().replace("-", "_").replace(" ", "_")
    if text in {
        "cheek_primary",
        "cheek_primary_no_skin_mask",
        "full_face_fallback",
        "full_face_yolo",
        "laplacian_fallback",
        "cheek_expand_no_skin",
        "large_roi_fallback",
        "approximate_face_bbox",
        "tzone_landmark_fallback",
        "tzone_face_fallback",
        "primary_roi",
        "fallback",
    }:
        return text
    if text in {"primary_roi", "primary", "roi", "primaryroi"}:
        return "primary_roi"
    if text in {
        "fallback",
        "fallback_roi",
        "bbox_fallback",
        "fallbackroi",
        "laplacian_fallback",
        "large_roi_fallback",
        "approximate_face_bbox",
        "tzone_landmark_fallback",
        "tzone_face_fallback",
    }:
        return "fallback"
    if text in {"skipped", "omit", "omitted", "not_computed", "unavailable"}:
        return "skipped"
    return "unknown"


def _normalize_metric_extraction_paths(raw: Any, metric_keys: list[str]) -> Dict[str, str]:
    normalized = {key: "unknown" for key in metric_keys}
    if raw is None:
        return normalized

    payload = raw
    if isinstance(raw, str):
        text = raw.strip()
        if not text:
            return normalized
        payload = json.loads(text)

    if not isinstance(payload, dict):
        return normalized

    for key, value in payload.items():
        canonical_map = _coalesce_metric_aliases({str(key): 1.0})
        if not canonical_map:
            continue
        canonical_key = next(iter(canonical_map.keys()))
        if canonical_key not in normalized:
            continue
        normalized[canonical_key] = _normalize_extraction_path_label(value)

    return normalized


def _normalize_metric_formula_versions(raw: Any, metric_keys: list[str]) -> Dict[str, int]:
    """Missing/invalid entries default to 1 -- a scan saved before this
    field existed, or a metric this session doesn't track a version for,
    is treated as the original formula, never as a value the trend gate
    should refuse to compare."""
    normalized = {key: 1 for key in metric_keys}
    if raw is None:
        return normalized

    payload = raw
    if isinstance(raw, str):
        text = raw.strip()
        if not text:
            return normalized
        try:
            payload = json.loads(text)
        except (TypeError, ValueError):
            return normalized

    if not isinstance(payload, dict):
        return normalized

    for key, value in payload.items():
        canonical_map = _coalesce_metric_aliases({str(key): 1.0})
        if not canonical_map:
            continue
        canonical_key = next(iter(canonical_map.keys()))
        if canonical_key not in normalized:
            continue
        try:
            normalized[canonical_key] = int(value)
        except (TypeError, ValueError):
            continue

    return normalized


def _normalize_baseline_metric_formula_versions(
    raw: Any,
    metric_keys: list[str],
) -> Dict[str, int]:
    """Parse only baseline versions that were explicitly sent and valid."""
    normalized: Dict[str, int] = {}
    if raw is None:
        return normalized

    payload = raw
    if isinstance(raw, str):
        text = raw.strip()
        if not text:
            return normalized
        try:
            payload = json.loads(text)
        except (TypeError, ValueError):
            return normalized

    if not isinstance(payload, dict):
        return normalized

    for key, value in payload.items():
        canonical_map = _coalesce_metric_aliases({str(key): 1.0})
        if not canonical_map:
            continue
        canonical_key = next(iter(canonical_map.keys()))
        if canonical_key not in metric_keys:
            continue
        try:
            normalized[canonical_key] = int(value)
        except (TypeError, ValueError):
            continue

    return normalized


def _baseline_formula_versions_for_redness_reference(
    formula_versions: Dict[str, int],
    baseline_matrix: Dict[str, Any],
) -> Dict[str, int]:
    normalized = dict(formula_versions)
    canonical_baseline = _coalesce_metric_aliases(baseline_matrix)
    has_redness_score = safe_float(canonical_baseline.get("localized_redness")) is not None
    has_personal_p95 = (
        safe_float(_coalesce_personal_lab_baseline(baseline_matrix).get("a_p95"))
        is not None
    )
    if has_redness_score and not has_personal_p95:
        normalized["localized_redness"] = 2
    return normalized


def _normalize_capture_quality(value: Any) -> str:
    if value is None:
        return "unknown"
    text = str(value).strip().lower().replace("-", "_").replace(" ", "_")
    if not text:
        return "unknown"
    if text in {
        "normal",
        "low_light",
        "face_offcenter",
        "poor_angle",
        "uneven_lighting",
        "blurry",
        "unknown",
    }:
        return text
    return "unknown"


def _compute_metric_extraction_paths(
    metric_status: Dict[str, str],
    raw_components: Dict[str, float],
    metric_keys: list[str],
) -> Dict[str, str]:
    fallback_used = bool(raw_components.get("fallback_used", 0.0) > 0.5)
    bbox_fallback_used = bool(raw_components.get("bbox_fallback_used", 0.0) > 0.5)
    pore_fallback_used = bool(raw_components.get("pore_fallback_used", 0.0) > 0.5)

    out: Dict[str, str] = {}
    for key in metric_keys:
        status = metric_status.get(key, "unavailable")
        if status != "computed":
            out[key] = "skipped"
            continue

        if key == "pore_visibility" and pore_fallback_used:
            out[key] = "fallback"
            continue

        if key == "sebum_excess_oil_gloss":
            if bool(raw_components.get("tzone_primary_used", 0.0) > 0.5):
                out[key] = "primary_roi"
            elif bool(raw_components.get("tzone_landmark_fallback_used", 0.0) > 0.5):
                out[key] = "tzone_landmark_fallback"
            elif bool(raw_components.get("tzone_face_fallback_used", 0.0) > 0.5):
                out[key] = "tzone_face_fallback"
            else:
                out[key] = "fallback"
            continue

        if key == "localized_redness":
            if bool(raw_components.get("localized_redness_cheek_primary_used", 0.0) > 0.5):
                out[key] = "cheek_primary"
            elif bool(raw_components.get("localized_redness_cheek_primary_no_skin_mask_used", 0.0) > 0.5):
                out[key] = "cheek_primary_no_skin_mask"
            elif bool(raw_components.get("localized_redness_full_face_fallback_used", 0.0) > 0.5):
                out[key] = "full_face_fallback"
            elif bool(raw_components.get("localized_redness_primary_used", 0.0) > 0.5):
                out[key] = "cheek_primary"
            elif bool(raw_components.get("localized_redness_bbox_fallback_used", 0.0) > 0.5):
                out[key] = "full_face_fallback"
            elif bool(raw_components.get("localized_redness_large_fallback_used", 0.0) > 0.5):
                out[key] = "full_face_fallback"
            else:
                out[key] = "full_face_fallback" if (fallback_used or bbox_fallback_used) else "cheek_primary"
            continue

        if key == "pigment_load":
            if bool(raw_components.get("pigment_cheek_primary_used", 0.0) > 0.5):
                out[key] = "cheek_primary"
            elif bool(raw_components.get("pigment_cheek_primary_no_skin_mask_used", 0.0) > 0.5):
                out[key] = "cheek_primary_no_skin_mask"
            elif bool(raw_components.get("pigment_full_face_fallback_used", 0.0) > 0.5):
                out[key] = "full_face_fallback"
            else:
                out[key] = "full_face_fallback" if (fallback_used or bbox_fallback_used) else "cheek_primary"
            continue

        if key == "texture_smoothness":
            if bool(raw_components.get("texture_cheek_expand_no_skin_used", 0.0) > 0.5):
                out[key] = "cheek_expand_no_skin"
                continue
            if bool(raw_components.get("texture_laplacian_fallback_used", 0.0) > 0.5):
                out[key] = "laplacian_fallback"
            elif bool(raw_components.get("texture_primary_used", 0.0) > 0.5):
                out[key] = "primary_roi"
            elif bool(raw_components.get("texture_bbox_fallback_used", 0.0) > 0.5):
                out[key] = "approximate_face_bbox"
            elif bool(raw_components.get("texture_large_fallback_used", 0.0) > 0.5):
                out[key] = "large_roi_fallback"
            else:
                out[key] = "fallback" if (fallback_used or bbox_fallback_used) else "primary_roi"
            continue

        if key == "wrinkle_load":
            if bool(raw_components.get("texture_cheek_expand_no_skin_used", 0.0) > 0.5):
                out[key] = "cheek_expand_no_skin"
            elif bool(raw_components.get("texture_primary_used", 0.0) > 0.5):
                out[key] = "primary_roi"
            elif bool(raw_components.get("texture_large_fallback_used", 0.0) > 0.5):
                out[key] = "large_roi_fallback"
            elif bool(raw_components.get("texture_laplacian_fallback_used", 0.0) > 0.5):
                out[key] = "laplacian_fallback"
            elif bool(raw_components.get("texture_bbox_fallback_used", 0.0) > 0.5):
                out[key] = "approximate_face_bbox"
            else:
                out[key] = "large_roi_fallback" if (fallback_used or bbox_fallback_used) else "primary_roi"
            continue

        if key == "breakout_activity":
            out[key] = "full_face_yolo"
            continue

        if key in {
            "localized_redness",
            "texture_smoothness",
            "pigment_load",
            "wrinkle_load",
            "breakout_activity",
        } and (fallback_used or bbox_fallback_used):
            out[key] = "fallback"
            continue

        out[key] = "primary_roi"

    return out


def _pore_visibility_omission_path(raw_components: Dict[str, float]) -> str:
    if (
        raw_components.get("pore_visibility_face_detected", 0.0) <= 0.5
        or raw_components.get("pore_visibility_pose_ok", 0.0) <= 0.5
    ):
        return "pose"
    if (
        raw_components.get("pore_visibility_crop_available", 0.0) <= 0.5
        or raw_components.get("primary_pore_roi_pixels", 0.0) <= 5000.0
    ):
        return "crop"
    if raw_components.get("pore_visibility_dog_spread_failed", 0.0) > 0.5:
        return "dog_spread"
    return "skipped"


def _metric_higher_is_worse(metric_key: str) -> bool:
    if metric_key in HIGHER_IS_BETTER_METRICS:
        return False
    if metric_key in HIGHER_IS_WORSE_METRICS:
        return True
    return True


def _source_resolutions_comparable(
    current_width: int | None,
    current_height: int | None,
    baseline_width: int | None,
    baseline_height: int | None,
) -> bool:
    if None in (current_width, current_height, baseline_width, baseline_height):
        return True
    if min(current_width, current_height, baseline_width, baseline_height) <= 0:
        return True
    return (
        abs(current_width - baseline_width) / baseline_width <= SOURCE_RESOLUTION_MISMATCH_RATIO
        and abs(current_height - baseline_height) / baseline_height <= SOURCE_RESOLUTION_MISMATCH_RATIO
    )


def _trend_delta_and_status(
    metric_key: str,
    current: float,
    baseline: float,
    current_path: str,
    baseline_path: str,
    honesty_band_pct: float,
    current_capture_quality: str = "unknown",
    baseline_capture_quality: str = "unknown",
    current_source_width: int | None = None,
    current_source_height: int | None = None,
    baseline_source_width: int | None = None,
    baseline_source_height: int | None = None,
    current_formula_version: int = 1,
    baseline_formula_version: int | None = 1,
    current_pose_template: str | None = None,
    baseline_pose_template: str | None = None,
    current_guide_type: str | None = None,
    baseline_guide_type: str | None = None,
) -> tuple[float, str]:
    if abs(baseline) < 1e-9:
        return 0.0, "stable"

    current_quality = (
        _normalize_capture_quality(current_capture_quality)
        if current_capture_quality is not None
        else "normal"
    )
    baseline_quality = (
        _normalize_capture_quality(baseline_capture_quality)
        if baseline_capture_quality is not None
        else "normal"
    )
    if current_quality == "unknown" or baseline_quality == "unknown":
        return 0.0, "stable"
    if current_quality != "normal" or baseline_quality != "normal":
        return 0.0, "stable"

    if current_path == "unknown" or baseline_path == "unknown":
        return 0.0, "stable"
    if current_path != baseline_path:
        return 0.0, "stable"
    if not _source_resolutions_comparable(
        current_source_width,
        current_source_height,
        baseline_source_width,
        baseline_source_height,
    ):
        return 0.0, "stable"
    # Angle/region honesty gate: only compare scans with the SAME recorded
    # pose template (view angle -- "Left 45°" is never "Left Profile") AND
    # the SAME camera guide type (facial/body/general). A missing value on
    # either side means the angle or region is unknown for that scan and is
    # never treated as a match -- same principle as the capture-quality/
    # path/resolution gates above, just for framing instead of exposure/
    # analysis method.
    if (
        not current_pose_template
        or not baseline_pose_template
        or current_pose_template != baseline_pose_template
    ):
        return 0.0, "stable"
    if (
        not current_guide_type
        or not baseline_guide_type
        or current_guide_type != baseline_guide_type
    ):
        return 0.0, "stable"
    # A scoring-formula change for this metric (see METRIC_FORMULA_VERSION)
    # makes its baseline and current values incomparable even though
    # capture quality/path/resolution all match -- a stored score from the
    # old formula doesn't mean the same thing as one from the new formula.
    if (
        baseline_formula_version is None
        or current_formula_version != baseline_formula_version
    ):
        return 0.0, "stable"

    denominator = abs(baseline)
    if _metric_higher_is_worse(metric_key):
        directional_delta = ((baseline - current) / denominator) * 100.0
    else:
        directional_delta = ((current - baseline) / denominator) * 100.0

    # Measured-noise-floor gate (see METRIC_NOISE_FLOOR_2SD's comment):
    # requires an absolute minimum change, sized to this specific metric's
    # own measured scan-to-scan noise, in addition to the relative honesty
    # band below. A metric with no measured floor is unaffected.
    noise_floor = METRIC_NOISE_FLOOR_2SD.get(metric_key)
    if noise_floor is not None:
        absolute_delta = abs(current - baseline)
        if metric_key in TREND_NOISE_FLOOR_EXCEEDS_USEFUL_RANGE:
            required_delta = noise_floor * TREND_NOISE_FLOOR_EXCLUDED_MULTIPLIER
            if absolute_delta < required_delta:
                # Not "stable" -- for this metric, a below-floor reading
                # doesn't mean "confirmed no change", it means the pipeline
                # cannot resolve real change from noise at all. Saying
                # "stable" here would be a confident-sounding claim this
                # metric's own measured noise floor doesn't support.
                return 0.0, "insufficient_signal"
        elif absolute_delta < noise_floor:
            return 0.0, "stable"

    if abs(directional_delta) < honesty_band_pct:
        return 0.0, "stable"

    rounded = round(directional_delta, 1)
    if rounded > 0:
        return rounded, "improved"
    if rounded < 0:
        return rounded, "worsened"
    return 0.0, "stable"


def _trend_lock_reason(
    current_path: str,
    baseline_path: str,
    current_capture_quality: str = "unknown",
    baseline_capture_quality: str = "unknown",
    current_source_width: int | None = None,
    current_source_height: int | None = None,
    baseline_source_width: int | None = None,
    baseline_source_height: int | None = None,
    current_formula_version: int = 1,
    baseline_formula_version: int | None = 1,
    current_pose_template: str | None = None,
    baseline_pose_template: str | None = None,
    current_guide_type: str | None = None,
    baseline_guide_type: str | None = None,
) -> str | None:
    """Purely-informational companion to _trend_delta_and_status.

    Mirrors the SAME honesty-gate checks in the SAME order as
    _trend_delta_and_status so the UI can explain *why* a metric was forced
    to "stable", without altering any gating logic/thresholds. Returns None
    whenever the gates above would not have forced a lock (including the
    genuine, honest "stable" case where the real delta is just inside the
    honesty band) — that case keeps its normal "steady" messaging.
    """
    current_quality = (
        _normalize_capture_quality(current_capture_quality)
        if current_capture_quality is not None
        else "normal"
    )
    baseline_quality = (
        _normalize_capture_quality(baseline_capture_quality)
        if baseline_capture_quality is not None
        else "normal"
    )
    if current_quality == "unknown" or baseline_quality == "unknown":
        return "capture_quality_mismatch"
    if current_quality != "normal" or baseline_quality != "normal":
        return "capture_quality_mismatch"

    if current_path == "unknown" or baseline_path == "unknown":
        return "path_mismatch"
    if current_path != baseline_path:
        return "path_mismatch"

    if not _source_resolutions_comparable(
        current_source_width,
        current_source_height,
        baseline_source_width,
        baseline_source_height,
    ):
        return "resolution_mismatch"

    if (
        not current_pose_template
        or not baseline_pose_template
        or current_pose_template != baseline_pose_template
        or not current_guide_type
        or not baseline_guide_type
        or current_guide_type != baseline_guide_type
    ):
        return "angle_or_guide_mismatch"

    if (
        baseline_formula_version is None
        or current_formula_version != baseline_formula_version
    ):
        return "formula_version_mismatch"

    return None


def _body_trend_delta_and_status(
    metric_key: str,
    current: float,
    baseline: float,
    current_scale_reference_pixels: float | None,
    baseline_scale_reference_pixels: float | None,
    current_confidence: float | None,
    baseline_confidence: float | None,
    current_capture_quality: str = "normal",
    baseline_capture_quality: str = "normal",
    honesty_band_pct: float = BODY_SILHOUETTE_HONESTY_BAND_PCT,
    minimum_consistent_scans: int = BODY_SILHOUETTE_REQUIRED_CONSISTENT_SCANS,
    current_capture_mode: str | None = None,
    baseline_capture_mode: str | None = None,
    current_source_width: int | None = None,
    current_source_height: int | None = None,
    baseline_source_width: int | None = None,
    baseline_source_height: int | None = None,
) -> tuple[float, str]:
    # Body silhouette change is not comparable to face metrics until capture is highly controlled.
    # Real different-person validation showed ~56% variance from framing alone; this metric should
    # only ever show a real improved/worsened claim after multiple consistent measurements, not a
    # single baseline/current pair. Until same-person paired data exists, the safe default is to
    # degrade to stable/insufficient_signal unless the evidence is substantially stronger.
    if abs(baseline) < 1e-9:
        return 0.0, "insufficient_signal"

    current_quality = (
        _normalize_capture_quality(current_capture_quality)
        if current_capture_quality is not None
        else "normal"
    )
    baseline_quality = (
        _normalize_capture_quality(baseline_capture_quality)
        if baseline_capture_quality is not None
        else "normal"
    )
    if current_quality == "unknown" or baseline_quality == "unknown":
        return 0.0, "stable"
    if current_quality != "normal" or baseline_quality != "normal":
        return 0.0, "stable"
    if not _source_resolutions_comparable(
        current_source_width,
        current_source_height,
        baseline_source_width,
        baseline_source_height,
    ):
        return 0.0, "stable"

    if current_confidence is None or baseline_confidence is None:
        return 0.0, "insufficient_signal"
    if current_confidence < BODY_SILHOUETTE_MIN_CONFIDENCE or baseline_confidence < BODY_SILHOUETTE_MIN_CONFIDENCE:
        return 0.0, "stable"

    if (
        current_scale_reference_pixels is None
        or baseline_scale_reference_pixels is None
        or baseline_scale_reference_pixels <= 0.0
    ):
        return 0.0, "insufficient_signal"

    scale_ratio_delta = abs(
        current_scale_reference_pixels - baseline_scale_reference_pixels
    ) / max(abs(baseline_scale_reference_pixels), 1.0)
    if scale_ratio_delta > BODY_SILHOUETTE_SCALE_MISMATCH_RATIO:
        return 0.0, "stable"

    # PROVISIONAL, same status as the rest of the body pipeline: a
    # captureMode mismatch (mirror vs. assisted vs. timer) between baseline
    # and current is treated as an honesty-gate signal analogous to the
    # scale_reference_pixels mismatch check above. Rationale is the same —
    # switching capture methods between scans can shift framing/depth
    # characteristics independent of any real body change (e.g. a mirror
    # capture's reflection adds real depth a direct assisted/timer shot
    # doesn't have), so a real improved/worsened claim shouldn't be made
    # across a method switch. Only gates when BOTH sides report a known,
    # differing mode — missing/legacy data (pre-dates this field) is left
    # ungated rather than forced to insufficient_signal, since that would
    # silently break every existing body comparison the moment this field
    # shipped.
    normalized_current_mode = (current_capture_mode or "").strip().lower() or None
    normalized_baseline_mode = (baseline_capture_mode or "").strip().lower() or None
    if (
        normalized_current_mode is not None
        and normalized_baseline_mode is not None
        and normalized_current_mode != normalized_baseline_mode
    ):
        return 0.0, "stable"

    if minimum_consistent_scans > 1:
        return 0.0, "insufficient_signal"

    directional_delta = ((current - baseline) / abs(baseline)) * 100.0
    if abs(directional_delta) < honesty_band_pct:
        return 0.0, "stable"

    rounded = round(directional_delta, 1)
    if rounded > 0:
        return rounded, "improved"
    if rounded < 0:
        return rounded, "worsened"
    return 0.0, "stable"


def _body_trend_lock_reason(
    baseline: float,
    current_scale_reference_pixels: float | None,
    baseline_scale_reference_pixels: float | None,
    current_confidence: float | None,
    baseline_confidence: float | None,
    current_capture_quality: str = "normal",
    baseline_capture_quality: str = "normal",
    current_capture_mode: str | None = None,
    baseline_capture_mode: str | None = None,
    current_source_width: int | None = None,
    current_source_height: int | None = None,
    baseline_source_width: int | None = None,
    baseline_source_height: int | None = None,
) -> str | None:
    """Purely-informational companion to _body_trend_delta_and_status.

    Mirrors the SAME honesty-gate checks in the SAME order so the UI can
    explain *why* a body silhouette comparison was forced to "stable",
    without altering any gating logic/thresholds. Returns None whenever the
    gates below did not force the lock (e.g. genuinely insufficient signal,
    or a real small delta inside the honesty band) — those keep their
    existing messaging.
    """
    if abs(baseline) < 1e-9:
        return None

    current_quality = (
        _normalize_capture_quality(current_capture_quality)
        if current_capture_quality is not None
        else "normal"
    )
    baseline_quality = (
        _normalize_capture_quality(baseline_capture_quality)
        if baseline_capture_quality is not None
        else "normal"
    )
    if current_quality == "unknown" or baseline_quality == "unknown":
        return "capture_quality_mismatch"
    if current_quality != "normal" or baseline_quality != "normal":
        return "capture_quality_mismatch"

    if not _source_resolutions_comparable(
        current_source_width,
        current_source_height,
        baseline_source_width,
        baseline_source_height,
    ):
        return "resolution_mismatch"

    if current_confidence is None or baseline_confidence is None:
        return None
    if current_confidence < BODY_SILHOUETTE_MIN_CONFIDENCE or baseline_confidence < BODY_SILHOUETTE_MIN_CONFIDENCE:
        return None

    if (
        current_scale_reference_pixels is None
        or baseline_scale_reference_pixels is None
        or baseline_scale_reference_pixels <= 0.0
    ):
        return None

    scale_ratio_delta = abs(
        current_scale_reference_pixels - baseline_scale_reference_pixels
    ) / max(abs(baseline_scale_reference_pixels), 1.0)
    if scale_ratio_delta > BODY_SILHOUETTE_SCALE_MISMATCH_RATIO:
        return "scale_mismatch"

    normalized_current_mode = (current_capture_mode or "").strip().lower() or None
    normalized_baseline_mode = (baseline_capture_mode or "").strip().lower() or None
    if (
        normalized_current_mode is not None
        and normalized_baseline_mode is not None
        and normalized_current_mode != normalized_baseline_mode
    ):
        return "capture_mode_mismatch"

    return None


def _coalesce_personal_lab_baseline(baseline: Dict[str, Any] | None) -> Dict[str, float]:
    if not baseline:
        return {}

    def _maybe_float(value: Any) -> float | None:
        if value is None:
            return None
        try:
            numeric = float(value)
        except (TypeError, ValueError):
            return None
        if not math.isfinite(numeric):
            return None
        return float(numeric)

    alias_maps = {
        "a_mean": ["a_mean", "mean_a", "a_star_mean", "a_star_mean_labs", "redness_a_mean"],
        "a_p95": ["a_p95", "p95_a", "a_star_p95", "redness_a_p95"],
        "b_mean": ["b_mean", "mean_b", "b_star_mean", "b_star_mean_labs"],
        "b_p95": ["b_p95", "p95_b", "b_star_p95"],
    }
    output: Dict[str, float] = {}
    for canonical, aliases in alias_maps.items():
        for key in aliases:
            value = _maybe_float(baseline.get(key))
            if value is not None:
                output[canonical] = value
                break
    return output


def _compute_redness_from_personal_baseline(
    current_values: Dict[str, Any],
    baseline: Dict[str, float],
) -> float:
    if not baseline:
        return 0.0

    def _pick(*keys: str) -> float | None:
        for key in keys:
            value = safe_float(current_values.get(key))
            if value is not None:
                return float(value)
        return None

    signal = _pick("a_p95", "p95_a", "a_mean", "mean_a")
    reference = _pick_personal_baseline_reference(baseline)
    if signal is None or reference is None:
        return 0.0
    effective_delta = max(
        0.0,
        (signal - reference) - LOCALIZED_REDNESS_FOLLOWUP_DEAD_ZONE_A_UNITS,
    )
    return float(
        np.clip(
            effective_delta * LOCALIZED_REDNESS_FOLLOWUP_MULTIPLIER,
            0.0,
            100.0,
        )
    )


def _pick_personal_baseline_reference(baseline: Dict[str, float]) -> float | None:
    for key in (
        "a_p95",
        "p95_a",
        "a_star_p95",
        "redness_a_p95",
        "a_mean",
        "mean_a",
        "a_star_mean",
        "redness_a_mean",
    ):
        value = safe_float(baseline.get(key))
        if value is not None:
            return float(value)
    return None


def _resolve_personal_lab_ctx(baseline_matrix: Dict[str, Any] | None) -> Dict[str, float]:
    baseline = _coalesce_personal_lab_baseline(baseline_matrix or {})
    return {
        "a_mean": safe_float(baseline.get("a_mean")) if baseline.get("a_mean") is not None else 128.0,
        "b_mean": safe_float(baseline.get("b_mean")) if baseline.get("b_mean") is not None else 128.0,
        "a_p95": safe_float(baseline.get("a_p95")) if baseline.get("a_p95") is not None else 128.0,
        "b_p95": safe_float(baseline.get("b_p95")) if baseline.get("b_p95") is not None else 128.0,
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
    return _coalesce_metric_aliases(baseline)


def _compute_trend_deltas(
    current_matrix: Dict[str, float],
    baseline_matrix: Dict[str, float],
    *,
    current_paths: Dict[str, str] | None = None,
    baseline_paths: Dict[str, str] | None = None,
    current_capture_quality: str | None = None,
    baseline_capture_quality: str | None = None,
    current_source_width: int | None = None,
    current_source_height: int | None = None,
    baseline_source_width: int | None = None,
    baseline_source_height: int | None = None,
    current_formula_versions: Dict[str, int] | None = None,
    baseline_formula_versions: Dict[str, int] | None = None,
    honesty_band_pct: float = HONESTY_STABLE_BAND_PCT,
    current_pose_template: str | None = None,
    baseline_pose_template: str | None = None,
    current_guide_type: str | None = None,
    baseline_guide_type: str | None = None,
) -> Dict[str, float]:
    current_canonical = _coalesce_metric_aliases(current_matrix)
    baseline_canonical = _coalesce_metric_aliases(baseline_matrix)
    deltas: Dict[str, float] = {}

    current_paths_norm = _normalize_metric_extraction_paths(
        current_paths,
        CANONICAL_METRIC_ORDER,
    )
    baseline_paths_norm = _normalize_metric_extraction_paths(
        baseline_paths,
        CANONICAL_METRIC_ORDER,
    )
    current_versions_norm = _normalize_metric_formula_versions(
        current_formula_versions,
        CANONICAL_METRIC_ORDER,
    )
    baseline_versions_norm = _normalize_baseline_metric_formula_versions(
        baseline_formula_versions,
        CANONICAL_METRIC_ORDER,
    )
    current_capture_quality_norm = (
        _normalize_capture_quality(current_capture_quality)
        if current_capture_quality is not None
        else "normal"
    )
    baseline_capture_quality_norm = (
        _normalize_capture_quality(baseline_capture_quality)
        if baseline_capture_quality is not None
        else "normal"
    )

    for key, current_value in current_canonical.items():
        if key not in baseline_canonical:
            continue

        current = safe_float(current_value)
        baseline_value = safe_float(baseline_canonical[key])
        if current is None or baseline_value is None:
            continue

        current_path = current_paths_norm.get(key, "unknown")
        baseline_path = baseline_paths_norm.get(key, "unknown")
        delta_pct, _ = _trend_delta_and_status(
            key,
            current,
            baseline_value,
            current_path,
            baseline_path,
            honesty_band_pct,
            current_capture_quality_norm,
            baseline_capture_quality_norm,
            current_source_width,
            current_source_height,
            baseline_source_width,
            baseline_source_height,
            current_versions_norm.get(key, 1),
            baseline_versions_norm.get(key),
            current_pose_template,
            baseline_pose_template,
            current_guide_type,
            baseline_guide_type,
        )
        deltas[key] = delta_pct
    return deltas


def _compute_trend_statuses(
    current_matrix: Dict[str, float],
    baseline_matrix: Dict[str, float],
    *,
    current_paths: Dict[str, str] | None = None,
    baseline_paths: Dict[str, str] | None = None,
    current_capture_quality: str | None = None,
    baseline_capture_quality: str | None = None,
    current_source_width: int | None = None,
    current_source_height: int | None = None,
    baseline_source_width: int | None = None,
    baseline_source_height: int | None = None,
    current_formula_versions: Dict[str, int] | None = None,
    baseline_formula_versions: Dict[str, int] | None = None,
    honesty_band_pct: float = HONESTY_STABLE_BAND_PCT,
    current_pose_template: str | None = None,
    baseline_pose_template: str | None = None,
    current_guide_type: str | None = None,
    baseline_guide_type: str | None = None,
) -> Dict[str, str]:
    current_canonical = _coalesce_metric_aliases(current_matrix)
    baseline_canonical = _coalesce_metric_aliases(baseline_matrix)

    current_paths_norm = _normalize_metric_extraction_paths(
        current_paths,
        CANONICAL_METRIC_ORDER,
    )
    baseline_paths_norm = _normalize_metric_extraction_paths(
        baseline_paths,
        CANONICAL_METRIC_ORDER,
    )
    current_versions_norm = _normalize_metric_formula_versions(
        current_formula_versions,
        CANONICAL_METRIC_ORDER,
    )
    baseline_versions_norm = _normalize_baseline_metric_formula_versions(
        baseline_formula_versions,
        CANONICAL_METRIC_ORDER,
    )
    current_capture_quality_norm = (
        _normalize_capture_quality(current_capture_quality)
        if current_capture_quality is not None
        else "normal"
    )
    baseline_capture_quality_norm = (
        _normalize_capture_quality(baseline_capture_quality)
        if baseline_capture_quality is not None
        else "normal"
    )

    out: Dict[str, str] = {}
    for key, current_value in current_canonical.items():
        if key not in baseline_canonical:
            continue
        current = safe_float(current_value)
        baseline_value = safe_float(baseline_canonical[key])
        if current is None or baseline_value is None:
            continue

        _, status = _trend_delta_and_status(
            key,
            current,
            baseline_value,
            current_paths_norm.get(key, "unknown"),
            baseline_paths_norm.get(key, "unknown"),
            honesty_band_pct,
            current_capture_quality_norm,
            baseline_capture_quality_norm,
            current_source_width,
            current_source_height,
            baseline_source_width,
            baseline_source_height,
            current_versions_norm.get(key, 1),
            baseline_versions_norm.get(key),
            current_pose_template,
            baseline_pose_template,
            current_guide_type,
            baseline_guide_type,
        )
        out[key] = status
    return out


def _compute_trend_lock_reasons(
    current_matrix: Dict[str, float],
    baseline_matrix: Dict[str, float],
    *,
    current_paths: Dict[str, str] | None = None,
    baseline_paths: Dict[str, str] | None = None,
    current_capture_quality: str | None = None,
    baseline_capture_quality: str | None = None,
    current_source_width: int | None = None,
    current_source_height: int | None = None,
    baseline_source_width: int | None = None,
    baseline_source_height: int | None = None,
    current_formula_versions: Dict[str, int] | None = None,
    baseline_formula_versions: Dict[str, int] | None = None,
    current_pose_template: str | None = None,
    baseline_pose_template: str | None = None,
    current_guide_type: str | None = None,
    baseline_guide_type: str | None = None,
) -> Dict[str, str | None]:
    """Per-metric companion to _compute_trend_statuses: explains WHY a metric
    that came back "stable" was locked there, when it was a mismatch gate
    rather than a genuine small delta. Purely additive/informational — does
    not affect trend_status or trend_deltas in any way.
    """
    current_canonical = _coalesce_metric_aliases(current_matrix)
    baseline_canonical = _coalesce_metric_aliases(baseline_matrix)

    current_paths_norm = _normalize_metric_extraction_paths(
        current_paths,
        CANONICAL_METRIC_ORDER,
    )
    baseline_paths_norm = _normalize_metric_extraction_paths(
        baseline_paths,
        CANONICAL_METRIC_ORDER,
    )
    current_versions_norm = _normalize_metric_formula_versions(
        current_formula_versions,
        CANONICAL_METRIC_ORDER,
    )
    baseline_versions_norm = _normalize_baseline_metric_formula_versions(
        baseline_formula_versions,
        CANONICAL_METRIC_ORDER,
    )
    current_capture_quality_norm = (
        _normalize_capture_quality(current_capture_quality)
        if current_capture_quality is not None
        else "normal"
    )
    baseline_capture_quality_norm = (
        _normalize_capture_quality(baseline_capture_quality)
        if baseline_capture_quality is not None
        else "normal"
    )

    out: Dict[str, str | None] = {}
    for key, current_value in current_canonical.items():
        if key not in baseline_canonical:
            continue
        current = safe_float(current_value)
        baseline_value = safe_float(baseline_canonical[key])
        if current is None or baseline_value is None:
            continue

        out[key] = _trend_lock_reason(
            current_paths_norm.get(key, "unknown"),
            baseline_paths_norm.get(key, "unknown"),
            current_capture_quality_norm,
            baseline_capture_quality_norm,
            current_source_width,
            current_source_height,
            baseline_source_width,
            baseline_source_height,
            current_versions_norm.get(key, 1),
            baseline_versions_norm.get(key),
            current_pose_template,
            baseline_pose_template,
            current_guide_type,
            baseline_guide_type,
        )
    return out


def _compute_body_silhouette_trend(
    current_result: Dict[str, Any],
    baseline_result: Dict[str, Any] | None,
    *,
    current_capture_quality: str | None = None,
    baseline_capture_quality: str | None = None,
    current_consistent_scan_count: int | None = None,
    baseline_consistent_scan_count: int | None = None,
    current_capture_mode: str | None = None,
    baseline_capture_mode: str | None = None,
    current_source_width: int | None = None,
    current_source_height: int | None = None,
    baseline_source_width: int | None = None,
    baseline_source_height: int | None = None,
) -> tuple[Dict[str, float], Dict[str, str], float, int, Dict[str, str | None]]:
    if baseline_result is None:
        return (
            {"normalized_area_index": 0.0},
            {"normalized_area_index": "insufficient_signal"},
            BODY_SILHOUETTE_HONESTY_BAND_PCT,
            BODY_SILHOUETTE_REQUIRED_CONSISTENT_SCANS,
            {"normalized_area_index": None},
        )

    current_value = safe_float(current_result.get("normalized_area_index"))
    baseline_value = safe_float(baseline_result.get("normalized_area_index"))
    current_scale = safe_float(current_result.get("scale_reference_pixels"))
    baseline_scale = safe_float(baseline_result.get("scale_reference_pixels"))
    current_confidence = safe_float(current_result.get("confidence"))
    baseline_confidence = safe_float(baseline_result.get("confidence"))

    # This comparison is intentionally conservative. A single baseline/current pair is not enough to
    # claim real body change because framing and pose alone can produce large area swings. Require at
    # least two consistent captures before allowing improved/worsened claims.
    effective_current_count = max(
        int(current_consistent_scan_count or current_result.get("consistent_scan_count") or 1),
        1,
    )
    required_scans = BODY_SILHOUETTE_REQUIRED_CONSISTENT_SCANS

    if current_value is None or baseline_value is None:
        return (
            {"normalized_area_index": 0.0},
            {"normalized_area_index": "insufficient_signal"},
            BODY_SILHOUETTE_HONESTY_BAND_PCT,
            required_scans,
            {"normalized_area_index": None},
        )

    delta_pct, status = _body_trend_delta_and_status(
        "normalized_area_index",
        current_value,
        baseline_value,
        current_scale,
        baseline_scale,
        current_confidence,
        baseline_confidence,
        current_capture_quality or "normal",
        baseline_capture_quality or "normal",
        minimum_consistent_scans=(
            required_scans
            if effective_current_count < required_scans
            else 1
        ),
        current_capture_mode=current_capture_mode,
        baseline_capture_mode=baseline_capture_mode,
        current_source_width=current_source_width,
        current_source_height=current_source_height,
        baseline_source_width=baseline_source_width,
        baseline_source_height=baseline_source_height,
    )
    lock_reason = _body_trend_lock_reason(
        baseline_value,
        current_scale,
        baseline_scale,
        current_confidence,
        baseline_confidence,
        current_capture_quality or "normal",
        baseline_capture_quality or "normal",
        current_capture_mode=current_capture_mode,
        baseline_capture_mode=baseline_capture_mode,
        current_source_width=current_source_width,
        current_source_height=current_source_height,
        baseline_source_width=baseline_source_width,
        baseline_source_height=baseline_source_height,
    )
    return {
        "normalized_area_index": round(float(delta_pct), 1),
    }, {
        "normalized_area_index": status,
    }, BODY_SILHOUETTE_HONESTY_BAND_PCT, required_scans, {
        "normalized_area_index": lock_reason,
    }


def _body_consistent_scan_count(
    current_result: Dict[str, Any],
    baseline_result: Dict[str, Any] | None,
    *,
    candidate_count: int,
    current_capture_quality: str | None,
    baseline_capture_quality: str | None,
    current_capture_mode: str | None,
    baseline_capture_mode: str | None,
    current_source_width: int | None = None,
    current_source_height: int | None = None,
    baseline_source_width: int | None = None,
    baseline_source_height: int | None = None,
) -> int:
    """Return the confirmed consecutive consistent-scan count for one procedure."""
    if baseline_result is None:
        return 1

    current_quality = _normalize_capture_quality(current_capture_quality)
    baseline_quality = _normalize_capture_quality(baseline_capture_quality)
    if current_quality != "normal" or baseline_quality != "normal":
        return 1
    if not _source_resolutions_comparable(
        current_source_width,
        current_source_height,
        baseline_source_width,
        baseline_source_height,
    ):
        return 1

    current_scale = safe_float(current_result.get("scale_reference_pixels"))
    baseline_scale = safe_float(baseline_result.get("scale_reference_pixels"))
    if current_scale is None or baseline_scale is None or baseline_scale <= 0.0:
        return 1
    if abs(current_scale - baseline_scale) / baseline_scale > BODY_SILHOUETTE_SCALE_MISMATCH_RATIO:
        return 1

    current_mode = (current_capture_mode or "").strip().lower() or None
    baseline_mode = (baseline_capture_mode or "").strip().lower() or None
    if current_mode is None or baseline_mode is None or current_mode != baseline_mode:
        return 1

    current_confidence = safe_float(current_result.get("confidence"))
    baseline_confidence = safe_float(baseline_result.get("confidence"))
    if (
        current_confidence is None
        or baseline_confidence is None
        or current_confidence < BODY_SILHOUETTE_MIN_CONFIDENCE
        or baseline_confidence < BODY_SILHOUETTE_MIN_CONFIDENCE
    ):
        return 1
    return max(candidate_count, 1)


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


def _compute_zone_analysis(
    face_bgr: np.ndarray,
    skin_mask: np.ndarray,
    regions: Dict[str, np.ndarray],
    *,
    min_pixels: int = 1200,
) -> Dict[str, Any]:
    """Return valid zone scores using the existing canonical formula pieces.

    This is deliberately additive: the whole-face pipeline remains the source
    of canonical metrics and trend decisions. Zone scores are emitted only
    when their ROI has enough pixels for the same signal family to be useful.
    """
    h, w = face_bgr.shape[:2]
    if h <= 0 or w <= 0:
        return {}

    lab = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2LAB)
    gray = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2GRAY)
    a_channel = lab[:, :, 1].astype(np.float32)
    l_channel = lab[:, :, 0].astype(np.float32)
    lap_abs = np.abs(cv2.Laplacian(gray, cv2.CV_32F, ksize=3))
    skin = _as_binary_mask(skin_mask, (h, w))

    raw_zones = {
        "forehead": regions.get("forehead"),
        "left_cheek": regions.get("right_cheek"),
        "right_cheek": regions.get("left_cheek"),
        "nose": _nose_region_mask((h, w), np.asarray([]), skin),
    }
    # The nose mask needs landmarks; callers pass it through regions when
    # available because _nose_region_mask has no meaningful empty fallback.
    if regions.get("nose") is not None:
        raw_zones["nose"] = regions["nose"]

    def normalized_crop(mask: np.ndarray) -> Dict[str, float] | None:
        ys, xs = np.where(mask > 0)
        if len(xs) == 0 or len(ys) == 0:
            return None
        x0, x1 = int(xs.min()), int(xs.max())
        y0, y1 = int(ys.min()), int(ys.max())
        side = max(x1 - x0 + 1, y1 - y0 + 1)
        pad = max(4, int(round(side * 0.12)))
        side = min(max(side + (pad * 2), 1), min(w, h))
        cx = (x0 + x1) / 2.0
        cy = (y0 + y1) / 2.0
        left = max(0.0, min(float(w - side), cx - side / 2.0)) / w
        top = max(0.0, min(float(h - side), cy - side / 2.0)) / h
        return {
            "left": round(left, 6),
            "top": round(top, 6),
            "size": round(min(side / w, side / h), 6),
            "coordinate_space": "normalized_face",
        }

    def score_texture(values: np.ndarray) -> float | None:
        if values.size < min_pixels:
            return None
        local_mean = cv2.GaussianBlur(gray.astype(np.float32), (0, 0), 1.4)
        local_mean_sq = cv2.GaussianBlur((gray.astype(np.float32) ** 2), (0, 0), 1.4)
        local_var = np.clip(local_mean_sq - (local_mean ** 2), 0.0, None)[values > 0]
        pixels = gray[values > 0].astype(np.float32)
        lap_values = lap_abs[values > 0]
        var_p80 = float(np.percentile(local_var, 80))
        lap_p80 = float(np.percentile(lap_values, 80))
        spread = float(np.std(pixels))
        energy = (0.65 * math.sqrt(max(var_p80, 0.0))) + (0.35 * lap_p80)
        n_energy = float(np.clip((energy - 8.0) / 22.0, 0.0, 1.0))
        n_var = float(np.clip((math.sqrt(max(var_p80, 0.0)) - 6.0) / 14.0, 0.0, 1.0))
        n_lap = float(np.clip((lap_p80 - 14.0) / 32.0, 0.0, 1.0))
        n_spread = float(np.clip((spread - 18.0) / 32.0, 0.0, 1.0))
        roughness = (0.45 * n_energy) + (0.20 * n_var) + (0.20 * n_lap) + (0.15 * n_spread)
        return round(float(np.clip(100.0 * (1.0 - math.pow(roughness, 1.10)), 0.0, 100.0)), 1)

    output: Dict[str, Any] = {}
    for zone_name, raw_mask in raw_zones.items():
        if raw_mask is None:
            continue
        mask = cv2.bitwise_and(_as_binary_mask(raw_mask, (h, w)), skin)
        pixel_count = int(cv2.countNonZero(mask))
        crop = normalized_crop(mask)
        if pixel_count < min_pixels or crop is None:
            continue
        pixels = mask > 0
        values = a_channel[pixels]
        spread = float(np.percentile(values, 95) - np.percentile(values, 10))
        redness = compute_localized_redness_and_rosacea(
            spread,
            0.0,
            float(np.mean(values >= np.percentile(values, 50) + 5.0) * 100.0),
        )["localized_redness"]
        zone: Dict[str, Any] = {
            "crop": crop,
            "pixel_count": pixel_count,
            "metrics": {"localized_redness": round(float(redness), 1)},
        }
        if zone_name in {"left_cheek", "right_cheek"}:
            cheek_l = l_channel[pixels]
            cheek_a = a_channel[pixels]
            cheek_b = lab[:, :, 2].astype(np.float32)[pixels]
            mean_a = float(np.mean(cheek_a))
            mean_b = float(np.mean(cheek_b))
            pigment_signal = float(
                np.percentile(np.sqrt((cheek_a - mean_a) ** 2 + (cheek_b - mean_b) ** 2), 85)
                + (PIGMENT_LOAD_L_CONTRAST_WEIGHT * np.std(cheek_l))
            )
            zone["metrics"]["pigment_load"] = round(float(compute_pigment_load(pigment_signal)), 1)
        if zone_name in {"forehead", "left_cheek", "right_cheek"}:
            texture = score_texture(mask)
            if texture is not None:
                zone["metrics"]["texture_smoothness"] = texture
        output[zone_name] = zone
    return output


def _pre_white_balance_cheek_percentiles_a(
    pre_white_balance_bgr: np.ndarray | None,
    points: np.ndarray,
    cheek_mask: np.ndarray | None,
) -> tuple[float | None, float | None]:
    """Diagnostic-only. Replays analyze_skin_patch's align/crop and
    normalize_lighting_and_shadows, plus the zone redness formula's a* blur,
    on the image as it was before white balance, then reads p10/p95 a* on the
    SAME boolean cheek mask the formula used. Never feeds a score."""
    if pre_white_balance_bgr is None or cheek_mask is None or not np.any(cheek_mask):
        return None, None
    try:
        aligned, _ = _align_and_crop_face(pre_white_balance_bgr, points)
        pre_norm = normalize_lighting_and_shadows(aligned)
        if pre_norm.shape[:2] != cheek_mask.shape[:2]:
            return None, None
        a_blur = cv2.GaussianBlur(
            cv2.cvtColor(pre_norm, cv2.COLOR_BGR2LAB)[:, :, 1].astype(np.float32),
            (0, 0),
            sigmaX=2.0,
        )
        values = a_blur[cheek_mask]
        return (
            float(np.percentile(values, LOCALIZED_REDNESS_SELF_BASELINE_PERCENTILE)),
            float(np.percentile(values, 95)),
        )
    except Exception as exc:
        logger.info("Pre-white-balance cheek percentile diagnostic skipped: %s", exc)
        return None, None


def _redness_color_diagnostics(
    redness_diagnostics: Dict[str, Any],
    *,
    branch: str,
    p10_a_before_wb: float | None,
    p95_a_before_wb: float | None,
) -> Dict[str, Any]:
    """image_quality fields describing which localized_redness branch ran and
    the cheek a*/b* it saw, all signed (neutral = 0)."""
    zone_branch_used = branch in {"within_cheek_spread", "baseline_p95_anchor"}

    def zone_value(key: str) -> float | None:
        if not zone_branch_used:
            return None
        return _signed_lab_value(safe_float(redness_diagnostics.get(key)))

    return {
        "redness_branch": branch,
        "redness_cheek_side": redness_diagnostics.get("cheek_side") if zone_branch_used else None,
        "redness_both_cheeks_in_dead_zone": (
            bool(redness_diagnostics.get("both_cheeks_in_dead_zone"))
            if zone_branch_used
            else None
        ),
        "redness_cheek_roi_pixels": (
            int(redness_diagnostics.get("cheek_roi_pixels", 0)) if zone_branch_used else None
        ),
        "redness_cheek_mean_a_after_wb": zone_value("mean_a_after_wb"),
        "redness_cheek_mean_b_after_wb": zone_value("mean_b_after_wb"),
        "redness_cheek_p10_a_after_wb": zone_value("p10_a_after_wb"),
        "redness_cheek_p95_a_after_wb": zone_value("p95_a_after_wb"),
        "redness_cheek_p10_a_before_wb": (
            _signed_lab_value(p10_a_before_wb) if zone_branch_used else None
        ),
        "redness_cheek_p95_a_before_wb": (
            _signed_lab_value(p95_a_before_wb) if zone_branch_used else None
        ),
        "redness_baseline_cheek_p95_a": zone_value("baseline_p95_a"),
    }


def _attach_localized_redness_baseline_p95(
    metric_matrix: Dict[str, Any],
    redness_diagnostics: Dict[str, Any],
) -> None:
    u_zone_p95 = safe_float(redness_diagnostics.get("u_zone_p95_a_after_wb"))
    if u_zone_p95 is not None:
        metric_matrix["a_p95"] = u_zone_p95


def _set_laplacian_fallback_texture_metric(
    metric_matrix: Dict[str, Any],
    metric_confidence: Dict[str, str],
    metric_status: Dict[str, str],
    fallback_reason: Dict[str, str],
    forced_metric_values: Dict[str, float],
    forced_metric_paths: Dict[str, str],
    *,
    fallback_roi_pixels: int,
    fallback_value: float | None,
) -> bool:
    metric_key = "texture_smoothness"
    if (
        fallback_roi_pixels < 500
        or fallback_value is None
        or not math.isfinite(fallback_value)
    ):
        metric_matrix.pop(metric_key, None)
        metric_confidence.pop(metric_key, None)
        forced_metric_values.pop(metric_key, None)
        forced_metric_paths.pop(metric_key, None)
        metric_status[metric_key] = "unavailable"
        fallback_reason[metric_key] = (
            "fallback_roi_too_small"
            if fallback_roi_pixels < 500
            else "non_usable_value"
        )
        return False

    value = round(float(np.clip(fallback_value, 0.0, 100.0)), 1)
    metric_matrix[metric_key] = value
    forced_metric_values[metric_key] = value
    forced_metric_paths[metric_key] = "laplacian_fallback"
    metric_status[metric_key] = "computed"
    fallback_reason[metric_key] = "laplacian_fallback"
    return True


def analyze_skin_patch(
    bgr_image: np.ndarray,
    baseline_matrix: Dict[str, float] | None = None,
    baseline_extraction_paths: Dict[str, str] | None = None,
    baseline_formula_versions: Dict[str, int] | None = None,
    capture_quality: str | None = None,
    baseline_capture_quality: str | None = None,
    quality_profile: Dict[str, Any] | None = None,
    baseline_image_bgr: np.ndarray | None = None,
    source_image_width: int | None = None,
    source_image_height: int | None = None,
    baseline_source_image_width: int | None = None,
    baseline_source_image_height: int | None = None,
    pose_template: str | None = None,
    baseline_pose_template: str | None = None,
    guide_type: str | None = None,
    baseline_guide_type: str | None = None,
    pre_white_balance_bgr: np.ndarray | None = None,
) -> Dict[str, Any]:
    """Core math analytics processor combined with 0-100 linear calibration scoring.

    [pre_white_balance_bgr] is diagnostic-only (see
    _assess_and_normalize_image_with_pre_white_balance): it is only read to
    log the redness cheek's p10/p95 a* before white balance, never scored."""
    ensure_pipeline_ready()
    if not hasattr(math, "exp"):
        raise RuntimeError("Python math.exp is unavailable for metric calibration.")

    request_roi_cache = _RequestRoiCache()

    def _clamp_score(value: float) -> float:
        return float(max(0.0, min(100.0, value)))

    logger.info(
        "analyze_skin_patch: input matrix shape=%s dtype=%s",
        tuple(bgr_image.shape),
        bgr_image.dtype,
    )

    if ENABLE_WHITE_BALANCE_CALIBRATION:
        calibrated_image, calibration = apply_white_balance_calibration(bgr_image)
    else:
        calibrated_image = bgr_image
        calibration = {
            "reference_found": False,
            "reason": "disabled_for_capture_pipeline",
        }

    rgb = cv2.cvtColor(calibrated_image, cv2.COLOR_BGR2RGB)
    primary_landmarks, primary_landmark_count, primary_source = _extract_primary_landmarks(rgb)

    if primary_landmarks is None:
        raise RuntimeError(_media_pipe_no_face_message(calibrated_image))

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
    personal_lab_baseline = _resolve_personal_lab_ctx(baseline_matrix)
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

    redness_diagnostics: Dict[str, Any] = {}
    try:
        zone_metrics = _compute_zone_based_metrics(
            norm,
            mask,
            regions,
            norm_points,
            baseline_matrix=baseline_matrix,
            roi_cache=request_roi_cache,
            redness_diagnostics=redness_diagnostics,
        )
    except Exception as exc:
        logger.warning(
            "Zone-based feature extraction failed; using fallbacks. Details: %s",
            exc,
        )
        # None, not 0.0: extraction failed outright, so these were never
        # measured. A 0.0 here would be indistinguishable downstream from a
        # genuine "no redness/rosacea detected" reading and get emitted as
        # if it were real data.
        zone_metrics = {
            "localized_redness": None,
            "rosacea_severity": None,
            "under_eye_texture_density": None,
            "under_eye_dark_circle_density": None,
        }
        redness_diagnostics = {}

    lab = cv2.cvtColor(norm, cv2.COLOR_BGR2LAB)
    gray = cv2.cvtColor(norm, cv2.COLOR_BGR2GRAY)

    a_channel = lab[:, :, 1].astype(np.float32)
    p95_a = _percentile(a_channel, cv2.bitwise_or(regions["left_cheek"], regions["right_cheek"]), 95)
    baseline_a_ref = _resolve_personal_lab_ctx(baseline_matrix or {}).get("a_mean", 128.0)
    redness_logistic = 1.0 / (1.0 + math.exp(-0.35 * (p95_a - (baseline_a_ref + 8.0))))
    # LEGACY, NOT a canonical producer: calibrated_redness_score is a separate
    # formula (p95_a logistic) that bypasses all ROI/confidence gating used by
    # the real localized_redness pipeline. Shipped only so old Flutter scans
    # that stored this key can still resolve a baseline alias; never treat it
    # as an alternate source for localized_redness.
    calibrated_redness_score = (1.0 - redness_logistic) * 100.0
    if p95_a <= baseline_a_ref + 4.5:
        calibrated_redness_score = max(96.0, 100.0 - (p95_a - baseline_a_ref + 2.0))
    calibrated_redness_score = _clamp_score(calibrated_redness_score)

    lap = cv2.Laplacian(gray, cv2.CV_64F, ksize=3)
    lap_abs = np.abs(lap)
    raw_variance = float(np.var(lap))
    texture_logistic = 1.0 / (1.0 + math.exp(-0.025 * (raw_variance - 65.0)))
    # LEGACY, NOT a canonical producer: same caveat as calibrated_redness_score
    # above, for texture_smoothness. Baseline-alias-only for old scans.
    calibrated_smoothness_score = (1.0 - texture_logistic) * 100.0
    if raw_variance <= 25.0:
        calibrated_smoothness_score = max(94.0, 100.0 - (raw_variance * 0.15))
    calibrated_smoothness_score = _clamp_score(calibrated_smoothness_score)

    yolo_kept, yolo_max_conf = _run_yolo_detection_stats(norm)
    logger.info("YOLO lesion detector: boxes=%d max_conf=%.4f", yolo_kept, yolo_max_conf)
    # LEGACY, NOT a canonical producer: acne_activity_score is a bare YOLO-count
    # linear formula, unrelated to the real breakout_activity pipeline in
    # _compute_canonical_patch_metrics. Top-level-only field, not consumed by
    # any current candidate_values entry.
    acne_activity_score = float(np.clip(100.0 - (yolo_kept * 10.0), 0.0, 100.0))
    fingerprint = hashlib.sha256(norm.tobytes()).hexdigest()
    additional_mask_diagnostics: Dict[str, Any] = {}
    try:
        additional_metrics = _compute_additional_opencv_metrics(
            norm,
            mask,
            regions,
            norm_points,
            roi_cache=request_roi_cache,
            mask_diagnostics=additional_mask_diagnostics,
        )
    except Exception as exc:
        logger.warning(
            "Additional feature extraction failed; using fallback values. Details: %s",
            exc,
        )
        # None, not 0.0: see the zone_metrics exception handler above for why
        # a failure placeholder must never look like a measured zero.
        additional_metrics = {
            "sebum_excess_oil_gloss": None,
            "diffuse_flushing_erythema": None,
            "skin_tone_radiance_evenness": None,
        }

    try:
        structural_metrics = _compute_structural_opencv_metrics(
            norm,
            mask,
            regions,
            norm_points,
            roi_cache=request_roi_cache,
        )
    except Exception as exc:
        logger.warning(
            "Structural feature extraction failed; using fallback values. Details: %s",
            exc,
        )
        # None, not 0.0: see the zone_metrics exception handler above for why
        # a failure placeholder must never look like a measured zero.
        structural_metrics = {
            "glabellar_wrinkle_depth": None,
            "pore_contraction_index": None,
            "structural_firmness_elasticity": None,
        }

    canonical_metric_matrix, metric_confidence, raw_components = _compute_canonical_patch_metrics(
        norm,
        mask,
        regions,
        norm_points,
        yolo_kept=yolo_kept,
        yolo_max_conf=yolo_max_conf,
        baseline_matrix=baseline_matrix,
        roi_cache=request_roi_cache,
    )
    zone_regions = dict(regions)
    zone_regions["nose"] = _nose_region_mask(
        norm.shape[:2],
        norm_points,
        mask,
        apply_skin_mask=False,
    )
    zone_analysis = _compute_zone_analysis(norm, mask, zone_regions)
    zone_redness = safe_float(zone_metrics.get("localized_redness"))
    if zone_redness is not None and math.isfinite(zone_redness):
        canonical_metric_matrix["localized_redness"] = round(
            float(np.clip(zone_redness, 0.0, 100.0)),
            1,
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

    canonical_metric_order = list(CANONICAL_METRIC_ORDER)

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
        if _is_missing_metric_value(numeric):
            return "low"
        if pixel_count >= high_pixels:
            return "high"
        if pixel_count >= medium_pixels:
            return "medium"
        return "low"

    glabella_pixels = int(cv2.countNonZero(_glabella_region_mask(norm.shape[:2], norm_points, mask)))
    glabella_pitch = float(_compute_pose_pitch_yaw_from_landmarks(norm_points)[0])
    left_under_eye = _under_eye_region_mask(norm.shape[:2], norm_points, mask, side="left")
    right_under_eye = _under_eye_region_mask(norm.shape[:2], norm_points, mask, side="right")
    under_eye_pixels = int(cv2.countNonZero(cv2.bitwise_or(left_under_eye, right_under_eye)))
    # A zero reading here is ambiguous (genuinely flawless vs. detector floor),
    # so it is passed through as-is rather than substituted with a synthetic
    # non-zero value; the emission loop below marks adequate-ROI zeros as an
    # explicit "insufficient_signal" status instead of fabricating a score.
    glabellar_conf_value = structural_metrics.get("glabellar_wrinkle_depth")
    under_eye_texture_conf_value = zone_metrics.get("under_eye_texture_density")
    under_eye_dark_conf_value = zone_metrics.get("under_eye_dark_circle_density")
    logger.info(
        "SMALL_ROI_PIXELS glabella=%d under_eye=%d",
        glabella_pixels,
        under_eye_pixels,
    )
    full_face_pixels = int(
        raw_components.get("full_face_skin_pixels", cv2.countNonZero(mask))
    )
    structural_pore_roi = cv2.bitwise_and(
        cv2.bitwise_or(
            cv2.bitwise_or(
                regions.get("left_cheek", np.zeros(norm.shape[:2], dtype=np.uint8)),
                regions.get("right_cheek", np.zeros(norm.shape[:2], dtype=np.uint8)),
            ),
            _nose_region_mask(norm.shape[:2], norm_points, mask),
        ),
        mask,
    )
    pore_contraction_roi_pixels = int(cv2.countNonZero(structural_pore_roi))
    raw_components["pore_contraction_roi_pixels"] = float(
        pore_contraction_roi_pixels
    )

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
            glabellar_conf_value,
            glabella_pixels,
            high_pixels=220,
            medium_pixels=110,
        ),
        "under_eye_texture_density": _conf_from_pixels_and_value(
            under_eye_texture_conf_value,
            under_eye_pixels,
            high_pixels=70,
            medium_pixels=24,
        ),
        "under_eye_dark_circle_density": _conf_from_pixels_and_value(
            under_eye_dark_conf_value,
            under_eye_pixels,
            high_pixels=70,
            medium_pixels=24,
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
            pore_contraction_roi_pixels,
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
    redness_force_write = False
    redness_forced_value: float | None = None
    redness_path = "skipped"
    metric_status: Dict[str, str] = {}
    fallback_reason: Dict[str, str] = {}
    forced_metric_values: Dict[str, float] = {}
    forced_metric_paths: Dict[str, str] = {}
    texture_current = safe_float(canonical_metric_matrix.get("texture_smoothness"))
    logger.info(
        "FORCE_SECTION_REACHED smooth=%s tex_roi=%s cheek=%s",
        texture_current,
        max(
            int(raw_components.get("texture_roi_pixels", 0.0)),
            int(raw_components.get("fallback_texture_roi_pixels", 0.0)),
            roi_after_fallback_pixels,
        ),
        int(raw_components.get("primary_cheek_roi_pixels", 0.0)),
    )

    # Build large fallback ROIs once so forced core metrics can be emitted even
    # when cheek/texture primary masks are too small in live capture.
    mask_binary = _as_binary_mask(mask, norm.shape[:2])
    # Clipped to the face oval at construction so neither downstream consumer
    # (forced texture_smoothness below, forced localized_redness further
    # down) can ever compute a score from the raw, un-clipped landmark
    # bounding box -- see _landmark_bbox_mask's docstring-less note above:
    # its rectangle corners fall outside the face oval and can include
    # hair/ears/background.
    bbox_mask = (
        cv2.bitwise_and(
            _landmark_bbox_mask(norm.shape[:2], norm_points),
            _face_oval_mask(norm.shape[:2], norm_points),
        )
        if norm_points.size > 0
        else np.zeros(norm.shape[:2], dtype=np.uint8)
    )
    _, fallback_skin_mask = request_roi_cache.get_face_skin_mask(
        norm.shape[:2], norm_points, mask_binary
    )
    fallback_skin_mask = _as_binary_mask(fallback_skin_mask, norm.shape[:2])
    fallback_skin_pixels = int(cv2.countNonZero(fallback_skin_mask))
    bbox_pixels = int(cv2.countNonZero(bbox_mask))

    large_fallback_roi = fallback_skin_mask if fallback_skin_pixels >= bbox_pixels else bbox_mask
    large_fallback_path = "large_roi_fallback" if fallback_skin_pixels >= bbox_pixels else "approximate_face_bbox"
    large_fallback_pixels = int(cv2.countNonZero(large_fallback_roi))

    # Target a broad face-support ROI (>=50k when available) to stabilize forced texture/redness.
    if max(fallback_skin_pixels, bbox_pixels) >= 50000:
        large_fallback_roi = fallback_skin_mask if fallback_skin_pixels >= 50000 else bbox_mask
        large_fallback_path = "large_roi_fallback" if fallback_skin_pixels >= 50000 else "approximate_face_bbox"
        large_fallback_pixels = int(cv2.countNonZero(large_fallback_roi))

    fallback_smoothness = None
    if large_fallback_pixels >= 500:
        local_mean = cv2.GaussianBlur(gray.astype(np.float32), (0, 0), 1.4)
        local_mean_sq = cv2.GaussianBlur((gray.astype(np.float32) ** 2), (0, 0), 1.4)
        local_var_map = np.clip(local_mean_sq - (local_mean ** 2), 0.0, None)
        local_var_vals = local_var_map[large_fallback_roi > 0]
        lap_vals = lap_abs[large_fallback_roi > 0]
        texture_vals = gray[large_fallback_roi > 0].astype(np.float32)

        var_p80 = float(np.percentile(local_var_vals, 80)) if local_var_vals.size > 0 else 0.0
        lap_p80 = float(np.percentile(lap_vals, 80)) if lap_vals.size > 0 else 0.0
        texture_energy = (0.65 * np.sqrt(max(var_p80, 0.0))) + (0.35 * lap_p80)
        texture_spread = float(np.std(texture_vals)) if texture_vals.size > 0 else 0.0

        roughness_terms = [
            float(np.clip(math.sqrt(max(var_p80, 0.0)) / 45.0, 0.0, 1.0)),
            float(np.clip(max(lap_p80, 0.0) / 180.0, 0.0, 1.0)),
            float(np.clip(max(texture_energy, 0.0) / 95.0, 0.0, 1.0)),
            float(np.clip(max(texture_spread, 0.0) / 70.0, 0.0, 1.0)),
        ]
        roughness = sum(roughness_terms) / len(roughness_terms)
        smoothness = float(np.clip(95.0 - (90.0 * roughness), 0.0, 100.0))

        fallback_smoothness = smoothness

    texture_force_write = _set_laplacian_fallback_texture_metric(
        canonical_metric_matrix,
        metric_confidence,
        metric_status,
        fallback_reason,
        forced_metric_values,
        forced_metric_paths,
        fallback_roi_pixels=large_fallback_pixels,
        fallback_value=fallback_smoothness,
    )
    if texture_force_write:
        metric_confidence["texture_smoothness"] = _merge_confidence(
            metric_confidence.get("texture_smoothness", "low"),
            "medium",
        )
        logger.info(
            "TEXTURE_FALLBACK_EMIT value=%s path=laplacian_fallback roi_pixels=%d stats={var_p80=%s lap_p80=%s energy=%s spread=%s target50k=%s fallback_path=%s}",
            forced_metric_values["texture_smoothness"],
            large_fallback_pixels,
            round(var_p80, 4),
            round(lap_p80, 4),
            round(float(texture_energy), 4),
            round(float(texture_spread), 4),
            large_fallback_pixels >= 50000,
            large_fallback_path,
        )

    redness_current = safe_float(canonical_metric_matrix.get("localized_redness"))
    redness_unset = redness_current is None or not math.isfinite(redness_current)
    redness_roi = np.zeros(norm.shape[:2], dtype=np.uint8)
    redness_path = "skipped"
    cheek_primary_usable = bool(raw_components.get("cheek_primary_usable", 0.0) > 0.5)
    cheek_expand_no_skin_used = bool(raw_components.get("cheek_expand_no_skin_used", 0.0) > 0.5)
    if cheek_primary_usable:
        left_cheek = regions.get("left_cheek", np.zeros(norm.shape[:2], dtype=np.uint8))
        right_cheek = regions.get("right_cheek", np.zeros(norm.shape[:2], dtype=np.uint8))
        redness_roi = cv2.bitwise_or(left_cheek, right_cheek)
        redness_path = "cheek_primary_no_skin_mask" if cheek_expand_no_skin_used else "cheek_primary"
    elif large_fallback_pixels >= 500:
        redness_roi = large_fallback_roi
        redness_path = "full_face_fallback"

    # The p95 zone value is canonical. This mean/p90 calculation is only an
    # availability fallback when zone extraction produced no finite value.
    redness_roi_pixels = int(cv2.countNonZero(redness_roi))
    if redness_unset and redness_roi_pixels >= 500:
        redness_values = a_channel[redness_roi > 0]
        if redness_values.size > 0:
            mean_a = float(np.mean(redness_values))
            p90_a = float(np.percentile(redness_values, 90))
            redness_signal = max(mean_a, p90_a)
            redness_reference = personal_lab_baseline.get("a_mean", 128.0)
            redness = float(
                np.clip(((redness_signal - redness_reference) / 30.0) * 100.0, 0.0, 100.0)
            )
            forced_metric_values["localized_redness"] = round(redness, 1)
            forced_metric_paths["localized_redness"] = redness_path
            canonical_metric_matrix["localized_redness"] = forced_metric_values["localized_redness"]
            redness_force_write = True
            redness_forced_value = canonical_metric_matrix["localized_redness"]
            metric_status["localized_redness"] = "computed"
            fallback_reason["localized_redness"] = redness_path
            metric_confidence["localized_redness"] = _merge_confidence(
                metric_confidence.get("localized_redness", "low"),
                "medium",
            )
            logger.info(
                "REDNESS_FALLBACK_EMIT value=%s path=%s roi_pixels=%d cheek=%s",
                forced_metric_values["localized_redness"],
                redness_path,
                redness_roi_pixels,
                primary_cheek_pixels,
            )
        else:
            metric_status["localized_redness"] = "unavailable"
            fallback_reason["localized_redness"] = "non_usable_value"
    elif redness_unset:
        metric_status["localized_redness"] = "unavailable"
        fallback_reason["localized_redness"] = "cheek_reject_no_fallback"

    raw_components["texture_force_write"] = 1.0 if texture_force_write else 0.0
    raw_components["texture_laplacian_fallback_used"] = 1.0 if texture_force_write else 0.0
    raw_components["redness_force_write"] = 1.0 if redness_force_write else 0.0

    candidate_values: Dict[str, Any] = {
        "localized_redness": canonical_metric_matrix.get("localized_redness"),
        "texture_smoothness": canonical_metric_matrix.get("texture_smoothness"),
        "pigment_load": canonical_metric_matrix.get("pigment_load"),
        "pore_visibility": canonical_metric_matrix.get("pore_visibility"),
        "chin_pore_visibility": canonical_metric_matrix.get("chin_pore_visibility"),
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
    rosacea_calibrated = safe_float(zone_metrics.get("rosacea_severity"))
    if rosacea_calibrated is not None and math.isfinite(rosacea_calibrated):
        candidate_values["rosacea_severity"] = round(
            float(np.clip(rosacea_calibrated, 0.0, 100.0)),
            1,
        )

    fallback_used = locals().get("fallback_used", False)
    bbox_fallback_used = locals().get("bbox_fallback_used", False)
    pigment_roi_pixels = int(raw_components.get("pigment_roi_pixels", 0.0))
    force_metric_roi_usable: Dict[str, bool] = {
        "localized_redness": redness_roi_pixels >= 500,
        "texture_smoothness": large_fallback_pixels >= 500,
        "pigment_load": pigment_roi_pixels >= 500,
        "rosacea_severity": full_face_pixels >= 3000,
        "skin_tone_radiance_evenness": full_face_pixels >= 3000,
        "structural_firmness_elasticity": full_face_pixels >= 3000,
    }

    pigment_numeric = safe_float(candidate_values.get("pigment_load"))
    pigment_path = (
        "full_face_fallback"
        if bool(raw_components.get("pigment_full_face_fallback_used", 0.0) > 0.5)
        else "cheek_primary"
    )
    if (
        not _is_missing_metric_value(pigment_numeric)
        and pigment_roi_pixels >= 500
    ):
        forced_metric_values["pigment_load"] = round(
            float(np.clip(pigment_numeric, 0.0, 100.0)),
            1,
        )
        forced_metric_paths["pigment_load"] = pigment_path
        metric_status["pigment_load"] = "computed"
        fallback_reason["pigment_load"] = forced_metric_paths["pigment_load"]
        metric_confidence["pigment_load"] = _merge_confidence(
            metric_confidence.get("pigment_load", "low"),
            "medium",
        )
        logger.info(
            "PIGMENT_FALLBACK_EMIT value=%s path=%s roi_pixels=%d",
            forced_metric_values["pigment_load"],
            forced_metric_paths["pigment_load"],
            pigment_roi_pixels,
        )

    rosacea_numeric = safe_float(candidate_values.get("rosacea_severity"))
    if (
        not _is_missing_metric_value(rosacea_numeric)
        and full_face_pixels >= 3000
    ):
        forced_metric_values["rosacea_severity"] = round(
            float(np.clip(rosacea_numeric, 0.0, 100.0)),
            1,
        )
        forced_metric_paths["rosacea_severity"] = "primary_roi"
        metric_status["rosacea_severity"] = "computed"
        fallback_reason["rosacea_severity"] = "primary_roi"
        metric_confidence["rosacea_severity"] = _merge_confidence(
            metric_confidence.get("rosacea_severity", "low"),
            "medium",
        )
        logger.info(
            "ROSACEA_FALLBACK_EMIT value=%s path=primary_roi full_face_pixels=%d",
            forced_metric_values["rosacea_severity"],
            full_face_pixels,
        )

    skin_intersected_full_face_pixels = int(raw_components.get("full_face_skin_pixels", 0.0))
    skin_mask_failed_path = bool(raw_components.get("skin_mask_failed", 0.0) > 0.5)
    cheek_expand_no_skin_path = bool(raw_components.get("cheek_expand_no_skin_used", 0.0) > 0.5)
    radiance_weak_or_fallback_path = bool(
        fallback_used
        or bbox_fallback_used
        or skin_mask_failed_path
        or cheek_expand_no_skin_path
        or skin_intersected_full_face_pixels < 3000
    )
    radiance_numeric = safe_float(candidate_values.get("skin_tone_radiance_evenness"))
    if (
        not _is_missing_metric_value(radiance_numeric)
        and full_face_pixels >= 3000
    ):
        radiance_emit_value = round(
            float(np.clip(radiance_numeric, 0.0, 100.0)),
            1,
        )
        if not (radiance_emit_value >= 95.0 and radiance_weak_or_fallback_path):
            forced_metric_values["skin_tone_radiance_evenness"] = radiance_emit_value
            forced_metric_paths["skin_tone_radiance_evenness"] = "primary_roi"
            metric_status["skin_tone_radiance_evenness"] = "computed"
            fallback_reason["skin_tone_radiance_evenness"] = "primary_roi"
            metric_confidence["skin_tone_radiance_evenness"] = _merge_confidence(
                metric_confidence.get("skin_tone_radiance_evenness", "low"),
                "medium",
            )
            logger.info(
                "RADIANCE_FALLBACK_EMIT value=%s path=primary_roi full_face_pixels=%d",
                forced_metric_values["skin_tone_radiance_evenness"],
                full_face_pixels,
            )
        else:
            metric_status.setdefault("skin_tone_radiance_evenness", "unavailable")
            fallback_reason.setdefault("skin_tone_radiance_evenness", "radiance_fallback_cap")

    firmness_numeric = safe_float(candidate_values.get("structural_firmness_elasticity"))
    if (
        not _is_missing_metric_value(firmness_numeric)
        and full_face_pixels >= 3000
    ):
        forced_metric_values["structural_firmness_elasticity"] = round(
            float(np.clip(firmness_numeric, 0.0, 100.0)),
            1,
        )
        forced_metric_paths["structural_firmness_elasticity"] = "primary_roi"
        metric_status["structural_firmness_elasticity"] = "computed"
        fallback_reason["structural_firmness_elasticity"] = "primary_roi"
        metric_confidence["structural_firmness_elasticity"] = _merge_confidence(
            metric_confidence.get("structural_firmness_elasticity", "low"),
            "medium",
        )
        logger.info(
            "FIRMNESS_FALLBACK_EMIT value=%s path=primary_roi full_face_pixels=%d",
            forced_metric_values["structural_firmness_elasticity"],
            full_face_pixels,
        )

    core_emit_keys = {
        "localized_redness",
        "texture_smoothness",
        "pigment_load",
        "pore_visibility",
        "chin_pore_visibility",
        "wrinkle_load",
        "breakout_activity",
        "skin_tone_radiance_evenness",
        "rosacea_severity",
        "structural_firmness_elasticity",
        "glabellar_wrinkle_depth",
        "under_eye_texture_density",
        "under_eye_dark_circle_density",
    }

    # ROI pixel budgets used to distinguish an unusable ROI from an
    # adequately-sized ROI that produced an ambiguous zero reading. A zero
    # in the latter case is never promoted to a confident value or score
    # here — see the "insufficient_signal" branch in the emission loop below.
    small_roi_zero_floor_metrics = {
        "glabellar_wrinkle_depth": {
            "roi_pixels": glabella_pixels,
            "min_roi_pixels": 110,
        },
        "under_eye_texture_density": {
            "roi_pixels": under_eye_pixels,
            "min_roi_pixels": 24,
        },
        "under_eye_dark_circle_density": {
            "roi_pixels": under_eye_pixels,
            "min_roi_pixels": 24,
        },
    }

    for metric_key, cfg in small_roi_zero_floor_metrics.items():
        metric_numeric = safe_float(candidate_values.get(metric_key))
        has_positive_signal = (
            metric_numeric is not None
            and math.isfinite(metric_numeric)
            and metric_numeric > 0.0
        )
        if has_positive_signal:
            metric_confidence[metric_key] = _merge_confidence(
                metric_confidence.get(metric_key, "low"),
                "medium",
            )

    under_eye_mask_metrics = {
        "under_eye_texture_density",
        "under_eye_dark_circle_density",
    }

    pore_visibility_detected = "pore_visibility" in canonical_metric_matrix
    metric_matrix: Dict[str, Any] = {}
    emitted_metric_keys: list[str] = []
    omitted_metric_reasons: Dict[str, str] = {}

    for metric_key in canonical_metric_order:
        if metric_key in forced_metric_values:
            forced_numeric = safe_float(forced_metric_values.get(metric_key))
            if _is_missing_metric_value(forced_numeric):
                metric_status.setdefault(metric_key, "unavailable")
                omitted_metric_reasons[metric_key] = "non_usable_forced_value"
                fallback_reason.setdefault(metric_key, forced_metric_paths.get(metric_key, "fallback"))
                continue

            if (
                metric_key == "skin_tone_radiance_evenness"
                and forced_numeric >= 95.0
                and radiance_weak_or_fallback_path
            ):
                metric_status.setdefault(metric_key, "unavailable")
                omitted_metric_reasons[metric_key] = "radiance_fallback_cap"
                fallback_reason.setdefault(metric_key, forced_metric_paths.get(metric_key, "fallback"))
                continue

            confidence_level = metric_confidence.get(metric_key, "low")
            roi_usable = force_metric_roi_usable.get(metric_key, True)
            if (confidence_level == "low" and not roi_usable) or not roi_usable:
                omitted_metric_reasons[metric_key] = "weak_roi_force_write"
                fallback_reason.setdefault(metric_key, forced_metric_paths.get(metric_key, "fallback"))
                if metric_key not in metric_status:
                    metric_status[metric_key] = "computed"
                continue
            forced_value = round(float(np.clip(forced_numeric, 0.0, 100.0)), 1)
            metric_matrix[metric_key] = forced_value
            emitted_metric_keys.append(metric_key)
            metric_status[metric_key] = "computed"
            omitted_metric_reasons.pop(metric_key, None)
            fallback_reason.setdefault(metric_key, forced_metric_paths.get(metric_key, "fallback"))
            continue

        # Both under-eye metrics read the same under-eye mask. Below the
        # T-zone's usable-region floor it is a shadow pocket (~991 px on
        # the clear-face fixture), not a measurement, so omit both.
        if (
            metric_key in under_eye_mask_metrics
            and under_eye_pixels < MIN_USABLE_TZONE_PIXELS
        ):
            metric_status.setdefault(metric_key, "unavailable")
            omitted_metric_reasons[metric_key] = "under_eye_roi_too_small"
            fallback_reason.setdefault(metric_key, "under_eye_roi_too_small")
            continue

        raw_value = candidate_values.get(metric_key)
        numeric_value = safe_float(raw_value)
        confidence_level = metric_confidence.get(metric_key, "low")

        small_roi_config = small_roi_zero_floor_metrics.get(metric_key)
        if (
            small_roi_config is not None
            and numeric_value is not None
            and math.isfinite(numeric_value)
            and numeric_value <= 0.0
        ):
            roi_pixels = int(small_roi_config["roi_pixels"])
            min_roi_pixels = int(small_roi_config["min_roi_pixels"])
            if roi_pixels >= min_roi_pixels:
                # Adequate ROI but a hard zero: genuinely flawless and a
                # detector floor are indistinguishable here. Report that
                # honestly instead of fabricating a non-zero score.
                if metric_key == "glabellar_wrinkle_depth":
                    logger.info(
                        "GLABELLA_SIGNAL_LOG glabella_pixels=%d raw_computed_value=%s pitch=%.2f confidence=%s result=insufficient_signal",
                        glabella_pixels,
                        numeric_value,
                        glabella_pitch,
                        confidence_level,
                    )
                metric_status.setdefault(metric_key, "unavailable")
                omitted_metric_reasons[metric_key] = "insufficient_signal"
                fallback_reason.setdefault(metric_key, "insufficient_signal")
                continue

        if metric_key == "pore_contraction_index" and "pore_contraction_index" not in structural_metrics:
            metric_status.setdefault(metric_key, "unavailable")
            omitted_metric_reasons[metric_key] = "formula_not_available"
            fallback_reason.setdefault(metric_key, "formula_not_available")
            continue

        if metric_key == "pore_visibility" and not pore_visibility_detected:
            metric_status.setdefault(metric_key, "unavailable")
            omitted_metric_reasons[metric_key] = "pore_gate_not_usable"
            fallback_reason.setdefault(metric_key, "pore_gate_not_usable")
            continue

        if _is_missing_metric_value(numeric_value):
            metric_status.setdefault(metric_key, "unavailable")
            omitted_metric_reasons[metric_key] = "non_usable_value"
            fallback_reason.setdefault(metric_key, "non_usable_value")
            continue

        is_usable_confidence = confidence_level == "high" or (
            confidence_level == "medium" and metric_key in core_emit_keys
        )
        if not is_usable_confidence:
            metric_status.setdefault(metric_key, "unavailable")
            omitted_metric_reasons[metric_key] = f"confidence_{confidence_level}"
            fallback_reason.setdefault(metric_key, f"confidence_{confidence_level}")
            continue

        # A measured value that clips/rounds to exactly 0.0 (e.g. at or
        # below the zero-reference floor) is a genuine reading -- "no
        # visible redness", "no detected breakouts" -- not a failure, and
        # must be emitted honestly rather than omitted. Only a truly
        # missing/NaN/Infinite value (caught above) means unmeasurable.
        rounded_value = round(float(np.clip(numeric_value, 0.0, 100.0)), 1)

        if (
            metric_key == "skin_tone_radiance_evenness"
            and rounded_value >= 95.0
            and radiance_weak_or_fallback_path
        ):
            metric_status.setdefault(metric_key, "unavailable")
            omitted_metric_reasons[metric_key] = "radiance_fallback_cap"
            fallback_reason.setdefault(metric_key, "radiance_fallback_cap")
            continue

        metric_matrix[metric_key] = rounded_value
        if metric_key == "glabellar_wrinkle_depth":
            logger.info(
                "GLABELLA_SIGNAL_LOG glabella_pixels=%d raw_computed_value=%s pitch=%.2f confidence=%s result=emitted",
                glabella_pixels,
                numeric_value,
                glabella_pitch,
                confidence_level,
            )
        emitted_metric_keys.append(metric_key)
        metric_status[metric_key] = "computed"
        fallback_reason.setdefault(metric_key, f"confidence_{confidence_level}")

    metric_matrix = _normalize_metric_payload_values(metric_matrix)
    if rosacea_calibrated is not None and math.isfinite(rosacea_calibrated):
        rosacea_emit_value = round(float(np.clip(rosacea_calibrated, 0.0, 100.0)), 1)
        if "rosacea_severity" in metric_matrix and rosacea_emit_value > 0.0:
            metric_matrix["rosacea_severity"] = rosacea_emit_value
            logger.info("ROSACEA_EMIT_FINAL value=%s source=calibrated", rosacea_emit_value)
    _attach_localized_redness_baseline_p95(metric_matrix, redness_diagnostics)
    trend_metric_matrix = {
        key: value
        for key, value in metric_matrix.items()
        if key in canonical_metric_order
    }
    normalized_baseline_matrix = _normalize_metric_payload_values(
        baseline_matrix or {}
    )
    personal_lab_baseline = _coalesce_personal_lab_baseline(baseline_matrix or {})
    current_lab_reference = {
        "a_mean": float(np.mean(a_channel)) if a_channel.size > 0 else 128.0,
        "b_mean": float(np.mean(lab[:, :, 2])) if lab.size > 0 else 128.0,
        "a_p95": float(np.percentile(a_channel, 95)) if a_channel.size > 0 else 128.0,
        "b_p95": float(np.percentile(lab[:, :, 2], 95)) if lab.size > 0 else 128.0,
    }
    if personal_lab_baseline:
        baseline_redness = _compute_redness_from_personal_baseline(
            current_lab_reference,
            personal_lab_baseline,
        )
        if baseline_redness > 0.0:
            zone_metrics["localized_redness"] = round(
                float(np.clip(baseline_redness, 0.0, 100.0)),
                1,
            )
    metric_extraction_paths = _compute_metric_extraction_paths(
        metric_status,
        raw_components,
        canonical_metric_order,
    )
    if texture_force_write:
        metric_extraction_paths["texture_smoothness"] = "laplacian_fallback"
    if redness_force_write:
        metric_extraction_paths["localized_redness"] = redness_path

    for emitted_key in list(metric_matrix.keys()):
        metric_status[emitted_key] = "computed"
        emitted_path = metric_extraction_paths.get(emitted_key, "primary_roi")
        metric_extraction_paths[emitted_key] = _normalize_extraction_path_label(emitted_path)

    if "pore_visibility" not in metric_matrix:
        metric_extraction_paths["pore_visibility"] = _pore_visibility_omission_path(
            raw_components
        )

    if "localized_redness" in metric_matrix:
        logger.info(
            "REDNESS_EMIT_PATH value=%s path=%s roi_pixels=%d",
            metric_matrix.get("localized_redness"),
            metric_extraction_paths.get("localized_redness", "unknown"),
            int(raw_components.get("localized_redness_roi_pixels", 0.0)),
        )
    if "pigment_load" in metric_matrix:
        logger.info(
            "PIGMENT_EMIT_PATH value=%s path=%s roi_pixels=%d",
            metric_matrix.get("pigment_load"),
            metric_extraction_paths.get("pigment_load", "unknown"),
            int(raw_components.get("pigment_roi_pixels", 0.0)),
        )

    core_metric_8 = [
        "localized_redness",
        "texture_smoothness",
        "pore_visibility",
        "wrinkle_load",
        "pigment_load",
        "rosacea_severity",
        "skin_tone_radiance_evenness",
        "structural_firmness_elasticity",
    ]
    final_matrix_8_keys = [key for key in core_metric_8 if key in metric_matrix]
    logger.info(
        "FINAL_MATRIX_8 count=%d keys=%s",
        len(final_matrix_8_keys),
        final_matrix_8_keys,
    )
    normalized_baseline_paths = _normalize_metric_extraction_paths(
        baseline_extraction_paths,
        canonical_metric_order,
    )
    metric_formula_versions = {
        key: _metric_formula_version(key) for key in canonical_metric_order
    }
    normalized_baseline_formula_versions = _normalize_baseline_metric_formula_versions(
        baseline_formula_versions,
        canonical_metric_order,
    )
    normalized_baseline_formula_versions = _baseline_formula_versions_for_redness_reference(
        normalized_baseline_formula_versions,
        baseline_matrix or {},
    )
    normalized_capture_quality = _normalize_capture_quality(capture_quality)
    normalized_baseline_capture_quality = _normalize_capture_quality(
        baseline_capture_quality
    )
    trend_deltas = _compute_trend_deltas(
        trend_metric_matrix,
        normalized_baseline_matrix,
        current_paths=metric_extraction_paths,
        baseline_paths=normalized_baseline_paths,
        current_capture_quality=normalized_capture_quality,
        baseline_capture_quality=normalized_baseline_capture_quality,
        current_source_width=source_image_width,
        current_source_height=source_image_height,
        baseline_source_width=baseline_source_image_width,
        baseline_source_height=baseline_source_image_height,
        current_formula_versions=metric_formula_versions,
        baseline_formula_versions=normalized_baseline_formula_versions,
        honesty_band_pct=HONESTY_STABLE_BAND_PCT,
        current_pose_template=pose_template,
        baseline_pose_template=baseline_pose_template,
        current_guide_type=guide_type,
        baseline_guide_type=baseline_guide_type,
    )
    trend_status = _compute_trend_statuses(
        trend_metric_matrix,
        normalized_baseline_matrix,
        current_paths=metric_extraction_paths,
        baseline_paths=normalized_baseline_paths,
        current_capture_quality=normalized_capture_quality,
        baseline_capture_quality=normalized_baseline_capture_quality,
        current_source_width=source_image_width,
        current_source_height=source_image_height,
        baseline_source_width=baseline_source_image_width,
        baseline_source_height=baseline_source_image_height,
        current_formula_versions=metric_formula_versions,
        baseline_formula_versions=normalized_baseline_formula_versions,
        honesty_band_pct=HONESTY_STABLE_BAND_PCT,
        current_pose_template=pose_template,
        baseline_pose_template=baseline_pose_template,
        current_guide_type=guide_type,
        baseline_guide_type=baseline_guide_type,
    )
    # Purely informational: explains WHY a "stable" trend_status was reached
    # (a genuine small delta vs. one of the honesty-gate mismatches) so the
    # UI can message the two cases differently. Does not affect trend_status
    # or trend_deltas.
    trend_lock_reasons = _compute_trend_lock_reasons(
        trend_metric_matrix,
        normalized_baseline_matrix,
        current_paths=metric_extraction_paths,
        baseline_paths=normalized_baseline_paths,
        current_capture_quality=normalized_capture_quality,
        baseline_capture_quality=normalized_baseline_capture_quality,
        current_source_width=source_image_width,
        current_source_height=source_image_height,
        baseline_source_width=baseline_source_image_width,
        baseline_source_height=baseline_source_image_height,
        current_formula_versions=metric_formula_versions,
        baseline_formula_versions=normalized_baseline_formula_versions,
        current_pose_template=pose_template,
        baseline_pose_template=baseline_pose_template,
        current_guide_type=guide_type,
        baseline_guide_type=baseline_guide_type,
    )
    trend_deltas = _stabilize_trend_deltas_for_near_identical_scan(
        trend_deltas,
        trend_metric_matrix,
        normalized_baseline_matrix,
        baseline_ssim,
    )

    # LEGACY top-level duplicates, NOT canonical producers (see the
    # CANONICAL_METRIC_ORDER producer registry comment above and
    # test_canonical_metric_producer_registry.py): calibrated_redness_score,
    # calibrated_smoothness_score, acne_activity_score, and raw_pore_density
    # are independent formulas that bypass the canonical ROI/confidence
    # pipeline entirely. They exist only so old client-side scans that stored
    # these legacy keys can still resolve a baseline alias lookup; they must
    # never be read as an alternate source for localized_redness,
    # texture_smoothness, breakout_activity, or pore_visibility.
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

    emitted_path_log = {
        key: metric_extraction_paths.get(key, "unknown")
        for key in emitted_metric_keys
    }
    calibration_log_metrics = [
        "localized_redness",
        "pigment_load",
        "rosacea_severity",
        "under_eye_dark_circle_density",
        "under_eye_texture_density",
        "glabellar_wrinkle_depth",
        "texture_smoothness",
        "wrinkle_load",
        "structural_firmness_elasticity",
        "skin_tone_radiance_evenness",
        # Added so a future repeatability session (tool/analyze_repeatability.py)
        # can measure noise floors for these two -- they had none of the ten
        # metrics above's CALIBRATION_LOG history to measure from. pore_visibility
        # is currently fully ungated (no honesty-band-equivalent floor at all)
        # and was observed reporting a 17% "improvement" on an unchanged face.
        "pore_visibility",
        "breakout_activity",
    ]
    calibration_roi_pixels = {
        "localized_redness": "localized_redness_roi_pixels",
        "pigment_load": "pigment_roi_pixels",
        "rosacea_severity": "full_face_skin_pixels",
        "under_eye_dark_circle_density": "under_eye_pixels",
        "under_eye_texture_density": "under_eye_pixels",
        "glabellar_wrinkle_depth": "glabella_pixels",
        "texture_smoothness": "texture_roi_pixels",
        "wrinkle_load": "wrinkle_roi_pixels",
        "structural_firmness_elasticity": "full_face_skin_pixels",
        "skin_tone_radiance_evenness": "full_face_skin_pixels",
        "pore_visibility": "primary_pore_roi_pixels",
        "breakout_activity": "breakout_roi_pixels",
    }
    for metric_key in calibration_log_metrics:
        if metric_key not in metric_matrix:
            continue
        value = metric_matrix.get(metric_key)
        confidence = metric_confidence.get(metric_key, "low")
        path = metric_extraction_paths.get(metric_key, "unknown")
        capture_label = _normalize_capture_quality(capture_quality)
        roi_key = calibration_roi_pixels.get(metric_key, "unknown")
        if roi_key == "under_eye_pixels":
            roi_pixels = under_eye_pixels
        elif roi_key == "glabella_pixels":
            roi_pixels = glabella_pixels
        elif roi_key == "unknown":
            roi_pixels = 0
        else:
            roi_pixels = int(raw_components.get(roi_key, 0.0))
        # This is the ONLY place CALIBRATION_LOG is emitted (confirmed via
        # `git log -S "CALIBRATION_LOG"` -- this exact 6-field format has
        # been here, unchanged, since it was introduced). Real captured logs
        # have nonetheless shown truncated lines with only
        # "metric=... value=..." and nothing after it. Since there is no
        # second logger.info call producing a shorter format, that
        # truncation happens downstream of this call -- in how the console
        # output was captured to a file (e.g. terminal line-wrapping or an
        # ANSI-sequence interaction from a colorized/transcript-style
        # capture, rather than a plain shell redirect) -- not from this
        # code path itself. tool/analyze_repeatability.py's parser treats
        # every field after value= as optional for exactly this reason.
        logger.info(
            "CALIBRATION_LOG metric=%s value=%s confidence=%s path=%s capture_quality=%s roi_pixels=%d",
            metric_key,
            value,
            confidence,
            path,
            capture_label,
            roi_pixels,
        )
    logger.info(
        "ROI_PATH_SUMMARY cheek=%d tzone_skin=%d texture_roi=%d redness_path=%s pigment_path=%s texture_path=%s",
        int(raw_components.get("primary_cheek_roi_pixels", 0.0)),
        int(raw_components.get("primary_t_zone_skin_pixels", 0.0)),
        int(raw_components.get("texture_roi_pixels", 0.0)),
        metric_extraction_paths.get("localized_redness", "unknown"),
        metric_extraction_paths.get("pigment_load", "unknown"),
        metric_extraction_paths.get("texture_smoothness", "unknown"),
    )
    logger.info("METRICS emitted_paths=%s", emitted_path_log)
    logger.info("METRICS emitted_keys=%s", emitted_metric_keys)
    logger.info("METRICS omitted_keys=%s", omitted_metric_reasons)
    logger.info(
        "METRICS roi_debug skin_mask_failed=%s bbox_fallback_used=%s roi_after_fallback=%d primary_roi_pixels={cheek:%d,tzone:%d,texture:%d,pigment:%d,pore:%d,breakout:%d} fallback_used=%s fallback_roi_pixels={texture:%d,pigment:%d,pore:%d,breakout:%d} smoothness=%s emitted_keys=%s emitted_paths=%s matrix_keys=%s",
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
        emitted_path_log,
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
                "glabellar_wrinkle_depth",
                "under_eye_texture_density",
                "under_eye_dark_circle_density",
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

    experimental_metrics = (
        _SCIN_EXPERIMENTAL_MODELS.predict(norm)
        if _SCIN_EXPERIMENTAL_MODELS is not None
        else {}
    )
    experimental_model_metadata = (
        _SCIN_EXPERIMENTAL_MODELS.metadata()
        if _SCIN_EXPERIMENTAL_MODELS is not None
        else {
            "status": "unavailable",
            "experimental": True,
            "canonical": False,
        }
    )

    # Logging only: which producer set canonical localized_redness above.
    if zone_redness is not None and math.isfinite(zone_redness):
        redness_branch = str(redness_diagnostics.get("branch") or "unknown_zone_branch")
    elif redness_force_write:
        redness_branch = "redness_fallback_emit"
    else:
        redness_branch = "unavailable"
    p10_a_before_wb, p95_a_before_wb = _pre_white_balance_cheek_percentiles_a(
        pre_white_balance_bgr,
        points,
        redness_diagnostics.get("mask"),
    )
    def metric_mask_kind(metric_key: str) -> str | None:
        path = metric_extraction_paths.get(metric_key)
        if metric_key == "texture_smoothness":
            if raw_components.get("texture_forehead_skin_used", 0.0) > 0.5:
                return "forehead_skin"
            if raw_components.get("texture_u_zone_used", 0.0) > 0.5:
                return "u_zone"
        if metric_key == "pigment_load" and path in {
            "cheek_primary",
            "cheek_primary_no_skin_mask",
        }:
            return "u_zone"
        if path in {"cheek_primary", "cheek_primary_no_skin_mask", "cheek_expand_no_skin"}:
            return "cheek_primary"
        if path == "fallback" and metric_key == "pore_visibility":
            return "tzone_pore"
        if path in {"primary_roi", "full_face_fallback", "large_roi_fallback", "approximate_face_bbox", "laplacian_fallback"}:
            return "face_skin"
        return None

    redness_mask_kind = metric_mask_kind("localized_redness")
    if redness_branch == "within_cheek_spread":
        cheek_side = redness_diagnostics.get("cheek_side")
        if cheek_side in {"left", "right"}:
            redness_mask_kind = f"{cheek_side}_cheek"
    elif redness_branch == "baseline_p95_anchor":
        redness_mask_kind = "u_zone"

    image_quality_payload = {
        **(quality_profile or {}),
        **_redness_color_diagnostics(
            redness_diagnostics,
            branch=redness_branch,
            p10_a_before_wb=p10_a_before_wb,
            p95_a_before_wb=p95_a_before_wb,
        ),
        "face_skin_pixels": int(raw_components.get("full_face_skin_pixels", 0.0)),
        "pore_roi_pixels": int(raw_components.get("primary_pore_roi_pixels", 0.0)),
        "u_zone_pixels": int(redness_diagnostics.get("u_zone_pixels", 0)),
        "cheek_side_convention": CHEEK_SIDE_CONVENTION,
        "localized_redness_mask_kind": redness_mask_kind,
        "localized_redness_mask_pixels": int(
            redness_diagnostics.get("cheek_roi_pixels")
            or raw_components.get("localized_redness_roi_pixels", 0.0)
        ),
        "texture_smoothness_mask_kind": metric_mask_kind("texture_smoothness"),
        "texture_smoothness_mask_pixels": int(
            raw_components.get("texture_roi_pixels", 0.0)
        ),
        "pigment_load_mask_kind": metric_mask_kind("pigment_load"),
        "pigment_load_mask_pixels": int(
            raw_components.get("pigment_roi_pixels", 0.0)
        ),
        "pore_visibility_mask_kind": "tzone_pore",
        "pore_visibility_mask_pixels": int(
            raw_components.get("primary_pore_roi_pixels", 0.0)
        ),
        "chin_pore_visibility_mask_kind": "chin_pore",
        "chin_pore_visibility_mask_pixels": int(
            raw_components.get("chin_pore_visibility_mask_pixels", 0.0)
        ),
        "diffuse_flushing_erythema_mask_kind": additional_mask_diagnostics.get(
            "diffuse_flushing_erythema_mask_kind"
        ),
        "diffuse_flushing_erythema_mask_pixels": additional_mask_diagnostics.get(
            "diffuse_flushing_erythema_mask_pixels"
        ),
    }

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
        "omitted_metric_reasons": omitted_metric_reasons,
        "fallback_reason": fallback_reason,
        "metric_extraction_paths": metric_extraction_paths,
        "baseline_metric_extraction_paths": normalized_baseline_paths,
        # Provenance for the trend gate's formula_version_mismatch check
        # (see METRIC_FORMULA_VERSION) -- lets a client echo this scan's
        # versions back as baseline_formula_versions on a later comparison.
        "metric_formula_versions": metric_formula_versions,
        "baseline_metric_formula_versions": normalized_baseline_formula_versions,
        "capture_quality": normalized_capture_quality,
        "baseline_capture_quality": normalized_baseline_capture_quality,
        "source_image_width": source_image_width,
        "source_image_height": source_image_height,
        "baseline_source_image_width": baseline_source_image_width,
        "baseline_source_image_height": baseline_source_image_height,
        "confidence_score": confidence_score,
        "confidence_hints": confidence_hints if confidence_score < 0.65 else [],
        "image_quality": image_quality_payload,
        "fingerprint": fingerprint,
        "calibration": calibration,
        "metric_matrix": metric_matrix,
        # EXPERIMENTAL ONLY: these probabilities never enter candidate_values,
        # canonical metric_matrix, trends, polarity, or clinical scoring.
        "experimental_metrics": experimental_metrics,
        "experimental_model_metadata": experimental_model_metadata,
        "zone_analysis": zone_analysis,
        "trend_deltas": trend_deltas,
        "trend_status": trend_status,
        "trend_lock_reasons": trend_lock_reasons,
        "metric_polarity": {
            key: (
                "higher_is_worse"
                if _metric_higher_is_worse(key)
                else "higher_is_better"
            )
            for key in canonical_metric_order
        },
        "honesty_band_percent": HONESTY_STABLE_BAND_PCT,
        # Published so a caller that aggregates multiple backend calls
        # itself (e.g. the app's multi-frame capture, which averages several
        # single-frame responses into one displayed value the backend never
        # sees) can re-apply the SAME noise-floor policy to that aggregated
        # value, instead of either skipping the check or hardcoding a second,
        # driftable copy of these constants client-side. See
        # METRIC_NOISE_FLOOR_2SD's comment for what these mean and their
        # single-session/single-device provenance.
        "metric_noise_floor_2sd": METRIC_NOISE_FLOOR_2SD,
        "trend_noise_floor_exceeds_useful_range": sorted(
            TREND_NOISE_FLOOR_EXCEEDS_USEFUL_RANGE
        ),
        "trend_noise_floor_excluded_multiplier": TREND_NOISE_FLOOR_EXCLUDED_MULTIPLIER,
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
    logger.info("AestheticSkin backend started (port=%s)", os.getenv("PORT", "8000"))
    yield
    logger.info("AestheticSkin backend shutting down")


app = FastAPI(title="AestheticSkin Analysis API", version="0.3.2", lifespan=lifespan)

# Defaults to localhost-only for local dev; set ALLOWED_ORIGIN_REGEX in any
# deployed environment that serves the Flutter web build from a real origin.
_CORS_ORIGIN_REGEX = os.getenv(
    "ALLOWED_ORIGIN_REGEX", r"http://(127\.0\.0\.1|localhost)(:\d+)?"
)
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=_CORS_ORIGIN_REGEX,
    allow_methods=["POST", "GET", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization", "X-API-Key"],
)

# Simple shared-secret auth for every /api/ route. Missing the env var is
# treated as local development: requests are allowed through, but loudly
# logged so this is never silently deployed unauthenticated.
_BACKEND_API_KEY = os.getenv("BACKEND_API_KEY", "").strip()
if not _BACKEND_API_KEY:
    logger.warning(
        "SECURITY WARNING: BACKEND_API_KEY is not set. Every /api/ endpoint is "
        "UNAUTHENTICATED. This is only acceptable for local development - set "
        "BACKEND_API_KEY before deploying anywhere reachable over the network."
    )


@app.middleware("http")
async def _require_api_key(request: Request, call_next):
    if (
        _BACKEND_API_KEY
        and request.method != "OPTIONS"
        and request.url.path.startswith("/api/")
    ):
        provided = request.headers.get("x-api-key", "")
        if not hmac.compare_digest(provided, _BACKEND_API_KEY):
            return JSONResponse(
                status_code=401,
                content={"detail": "Missing or invalid X-API-Key header."},
            )
    return await call_next(request)


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


@app.post("/api/body/analyze-silhouette")
async def analyze_body_silhouette_endpoint(request: Request):
    try:
        ensure_body_pipeline_ready()
        body = await request.json()
        image_b64 = body.get("imageBytes") or body.get("image_bytes") or body.get("image")
        if not image_b64:
            raise HTTPException(status_code=422, detail="Missing image data (imageBytes / image_bytes / image)")

        image_data = base64.b64decode(image_b64)
        image_bgr = _decode_image_bytes(image_data)
        if image_bgr is None or image_bgr.size == 0:
            raise HTTPException(status_code=400, detail="Decoded image is empty for body silhouette analysis.")

        current_capture_quality = _normalize_capture_quality(
            body.get("captureQuality") or body.get("capture_quality")
        )
        baseline_capture_quality = _normalize_capture_quality(
            body.get("baselineCaptureQuality") or body.get("baseline_capture_quality")
        )
        current_source_width = safe_float(
            body.get("sourceImageWidth") or body.get("source_image_width")
        )
        current_source_height = safe_float(
            body.get("sourceImageHeight") or body.get("source_image_height")
        )
        baseline_source_width = safe_float(
            body.get("baselineSourceImageWidth") or body.get("baseline_source_image_width")
        )
        baseline_source_height = safe_float(
            body.get("baselineSourceImageHeight") or body.get("baseline_source_image_height")
        )
        # PROVISIONAL, same as the rest of this endpoint: which real-world
        # setup (mirror / assisted / timer) produced each photo. Only used
        # as a mismatch signal in _body_trend_delta_and_status — not
        # normalized/validated against a fixed enum here, matching how
        # capture_quality tags are handled loosely at this layer too.
        current_capture_mode_raw = body.get("captureMode") or body.get("capture_mode")
        current_capture_mode = (
            str(current_capture_mode_raw).strip().lower() or None
            if current_capture_mode_raw is not None
            else None
        )
        baseline_capture_mode_raw = body.get("baselineCaptureMode") or body.get("baseline_capture_mode")
        baseline_payload = body.get("baselineResult") or body.get("baseline_result")
        if baseline_payload is None:
            baseline_payload = body.get("baselineMetricMatrix") or body.get("baseline_metric_matrix")
        if baseline_payload is None:
            baseline_payload = body.get("baselineMetrics") or body.get("baseline_metrics")

        if isinstance(baseline_payload, str):
            try:
                baseline_payload = json.loads(baseline_payload)
            except json.JSONDecodeError:
                baseline_payload = None

        if isinstance(baseline_payload, dict) and not baseline_payload.get("normalized_area_index") and not baseline_payload.get("area_index"):
            baseline_payload = {
                "normalized_area_index": baseline_payload.get("normalizedAreaIndex") or baseline_payload.get("normalized_area_index") or baseline_payload.get("area_index"),
                "scale_reference_pixels": baseline_payload.get("scaleReferencePixels") or baseline_payload.get("scale_reference_pixels"),
                "roi_pixel_count": baseline_payload.get("roiPixelCount") or baseline_payload.get("roi_pixel_count"),
                "confidence": baseline_payload.get("confidence"),
                "capture_mode": baseline_payload.get("captureMode") or baseline_payload.get("capture_mode"),
            }

        baseline_result = None
        if baseline_payload is not None and isinstance(baseline_payload, dict):
            baseline_result = {
                "normalized_area_index": safe_float(baseline_payload.get("normalized_area_index"))
                if baseline_payload.get("normalized_area_index") is not None
                else safe_float(baseline_payload.get("normalizedAreaIndex")),
                "scale_reference_pixels": safe_float(baseline_payload.get("scale_reference_pixels"))
                if baseline_payload.get("scale_reference_pixels") is not None
                else safe_float(baseline_payload.get("scaleReferencePixels")),
                "roi_pixel_count": safe_float(baseline_payload.get("roi_pixel_count"))
                if baseline_payload.get("roi_pixel_count") is not None
                else safe_float(baseline_payload.get("roiPixelCount")),
                "confidence": safe_float(baseline_payload.get("confidence")),
                "consistent_scan_count": int(
                    body.get("baselineConsistentScanCount")
                    or body.get("baseline_consistent_scan_count")
                    or baseline_payload.get("consistent_scan_count")
                    or baseline_payload.get("consistentScanCount")
                    or 1
                ),
                "capture_mode": (
                    baseline_capture_mode_raw
                    or baseline_payload.get("capture_mode")
                    or baseline_payload.get("captureMode")
                ),
            }

        result = analyze_body_silhouette(image_bgr)
        candidate_consistent_scan_count = int(
            body.get("currentConsistentScanCount")
            or body.get("current_consistent_scan_count")
            or body.get("consistentScanCount")
            or body.get("consistent_scan_count")
            or result.get("consistent_scan_count")
            or 1
        )
        baseline_capture_mode_value = baseline_result.get("capture_mode") if baseline_result else None
        baseline_capture_mode = (
            str(baseline_capture_mode_value).strip().lower() or None
            if baseline_capture_mode_value is not None
            else None
        )
        current_consistent_scan_count = _body_consistent_scan_count(
            result,
            baseline_result,
            candidate_count=candidate_consistent_scan_count,
            current_capture_quality=current_capture_quality,
            baseline_capture_quality=baseline_capture_quality,
            current_capture_mode=current_capture_mode,
            baseline_capture_mode=baseline_capture_mode,
            current_source_width=int(current_source_width) if current_source_width else None,
            current_source_height=int(current_source_height) if current_source_height else None,
            baseline_source_width=int(baseline_source_width) if baseline_source_width else None,
            baseline_source_height=int(baseline_source_height) if baseline_source_height else None,
        )
        result["consistent_scan_count"] = current_consistent_scan_count
        trend_deltas, trend_status, honesty_band_pct, required_consistent_scans, trend_lock_reasons = _compute_body_silhouette_trend(
            result,
            baseline_result,
            current_capture_quality=current_capture_quality,
            baseline_capture_quality=baseline_capture_quality,
            current_consistent_scan_count=current_consistent_scan_count,
            baseline_consistent_scan_count=(baseline_result.get("consistent_scan_count") if baseline_result else 1),
            current_capture_mode=current_capture_mode,
            baseline_capture_mode=baseline_capture_mode,
            current_source_width=int(current_source_width) if current_source_width else None,
            current_source_height=int(current_source_height) if current_source_height else None,
            baseline_source_width=int(baseline_source_width) if baseline_source_width else None,
            baseline_source_height=int(baseline_source_height) if baseline_source_height else None,
        )

        response = {
            "status": "success",
            "text": "Body silhouette analysis complete.",
            "modelUsed": "mediapipe-pose+selfie-segmentation",
            "result": result,
            "trend_deltas": trend_deltas,
            "trend_status": trend_status,
            "trend_lock_reasons": trend_lock_reasons,
            "honesty_band_percent": honesty_band_pct,
            "consistent_scan_requirement": required_consistent_scans,
            "consistent_scan_count": current_consistent_scan_count,
            "source_image_width": int(current_source_width) if current_source_width else None,
            "source_image_height": int(current_source_height) if current_source_height else None,
        }
        return response
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Body silhouette endpoint failed")
        raise HTTPException(status_code=400, detail=str(exc))


@app.get("/health")
async def health_check():
    # GIT_COMMIT is baked into the image as an env var at `docker build
    # --build-arg GIT_COMMIT=...` time (see Dockerfile) -- there is no .git
    # directory in the running container to read it from at request time.
    # Missing/unset -> "unknown", never a failed health check.
    commit = os.environ.get("GIT_COMMIT", "").strip() or "unknown"
    return {"status": "ok", "commit": commit}


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
        baseline_extraction_paths = _normalize_metric_extraction_paths(
            body.get("baselineExtractionPaths") or body.get("baseline_extraction_paths"),
            CANONICAL_METRIC_ORDER,
        )
        baseline_formula_versions = _normalize_baseline_metric_formula_versions(
            body.get("baselineFormulaVersions") or body.get("baseline_formula_versions"),
            CANONICAL_METRIC_ORDER,
        )
        capture_quality = _normalize_capture_quality(
            body.get("captureQuality") or body.get("capture_quality")
        )
        baseline_capture_quality = _normalize_capture_quality(
            body.get("baselineCaptureQuality") or body.get("baseline_capture_quality")
        )
        current_source_width = safe_float(
            body.get("sourceImageWidth") or body.get("source_image_width")
        )
        current_source_height = safe_float(
            body.get("sourceImageHeight") or body.get("source_image_height")
        )
        baseline_source_width = safe_float(
            body.get("baselineSourceImageWidth") or body.get("baseline_source_image_width")
        )
        baseline_source_height = safe_float(
            body.get("baselineSourceImageHeight") or body.get("baseline_source_image_height")
        )
        pose_template = body.get("poseTemplate") or body.get("pose_template")
        baseline_pose_template = body.get("baselinePoseTemplate") or body.get(
            "baseline_pose_template"
        )
        guide_type = body.get("guideType") or body.get("guide_type")
        baseline_guide_type = body.get("baselineGuideType") or body.get(
            "baseline_guide_type"
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

        (
            normalized_image,
            quality_profile,
            pre_white_balance_image,
        ) = _assess_and_normalize_image_with_pre_white_balance(image_data)
        logger.info("/api/analyze-skin request matrix accepted for inference.")
        validate_camera_hardware_qa(normalized_image)
        result = analyze_skin_patch(
            normalized_image,
            baseline_matrix=baseline_matrix,
            baseline_extraction_paths=baseline_extraction_paths,
            baseline_formula_versions=baseline_formula_versions,
            capture_quality=capture_quality,
            baseline_capture_quality=baseline_capture_quality,
            quality_profile=quality_profile,
            baseline_image_bgr=baseline_image_bgr,
            source_image_width=int(current_source_width) if current_source_width else None,
            source_image_height=int(current_source_height) if current_source_height else None,
            baseline_source_image_width=int(baseline_source_width) if baseline_source_width else None,
            baseline_source_image_height=int(baseline_source_height) if baseline_source_height else None,
            pose_template=str(pose_template) if pose_template else None,
            baseline_pose_template=str(baseline_pose_template) if baseline_pose_template else None,
            guide_type=str(guide_type) if guide_type else None,
            baseline_guide_type=str(baseline_guide_type) if baseline_guide_type else None,
            pre_white_balance_bgr=pre_white_balance_image,
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
        if message in {YUNET_PRECISE_LANDMARKS_MESSAGE, YUNET_PARTIAL_FACE_MESSAGE}:
            raise HTTPException(status_code=400, detail=message)
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
    capture_quality: str | None = Form(None),
    baseline_capture_quality: str | None = Form(None),
    days_post_op: str | None = Form(None),
    skin_profile_note: str | None = Form(None),
    selected_skin_profile_note: str | None = Form(None),
    rosacea_score: str | None = Form(None),
    sensitivity_score: str | None = Form(None),
    compromised_barrier: str | None = Form(None),
    baseline_metric_matrix: str | None = Form(None),
    baseline_extraction_paths: str | None = Form(None),
    baseline_formula_versions: str | None = Form(None),
    source_image_width: int | None = Form(None),
    source_image_height: int | None = Form(None),
    baseline_source_image_width: int | None = Form(None),
    baseline_source_image_height: int | None = Form(None),
    pose_template: str | None = Form(None),
    baseline_pose_template: str | None = Form(None),
    guide_type: str | None = Form(None),
    baseline_guide_type: str | None = Form(None),
):
    try:
        ensure_pipeline_ready()

        parsed_baseline_matrix = _parse_baseline_metric_matrix(baseline_metric_matrix)
        parsed_baseline_paths = _normalize_metric_extraction_paths(
            baseline_extraction_paths,
            CANONICAL_METRIC_ORDER,
        )
        parsed_baseline_formula_versions = _normalize_baseline_metric_formula_versions(
            baseline_formula_versions,
            CANONICAL_METRIC_ORDER,
        )
        parsed_capture_quality = _normalize_capture_quality(capture_quality)
        parsed_baseline_capture_quality = _normalize_capture_quality(
            baseline_capture_quality
        )

        contents = await image.read()
        if not contents:
            raise HTTPException(status_code=400, detail="Empty file attachment package received.")

        try:
            (
                img_bgr,
                quality_profile,
                pre_white_balance_image,
            ) = _assess_and_normalize_image_with_pre_white_balance(contents)
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
            baseline_extraction_paths=parsed_baseline_paths,
            baseline_formula_versions=parsed_baseline_formula_versions,
            capture_quality=parsed_capture_quality,
            baseline_capture_quality=parsed_baseline_capture_quality,
            quality_profile=quality_profile,
            baseline_image_bgr=baseline_image_bgr,
            source_image_width=source_image_width,
            source_image_height=source_image_height,
            baseline_source_image_width=baseline_source_image_width,
            baseline_source_image_height=baseline_source_image_height,
            pose_template=pose_template,
            baseline_pose_template=baseline_pose_template,
            guide_type=guide_type,
            baseline_guide_type=baseline_guide_type,
            pre_white_balance_bgr=pre_white_balance_image,
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
            "metric_extraction_paths": results.get("metric_extraction_paths", {}),
            "baseline_metric_extraction_paths": results.get(
                "baseline_metric_extraction_paths",
                {},
            ),
            "metric_formula_versions": results.get("metric_formula_versions", {}),
            "baseline_metric_formula_versions": results.get(
                "baseline_metric_formula_versions",
                {},
            ),
            "capture_quality": results.get("capture_quality", "unknown"),
            "baseline_capture_quality": results.get(
                "baseline_capture_quality",
                "unknown",
            ),
            "metric_matrix": results.get("metric_matrix", {}),
            "trend_deltas": results.get("trend_deltas", {}),
            "trend_status": results.get("trend_status", {}),
            "metric_polarity": results.get("metric_polarity", {}),
            "honesty_band_percent": results.get(
                "honesty_band_percent",
                HONESTY_STABLE_BAND_PCT,
            ),
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
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=int(os.getenv("PORT", "8000")),
        reload=bool(os.getenv("UVICORN_RELOAD")),
    )