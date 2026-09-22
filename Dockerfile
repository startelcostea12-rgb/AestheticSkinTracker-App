FROM python:3.11-slim

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
RUN pip install --no-cache-dir -r requirements.txt

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
