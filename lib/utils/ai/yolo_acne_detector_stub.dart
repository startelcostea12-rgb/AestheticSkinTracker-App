// Stub used on web and platforms without dart:io. YOLO via tflite is
// not supported here; the runner skips this engine cleanly.

import 'yolo_acne_detector.dart';

Future<YoloAcneDetector?> loadYoloAcneDetector() async => null;
