// Stub used on web and any platform without dart:io.
// ML Kit Face Mesh has no web implementation; we just pass the bytes
// through with a clear "not run on this platform" reason.

import 'dart:typed_data';

import 'face_mesh_service.dart';

Future<FaceMeshResult> runFaceMesh(Uint8List bytes) async {
  return FaceMeshResult.passthrough(
    bytes,
    'ML Kit Face Mesh not available on this platform',
  );
}
