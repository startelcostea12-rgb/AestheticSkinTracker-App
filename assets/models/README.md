# AI Models — Skin Analysis (Hybrid Stack)

This folder holds the on-device AI models used by **Skin AI Analysis**
and the **Acne & Rosacea Tracker**. None of these `.tflite` files are
committed — train / convert / download each one and drop it in here.

When a model is missing the app simply skips that stage. The badge in
the results UI always tells the user exactly which engines fired, so
the user can never be misled into thinking AI ran when it didn't.

## The hybrid pipeline

1. **ML Kit Face Mesh** (Android / iOS only) — crops to the face and
   reports `face coverage %` and `L/R symmetry %`. Code:
   `lib/utils/ai/face_mesh_service*.dart`.
2. **YOLOv8-Nano (or v11-Nano) acne / lesion detector** — per-lesion
   bounding boxes for papules, pustules, cysts, blackheads, whiteheads
   and dark spots. Drives `acneSeverity`, `cysticAcneSeverity`, and
   `hormonalAcneSeverity` via per-class counts. Code:
   `lib/utils/ai/yolo_acne_detector*.dart`.
3. **EfficientNet-B0 skin-quality multi-head** — global scores for
   texture, wrinkles, pores, elasticity, overall. Blended into
   `skinSensitivity` / `rosaceaSeverity`. Code:
   `lib/utils/ai/efficientnet_skin_quality*.dart`.
4. **Legacy ACNE04 MobileNetV2 classifier** — fallback for
   `acneSeverity` only when YOLO is not bundled.
5. **Calibrated rule engine** (`lib/utils/acne_rosacea_photo_analysis.dart`)
   owns every metric the AI didn't.

## Expected files

| Asset                                              | Input            | Output                                | Used by                                |
| -------------------------------------------------- | ---------------- | ------------------------------------- | -------------------------------------- |
| `assets/models/yolo_acne_detector.tflite`          | `[1,640,640,3]` f32 `[0,1]` | `[1, 4+C, A]` or `[1, A, 4+C]` (cx,cy,w,h,classes) | YOLOv8 lesion detector            |
| `assets/models/efficientnet_skin_quality.tflite`   | `[1,224,224,3]` f32 ImageNet-norm | `[1, K]` per-head (sigmoid if values escape [0,1]) | EfficientNet-B0 quality       |
| `assets/models/acne_severity_acne04.tflite`        | `[1,224,224,3]` f32 `[0,1]` | `[1, 4]` softmax over Hayashi 0..3 | Legacy ACNE04 classifier              |

The native loaders are tolerant of both channels-first and transposed
YOLO output, and auto-detect whether EfficientNet heads are already
squashed.

## YOLOv8-Nano — training notes

Roboflow has several public acne / skin-lesion datasets that can be
fine-tuned on top of `yolov8n.pt`. Recommended class list (the app
maps these names directly):

```
papule, pustule, cyst, blackhead, whitehead, dark_spot
```

Export to TFLite (float32, NCHW):

```bash
yolo export model=runs/detect/train/weights/best.pt format=tflite imgsz=640
```

Drop the resulting `best_float32.tflite` here as
`yolo_acne_detector.tflite`. Adjust `kDefaultAcneLabels` in
`lib/utils/ai/skin_detections.dart` if your class order differs.

## EfficientNet-B0 — training notes

Use any Keras `EfficientNetB0(weights='imagenet', include_top=False)`
backbone with a small multi-head classifier producing 1–5 outputs
matching this index order:

```
[0] texture   (1 = smooth)
[1] wrinkles  (1 = severe)
[2] pores     (1 = very visible)
[3] elasticity(1 = firm)
[4] overall   (1 = excellent)
```

Convert with `tf.lite.TFLiteConverter.from_keras_model(...)` and save
as `efficientnet_skin_quality.tflite`. The loader handles outputs of
length 1..5 and sigmoid-squashes anything outside `[0,1]`.

## Legacy ACNE04 — MobileNetV2 fallback

Train MobileNetV2 on ACNE04 (Wu et al., 2019 — 1,457 facial photos
labeled Hayashi grades 0–3), export to TFLite with input
`[1,224,224,3]` float32 `[0,1]` and output `[1,4]` softmax. Save here
as `acne_severity_acne04.tflite`. Used only when YOLO isn't bundled.

## Native TFLite runtime requirements

- **Android / iOS / macOS / Linux**: `tflite_flutter` ships the runtime.
- **Windows**: `tensorflowlite_c.dll` must sit next to the built `.exe`.
- **Web**: `tflite_flutter` is unsupported — all three engines skip on
  the web target and the rule engine drives every metric.

## Verifying which engines fired

Run a scan from the Skin AI Analysis screen. The banner reads, e.g.:

```
Powered by ML Kit Face Mesh + YOLOv8-Nano Lesion Detector + EfficientNet-B0 Skin Quality
Backend: TFLite (native) · hybrid · 78% conf
Face Mesh: face covers 41% of frame · L/R symmetry 92%
YOLO: 7 lesions detected (3 papules, 2 pustules, 1 cyst, 1 blackhead)
EfficientNet: overall 64% · texture 58% · wrinkles 12% · pores 36%
```

When a model is missing the corresponding line drops out of the banner
— the user always sees the truth.
