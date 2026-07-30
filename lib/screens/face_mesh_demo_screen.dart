import 'package:flutter/material.dart';

import '../widgets/face_mesh_camera_view.dart';

class FaceMeshDemoScreen extends StatefulWidget {
  const FaceMeshDemoScreen({super.key});

  static Route<void> route() {
    return MaterialPageRoute<void>(
      builder: (_) => const FaceMeshDemoScreen(),
    );
  }

  @override
  State<FaceMeshDemoScreen> createState() => _FaceMeshDemoScreenState();
}

class _FaceMeshDemoScreenState extends State<FaceMeshDemoScreen> {
  int _landmarkCount = 0;
  bool _isDetecting = false;

  String get _statusText {
    if (_isDetecting) return 'Detecting...';
    if (_landmarkCount > 0) return 'Face detected';
    return 'No face found';
  }

  Color get _statusColor {
    if (_isDetecting) return const Color(0xFF0D47A1);
    if (_landmarkCount > 0) return const Color(0xFF1B5E20);
    return const Color(0xFFB71C1C);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MediaPipe Face Mesh Demo'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          FaceMeshCameraView(
            onStatusChanged: (status) {
              if (!mounted) return;
              setState(() {
                _landmarkCount = status.landmarkCount;
                _isDetecting = status.isDetecting;
              });
            },
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.track_changes, size: 18, color: _statusColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$_landmarkCount points • $_statusText',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
