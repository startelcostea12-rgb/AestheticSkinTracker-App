FROM python:3.11-slim

# Set via `docker build --build-arg GIT_COMMIT=$(git rev-parse HEAD) ...` in
# the deploy pipeline. Baked in as an env var (not read from a .git dir,
# which isn't copied into the image) so GET /health can report exactly
# which commit is actually running. Left unset -> /health reports "unknown"
# rather than failing.
ARG GIT_COMMIT=unknown
ENV GIT_COMMIT=$GIT_COMMIT

# OpenCV/MediaPipe need these native libs even in "headless" mode.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
# torch/torchvision from the default index pull the full CUDA runtime
# stack (nvidia-cublas-cu12, nvidia-cudnn-cu12, etc.) even though this
# service only ever does CPU inference -- that alone is several GB and is
# what exhausts the build. Installing the CPU-only build first satisfies
# requirements.txt's torch>=2.0.0/torchvision>=0.15.0 constraints (a
# "2.x+cpu" version numerically satisfies ">=2.0.0"), so the second
# install step recognizes them as already satisfied and does not reinstall
# from the default index.
RUN pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu torch torchvision \
    && pip install --no-cache-dir -r requirements.txt

COPY main.py .
COPY scin_experimental_models.py .
COPY model_evaluation_gate.py .

# All committed model directories (~57 MB total - negligible next to the
# torch/mediapipe/ultralytics pip packages, so nothing is cherry-picked here).
# ensure_pipeline_ready() loads best.pt + face_detector.tflite + the two SCIN
# .pth files at startup; pose_landmarker_full.task/selfie_segmenter.tflite
# load lazily on first /api/body/analyze-silhouette call - omitting them
# would silently break that endpoint for no real size benefit.
COPY assets/models/ assets/models/
COPY backend/models/ backend/models/
COPY ml_models/ ml_models/

ENV PYTHONUNBUFFERED=1

EXPOSE 8080

CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080}"]
