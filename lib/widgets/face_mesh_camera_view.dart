import 'dart:async';
import 'dart:ui' show applyBoxFit;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/media_pipe_face_detector.dart';

class FaceMeshStatusUpdate {
  const FaceMeshStatusUpdate({
    required this.landmarkCount,
    required this.isDetecting,
  });

  final int landmarkCount;
  final bool isDetecting;

  bool get hasFace => landmarkCount > 0;
}

class FaceMeshCameraView extends StatefulWidget {
  const FaceMeshCameraView({
    super.key,
    this.onStatusChanged,
  });

  final ValueChanged<FaceMeshStatusUpdate>? onStatusChanged;

  @override
  State<FaceMeshCameraView> createState() => _FaceMeshCameraViewState();
}

class _FaceMeshCameraViewState extends State<FaceMeshCameraView>
    with WidgetsBindingObserver {
  final MediaPipeFaceDetector _detector = MediaPipeFaceDetector();

  CameraController? _cameraController;
  bool _isInitializing = true;
  bool _isStreaming = false;
  bool _isProcessing = false;
  String? _error;

  List<FaceLandmark3D> _landmarks = const <FaceLandmark3D>[];
  Size? _frameSize;

  void _notifyStatus({required int landmarkCount, required bool isDetecting}) {
    widget.onStatusChanged?.call(
      FaceMeshStatusUpdate(
        landmarkCount: landmarkCount,
        isDetecting: isDetecting,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_teardown());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      unawaited(_stopStream());
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_restartIfNeeded());
    }
  }

  @override
  void didChangeMetrics() {
    if (mounted) {
      setState(() {
        // Repaint overlay after rotation / viewport geometry changes.
      });
    }
  }

  Future<void> _initialize() async {
    setState(() {
      _isInitializing = true;
      _error = null;
    });

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw MediaPipeFaceDetectorException('No cameras available on this device.');
      }

      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();
      await _detector.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      _cameraController = controller;
      await _startStream();

      if (!mounted) return;
      setState(() {
        _isInitializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _error = e.toString();
      });
      _notifyStatus(landmarkCount: 0, isDetecting: false);
    }
  }

  Future<void> _restartIfNeeded() async {
    if (!mounted) return;
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      await _teardown();
      await _initialize();
      return;
    }

    if (!_isStreaming) {
      await _startStream();
    }
  }

  Future<void> _startStream() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized || _isStreaming) {
      return;
    }

    try {
      await controller.startImageStream((CameraImage image) async {
        if (!mounted || _isProcessing) return;

        _isProcessing = true;
        _notifyStatus(landmarkCount: _landmarks.length, isDetecting: true);
        try {
          final points = await _detector.detectFromCameraImage(image);
          if (!mounted) return;

          setState(() {
            _landmarks = points;
            _frameSize = Size(image.width.toDouble(), image.height.toDouble());
          });
          _notifyStatus(landmarkCount: points.length, isDetecting: false);
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _error = e.toString();
          });
          _notifyStatus(landmarkCount: _landmarks.length, isDetecting: false);
        } finally {
          _isProcessing = false;
        }
      });
      _isStreaming = true;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to start camera stream: $e';
      });
      _notifyStatus(landmarkCount: 0, isDetecting: false);
    }
  }

  Future<void> _stopStream() async {
    final controller = _cameraController;
    if (controller == null || !_isStreaming) return;

    try {
      await controller.stopImageStream();
    } catch (_) {
      // Ignore stop stream errors during lifecycle transitions.
    }
    _isStreaming = false;
    _notifyStatus(landmarkCount: _landmarks.length, isDetecting: false);
  }

  Future<void> _teardown() async {
    await _stopStream();
    await _cameraController?.dispose();
    _cameraController = null;
    await _detector.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;

    if (_isInitializing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.redAccent),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: Text('Camera is unavailable.'));
    }

    final isFrontCamera =
        controller.description.lensDirection == CameraLensDirection.front;

    return OrientationBuilder(
      builder: (context, orientation) {
        return LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(controller),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: FaceMeshPainter(
                        landmarks: _landmarks,
                        imageSize: _frameSize,
                        isFrontCamera: isFrontCamera,
                        isPortraitViewport: orientation == Orientation.portrait,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class FaceMeshPainter extends CustomPainter {
  static const int _leftEyeOuter = 33;
  static const int _leftEyeInner = 133;
  static const int _rightEyeOuter = 362;
  static const int _rightEyeInner = 263;

  const FaceMeshPainter({
    required this.landmarks,
    required this.imageSize,
    required this.isFrontCamera,
    required this.isPortraitViewport,
  });

  final List<FaceLandmark3D> landmarks;
  final Size? imageSize;
  final bool isFrontCamera;
  final bool isPortraitViewport;

  @override
  void paint(Canvas canvas, Size size) {
    final srcSize = imageSize;
    if (landmarks.isEmpty || srcSize == null) return;

    final adjusted = _adjustForRotation(landmarks, srcSize, isPortraitViewport);
    final points = adjusted.points;
    final sourceSize = adjusted.sourceSize;

    final fitted = applyBoxFit(BoxFit.cover, sourceSize, size);
    final sourceSubrect = Alignment.center.inscribe(
      fitted.source,
      Offset.zero & sourceSize,
    );
    final destinationSubrect = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );

    final mapped = <Offset>[];
    for (final p in points) {
      final mappedPoint = _mapSourcePointToDestination(
        sourcePoint: Offset(p.x, p.y),
        sourceSubrect: sourceSubrect,
        destinationSubrect: destinationSubrect,
        isFrontCamera: isFrontCamera,
      );
      if (mappedPoint != null) {
        mapped.add(mappedPoint);
      } else {
        mapped.add(const Offset(-1, -1));
      }
    }

    _paintRoiMask(
      canvas,
      mapped,
      destinationSubrect,
    );

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF4FC3F7)
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final mappedPoint = mapped[i];
      if (mappedPoint.dx < 0 || mappedPoint.dy < 0) continue;

      final dx = mappedPoint.dx;
      final dy = mappedPoint.dy;

      final zScale = (p.z.abs() / 120.0).clamp(0.0, 1.0);
      final radius = 1.4 + (1.8 * (1.0 - zScale));

      paint.color = Color.lerp(
            const Color(0xFF4FC3F7),
            const Color(0xFFFFD54F),
            zScale,
          )!
          .withValues(alpha: 0.82);

      canvas.drawCircle(Offset(dx, dy), radius, paint);
    }
  }

  Offset? _mapSourcePointToDestination({
    required Offset sourcePoint,
    required Rect sourceSubrect,
    required Rect destinationSubrect,
    required bool isFrontCamera,
  }) {
    final sx = (sourcePoint.dx - sourceSubrect.left) / sourceSubrect.width;
    final sy = (sourcePoint.dy - sourceSubrect.top) / sourceSubrect.height;
    if (sx.isNaN || sy.isNaN) return null;
    if (sx < 0 || sx > 1 || sy < 0 || sy > 1) return null;

    double dx = destinationSubrect.left + sx * destinationSubrect.width;
    final dy = destinationSubrect.top + sy * destinationSubrect.height;

    if (isFrontCamera) {
      dx = destinationSubrect.left +
          destinationSubrect.width -
          (dx - destinationSubrect.left);
    }

    return Offset(dx, dy);
  }

  void _paintRoiMask(
    Canvas canvas,
    List<Offset> mappedPoints,
    Rect destinationSubrect,
  ) {
    final valid = mappedPoints.where((p) => p.dx >= 0 && p.dy >= 0).toList();
    if (valid.length < 8) return;

    final faceBounds = _boundsForPoints(valid);
    if (faceBounds == null) return;

    final faceOval = Rect.fromCenter(
      center: faceBounds.center,
      width: faceBounds.width * 1.06,
      height: faceBounds.height * 1.08,
    ).intersect(destinationSubrect);
    if (faceOval.isEmpty) return;

    final roiPath = Path()..addOval(faceOval);
    final eyesPath = Path();

    final leftEye = _eyeCircle(mappedPoints, _leftEyeOuter, _leftEyeInner);
    final rightEye = _eyeCircle(mappedPoints, _rightEyeOuter, _rightEyeInner);

    if (leftEye != null) eyesPath.addOval(leftEye);
    if (rightEye != null) eyesPath.addOval(rightEye);

    final roiWithoutEyes = Path.combine(
      PathOperation.difference,
      roiPath,
      eyesPath,
    );

    final maskPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0x334FC3F7);
    canvas.drawPath(roiWithoutEyes, maskPaint);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..color = const Color(0xAA4FC3F7);
    canvas.drawPath(roiWithoutEyes, borderPaint);
  }

  Rect? _boundsForPoints(List<Offset> points) {
    if (points.isEmpty) return null;
    double minX = points.first.dx;
    double minY = points.first.dy;
    double maxX = points.first.dx;
    double maxY = points.first.dy;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Rect? _eyeCircle(List<Offset> points, int a, int b) {
    if (a >= points.length || b >= points.length) return null;
    final p1 = points[a];
    final p2 = points[b];
    if (p1.dx < 0 || p1.dy < 0 || p2.dx < 0 || p2.dy < 0) return null;

    final center = Offset((p1.dx + p2.dx) * 0.5, (p1.dy + p2.dy) * 0.5);
    final eyeSpan = (p2 - p1).distance;
    final radius = eyeSpan * 0.62;
    return Rect.fromCircle(center: center, radius: radius);
  }

  ({List<FaceLandmark3D> points, Size sourceSize}) _adjustForRotation(
    List<FaceLandmark3D> raw,
    Size source,
    bool portrait,
  ) {
    final cameraStreamIsLandscape = source.width > source.height;
    if (!(portrait && cameraStreamIsLandscape)) {
      return (points: raw, sourceSize: source);
    }

    final rotated = <FaceLandmark3D>[];
    for (final p in raw) {
      // 90deg clockwise rotation from sensor space to portrait view space.
      final nx = p.y;
      final ny = source.width - p.x;
      rotated.add(FaceLandmark3D(x: nx, y: ny, z: p.z));
    }

    return (
      points: rotated,
      sourceSize: Size(source.height, source.width),
    );
  }

  @override
  bool shouldRepaint(covariant FaceMeshPainter oldDelegate) {
    return oldDelegate.landmarks != landmarks ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.isFrontCamera != isFrontCamera ||
        oldDelegate.isPortraitViewport != isPortraitViewport;
  }
}
