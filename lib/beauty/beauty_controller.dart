// lib/beauty/beauty_controller.dart
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'face_regions.dart';
import 'filters.dart';

class BeautyParams {
  double skinStrength; // 0~1
  double eyeAmount; // 0~1
  double lipSatGain; // 0~1
  double lipIntensity; // 0~1
  double hueShift; // deg

  BeautyParams({
    this.skinStrength = 0.35,
    this.eyeAmount = 0.25,
    this.lipSatGain = 0.25,
    this.lipIntensity = 0.6,
    this.hueShift = 0,
  });

  BeautyParams copyWith({
    double? skinStrength,
    double? eyeAmount,
    double? lipSatGain,
    double? lipIntensity,
    double? hueShift,
  }) => BeautyParams(
    skinStrength: skinStrength ?? this.skinStrength,
    eyeAmount: eyeAmount ?? this.eyeAmount,
    lipSatGain: lipSatGain ?? this.lipSatGain,
    lipIntensity: lipIntensity ?? this.lipIntensity,
    hueShift: hueShift ?? this.hueShift,
  );
}

// (선택) import 'package:flutter/foundation.dart'; // compute 안 쓰면 없어도 됨

class BeautyController {
  /// 메인 Isolate에서 바로 적용 (간단/안정)
  Future<Uint8List> applyAll({
    required Uint8List srcPng,
    required List<List<Offset>> faces468,
    required int selectedFace,
    required Size imageSize,
    required BeautyParams params,
  }) async {
    final job = _Job(srcPng, faces468, selectedFace, imageSize, params);
    return _apply(job); // ← compute 대신 직접 호출
  }
}

class _Job {
  final Uint8List srcPng;
  final List<List<Offset>> faces468;
  final int selectedFace;
  final Size imageSize;
  final BeautyParams params;
  _Job(
    this.srcPng,
    this.faces468,
    this.selectedFace,
    this.imageSize,
    this.params,
  );
}

// 이름만 바꿔서 내부 호출
Future<Uint8List> _apply(_Job j) async {
  final width = j.imageSize.width.toInt();
  final height = j.imageSize.height.toInt();

  // 1) 좌표 변환
  final ptsImg = j.faces468[j.selectedFace]
      .map((p) => Offset(p.dx * width, p.dy * height))
      .toList();

  // 2) 마스크들 만들기 (지금 로직 그대로)
  final lipPath = polyPathFrom(ptsImg, lipsOuter);

  double minX = width.toDouble(), minY = height.toDouble(), maxX = 0, maxY = 0;
  for (final p in ptsImg) {
    if (p.dx < minX) minX = p.dx;
    if (p.dy < minY) minY = p.dy;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy > maxY) maxY = p.dy;
  }
  final faceRectPath = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(minX - 10, minY - 10, maxX + 10, maxY + 10),
        const Radius.circular(20),
      ),
    );
  final lipPathInv = Path.combine(
    PathOperation.difference,
    faceRectPath,
    lipPath,
  );

  final lipMask = await rasterizeMask(j.imageSize, lipPath, feather: 2);
  final skinMask = await rasterizeMask(j.imageSize, lipPathInv, feather: 4);

  // 3) 눈 중심
  Offset _center(List<int> idx) {
    double sx = 0, sy = 0;
    for (final i in idx) {
      sx += ptsImg[i].dx;
      sy += ptsImg[i].dy;
    }
    return Offset(sx / idx.length, sy / idx.length);
  }

  final lc = _center(leftEyeRing);
  final rc = _center(rightEyeRing);
  final eyeRadius = ((maxX - minX) * 0.1).clamp(12, 48);

  // 4) 필터들 적용 (이미 작성한 filters.dart 사용)
  var cur = await smoothSkin(
    bytes: j.srcPng,
    maskAlpha: skinMask,
    width: width,
    height: height,
    strength: j.params.skinStrength,
  );

  cur = await enlargeEyes(
    bytes: cur,
    leftCenter: lc,
    rightCenter: rc,
    radius: eyeRadius.toDouble(),
    amount: j.params.eyeAmount,
    width: width,
    height: height,
  );

  cur = await tintLips(
    bytes: cur,
    lipMaskAlpha: lipMask,
    width: width,
    height: height,
    satGain: j.params.lipSatGain,
    hueShiftDeg: j.params.hueShift,
    intensity: j.params.lipIntensity,
  );

  return cur;
}
