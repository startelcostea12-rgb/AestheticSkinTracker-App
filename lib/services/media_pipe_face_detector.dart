import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class FaceLandmark3D {
  const FaceLandmark3D({required this.x, required this.y, required this.z});

  final double x;
  final double y;
  final double z;
}

class MediaPipeFaceDetectorException implements Exception {
  MediaPipeFaceDetectorException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'MediaPipeFaceDetectorException: $message';
}

class MediaPipeFaceDetector {
  MediaPipeFaceDetector({
    this.faceDetectorAsset = 'assets/models/face_detector.tflite',
    this.faceLandmarksAsset = 'assets/models/face_landmarks_detector.tflite',
  });

  final String faceDetectorAsset;
  final String faceLandmarksAsset;

  Interpreter? _faceDetector;
  Interpreter? _faceLandmarks;

  bool _initialized = false;

  int _detectorInputH = 0;
  int _detectorInputW = 0;
  int _landmarkInputH = 0;
  int _landmarkInputW = 0;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await rootBundle.load(faceDetectorAsset);
      await rootBundle.load(faceLandmarksAsset);

      _faceDetector = await Interpreter.fromAsset(faceDetectorAsset);
      _faceLandmarks = await Interpreter.fromAsset(faceLandmarksAsset);

      _detectorInputH = _readInputHeight(_faceDetector!);
      _detectorInputW = _readInputWidth(_faceDetector!);
      _landmarkInputH = _readInputHeight(_faceLandmarks!);
      _landmarkInputW = _readInputWidth(_faceLandmarks!);

      _initialized = true;
    } catch (e) {
      await dispose();
      throw MediaPipeFaceDetectorException(
        'Failed to initialize face detector models.',
        cause: e,
      );
    }
  }

  Future<List<FaceLandmark3D>> detectFromCameraImage(CameraImage cameraImage) async {
    _assertInitialized();

    try {
      final frame = _cameraImageToRgb(cameraImage);
      return _detectFromImage(frame);
    } catch (e) {
      throw MediaPipeFaceDetectorException(
        'Failed to run inference on CameraImage.',
        cause: e,
      );
    }
  }

  Future<List<FaceLandmark3D>> detectFromBytes(Uint8List imageBytes) async {
    _assertInitialized();

    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) {
        throw MediaPipeFaceDetectorException('Could not decode input image bytes.');
      }
      return _detectFromImage(decoded);
    } catch (e) {
      if (e is MediaPipeFaceDetectorException) rethrow;
      throw MediaPipeFaceDetectorException(
        'Failed to run inference on raw image bytes.',
        cause: e,
      );
    }
  }

  Future<void> dispose() async {
    try {
      _faceDetector?.close();
    } catch (_) {}
    try {
      _faceLandmarks?.close();
    } catch (_) {}

    _faceDetector = null;
    _faceLandmarks = null;
    _initialized = false;
  }

  List<FaceLandmark3D> _detectFromImage(img.Image sourceImage) {
    final detector = _faceDetector;
    final landmarks = _faceLandmarks;
    if (detector == null || landmarks == null) {
      throw MediaPipeFaceDetectorException('Models are not initialized.');
    }

    final resizedDetectorImage = img.copyResize(
      sourceImage,
      width: _detectorInputW,
      height: _detectorInputH,
      interpolation: img.Interpolation.linear,
    );

    final detectorInput = _imageToInputTensor(resizedDetectorImage);
    final detectorOutputs = _createOutputMap(detector);
    detector.runForMultipleInputs([detectorInput], detectorOutputs);

    final faceBox = _extractBestFaceBox(
      outputs: detectorOutputs,
      sourceWidth: sourceImage.width,
      sourceHeight: sourceImage.height,
    );

    if (faceBox == null) {
      return const <FaceLandmark3D>[];
    }

    final croppedFace = img.copyCrop(
      sourceImage,
      x: faceBox.left,
      y: faceBox.top,
      width: faceBox.width,
      height: faceBox.height,
    );

    final resizedLandmarkImage = img.copyResize(
      croppedFace,
      width: _landmarkInputW,
      height: _landmarkInputH,
      interpolation: img.Interpolation.linear,
    );

    final landmarkInput = _imageToInputTensor(resizedLandmarkImage);
    final landmarkOutputs = _createOutputMap(landmarks);
    landmarks.runForMultipleInputs([landmarkInput], landmarkOutputs);

    return _extract478Landmarks(
      outputs: landmarkOutputs,
      cropBox: faceBox,
    );
  }

  void _assertInitialized() {
    if (!_initialized) {
      throw MediaPipeFaceDetectorException(
        'MediaPipeFaceDetector is not initialized. Call initialize() first.',
      );
    }
  }

  int _readInputHeight(Interpreter interpreter) {
    final shape = interpreter.getInputTensor(0).shape;
    if (shape.length >= 3) {
      return shape[1];
    }
    throw MediaPipeFaceDetectorException('Unsupported model input shape: $shape');
  }

  int _readInputWidth(Interpreter interpreter) {
    final shape = interpreter.getInputTensor(0).shape;
    if (shape.length >= 3) {
      return shape[2];
    }
    throw MediaPipeFaceDetectorException('Unsupported model input shape: $shape');
  }

  List<List<List<List<double>>>> _imageToInputTensor(img.Image image) {
    final tensor = List.generate(
      1,
      (_) => List.generate(
        image.height,
        (y) => List.generate(image.width, (x) {
          final px = image.getPixel(x, y);
          return <double>[
            px.r / 255.0,
            px.g / 255.0,
            px.b / 255.0,
          ];
        }),
      ),
    );
    return tensor;
  }

  Map<int, Object> _createOutputMap(Interpreter interpreter) {
    final outputs = <int, Object>{};
    for (int i = 0; i < interpreter.getOutputTensors().length; i++) {
      final tensor = interpreter.getOutputTensor(i);
      outputs[i] = _createTensorBuffer(tensor.shape);
    }
    return outputs;
  }

  Object _createTensorBuffer(List<int> shape) {
    if (shape.isEmpty) {
      return <double>[];
    }

    Object build(int dim) {
      final size = shape[dim];
      if (dim == shape.length - 1) {
        return List<double>.filled(size, 0.0, growable: false);
      }
      return List.generate(size, (_) => build(dim + 1), growable: false);
    }

    return build(0);
  }

  _FaceBox? _extractBestFaceBox({
    required Map<int, Object> outputs,
    required int sourceWidth,
    required int sourceHeight,
  }) {
    List<List<double>>? candidateBoxes;
    List<double>? candidateScores;

    for (final value in outputs.values) {
      final flat = _flattenToDoubleList(value);
      if (flat.isEmpty) continue;

      final shape = _inferShape(value);
      if (shape.isEmpty) continue;

      if (shape.last == 4 && shape.length >= 2) {
        final count = flat.length ~/ 4;
        if (count <= 0) continue;

        final boxes = List.generate(count, (i) {
          final o = i * 4;
          return <double>[flat[o], flat[o + 1], flat[o + 2], flat[o + 3]];
        });
        candidateBoxes ??= boxes;
      } else if (shape.last == 1 || shape.length == 2) {
        candidateScores ??= flat;
      }
    }

    if (candidateBoxes == null || candidateBoxes.isEmpty) {
      return null;
    }

    int bestIndex = 0;
    double bestScore = -double.infinity;

    for (int i = 0; i < candidateBoxes.length; i++) {
      final score = (candidateScores != null && i < candidateScores.length)
          ? candidateScores[i]
          : 0.0;
      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }

    final box = candidateBoxes[bestIndex];

    double yMin = box[0];
    double xMin = box[1];
    double yMax = box[2];
    double xMax = box[3];

    if (yMax <= yMin || xMax <= xMin) {
      // Some models emit [x_center, y_center, w, h].
      final xCenter = box[0];
      final yCenter = box[1];
      final w = box[2];
      final h = box[3];
      xMin = xCenter - (w / 2.0);
      xMax = xCenter + (w / 2.0);
      yMin = yCenter - (h / 2.0);
      yMax = yCenter + (h / 2.0);
    }

    xMin = xMin.clamp(0.0, 1.0);
    xMax = xMax.clamp(0.0, 1.0);
    yMin = yMin.clamp(0.0, 1.0);
    yMax = yMax.clamp(0.0, 1.0);

    final left = (xMin * sourceWidth).floor();
    final top = (yMin * sourceHeight).floor();
    final right = (xMax * sourceWidth).ceil();
    final bottom = (yMax * sourceHeight).ceil();

    final clampedLeft = left.clamp(0, math.max(0, sourceWidth - 1));
    final clampedTop = top.clamp(0, math.max(0, sourceHeight - 1));
    final clampedRight = right.clamp(clampedLeft + 1, sourceWidth);
    final clampedBottom = bottom.clamp(clampedTop + 1, sourceHeight);

    final width = clampedRight - clampedLeft;
    final height = clampedBottom - clampedTop;

    if (width <= 1 || height <= 1) return null;

    return _FaceBox(
      left: clampedLeft,
      top: clampedTop,
      width: width,
      height: height,
    );
  }

  List<FaceLandmark3D> _extract478Landmarks({
    required Map<int, Object> outputs,
    required _FaceBox cropBox,
  }) {
    // Pick the largest float output tensor, which is usually the landmark tensor.
    List<double> best = const <double>[];
    for (final value in outputs.values) {
      final flat = _flattenToDoubleList(value);
      if (flat.length > best.length) {
        best = flat;
      }
    }

    if (best.length < 478 * 3) {
      throw MediaPipeFaceDetectorException(
        'Landmark tensor is too small. Expected at least ${478 * 3} floats, got ${best.length}.',
      );
    }

    final points = <FaceLandmark3D>[];
    for (int i = 0; i < 478; i++) {
      final base = i * 3;
      final rawX = best[base];
      final rawY = best[base + 1];
      final rawZ = best[base + 2];

      final x = (rawX >= 0.0 && rawX <= 1.0)
          ? cropBox.left + (rawX * cropBox.width)
          : cropBox.left + rawX;
      final y = (rawY >= 0.0 && rawY <= 1.0)
          ? cropBox.top + (rawY * cropBox.height)
          : cropBox.top + rawY;

      // Keep Z as model-space depth. If normalized, scale to crop width.
      final z = (rawZ >= -1.0 && rawZ <= 1.0) ? rawZ * cropBox.width : rawZ;

      points.add(FaceLandmark3D(x: x.toDouble(), y: y.toDouble(), z: z.toDouble()));
    }

    return points;
  }

  List<double> _flattenToDoubleList(Object value) {
    final out = <double>[];

    void walk(Object node) {
      if (node is List) {
        for (final child in node) {
          walk(child);
        }
        return;
      }
      if (node is num) {
        out.add(node.toDouble());
      }
    }

    walk(value);
    return out;
  }

  List<int> _inferShape(Object value) {
    final shape = <int>[];
    Object? cursor = value;

    while (cursor is List) {
      shape.add(cursor.length);
      if (cursor.isEmpty) break;
      cursor = cursor.first;
    }

    return shape;
  }

  img.Image _cameraImageToRgb(CameraImage image) {
    if (image.format.group == ImageFormatGroup.bgra8888 && image.planes.length == 1) {
      return _bgraToRgb(image);
    }

    if (image.planes.length == 3 && image.format.group == ImageFormatGroup.yuv420) {
      return _yuv420ToRgb(image);
    }

    throw MediaPipeFaceDetectorException(
      'Unsupported CameraImage format: ${image.format.group}.',
    );
  }

  img.Image _bgraToRgb(CameraImage image) {
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final out = img.Image(width: image.width, height: image.height);

    int offset = 0;
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final b = bytes[offset];
        final g = bytes[offset + 1];
        final r = bytes[offset + 2];
        out.setPixelRgb(x, y, r, g, b);
        offset += 4;
      }
    }

    return out;
  }

  img.Image _yuv420ToRgb(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yBytes = yPlane.bytes;
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;

    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;

    final out = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      final yRow = y * yPlane.bytesPerRow;
      final uvRow = (y >> 1) * uvRowStride;

      for (int x = 0; x < width; x++) {
        final yIndex = yRow + x;
        final uvIndex = uvRow + (x >> 1) * uvPixelStride;

        final yValue = yBytes[yIndex] & 0xFF;
        final uValue = uBytes[uvIndex] & 0xFF;
        final vValue = vBytes[uvIndex] & 0xFF;

        final c = yValue - 16;
        final d = uValue - 128;
        final e = vValue - 128;

        int r = ((298 * c + 409 * e + 128) >> 8);
        int g = ((298 * c - 100 * d - 208 * e + 128) >> 8);
        int b = ((298 * c + 516 * d + 128) >> 8);

        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        out.setPixelRgb(x, y, r, g, b);
      }
    }

    return out;
  }
}

class _FaceBox {
  const _FaceBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final int left;
  final int top;
  final int width;
  final int height;
}
