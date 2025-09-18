import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui';

class FaceLandmarker {
  static const _ch = MethodChannel('face_landmarker');
  static bool _loaded = false;

  static Future<void> loadModel(Uint8List taskBytes, {int maxFaces = 5}) async {
    if (_loaded) return;
    await _ch.invokeMethod('loadModel', {
      'task': taskBytes,
      'maxFaces': maxFaces,
    });
    _loaded = true;
  }

  /// returns: List<List<Offset>>  (정규화 0~1 좌표)
  static Future<List<List<Offset>>> detect(Uint8List imageBytes) async {
    final res = await _ch.invokeMethod('detect', {'image': imageBytes});
    final faces = <List<Offset>>[];
    for (final face in (res as List)) {
      final pts = <Offset>[];
      for (final p in (face as List)) {
        pts.add(Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()));
      }
      faces.add(pts);
    }
    return faces;
  }

  static Future<void> close() async {
    const _ch = MethodChannel('face_landmarker');
    await _ch.invokeMethod('close');
  }
}
