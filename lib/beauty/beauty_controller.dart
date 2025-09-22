// lib/beauty/beauty_controller.dart
import 'dart:typed_data';
import 'dart:ui';

import 'face_regions.dart';
import 'filters.dart';

class BeautyParams {
  double skinTone;
  double eyeTail;
  double lipSatGain;
  double lipIntensity;
  double hueShift;
  double noseAmount;

  BeautyParams({
    this.skinTone = 0.0,
    this.eyeTail = 0.0,
    this.lipSatGain = 0.25,
    this.lipIntensity = 0.6,
    this.hueShift = 0.0,
    this.noseAmount = 0.0,
  });

  BeautyParams copyWith({
    double? skinTone,
    double? eyeTail,
    double? lipSatGain,
    double? lipIntensity,
    double? hueShift,
    double? noseAmount,
  }) => BeautyParams(
    skinTone: skinTone ?? this.skinTone,
    eyeTail: eyeTail ?? this.eyeTail,
    lipSatGain: lipSatGain ?? this.lipSatGain,
    lipIntensity: lipIntensity ?? this.lipIntensity,
    hueShift: hueShift ?? this.hueShift,
    noseAmount: noseAmount ?? this.noseAmount,
  );
}

class BeautyController {
  Future<Uint8List> applyAll({
    required Uint8List srcPng,
    required List<List<Offset>> faces468,
    required int selectedFace,
    required Size imageSize,
    required BeautyParams params,
    BeautyParams? prevParams, // 이전(패널 열 당시) 값
  }) async {
    final job = _Job(srcPng, faces468, selectedFace, imageSize, params);
    // ❗ 반드시 prev 전달: 누적 보정 방지(Δ만 적용)
    return _apply(job, prev: prevParams);
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

// 중심 기준 스케일 행렬 (Path.addPath(matrix4:)에 넣을 4x4)
Float64List _scaleAbout(Offset c, double sx, double sy) {
  return Float64List.fromList(<double>[
    sx, 0, 0, 0,
    0, sy, 0, 0,
    0, 0, 1, 0,
    c.dx - sx * c.dx, // tx
    c.dy - sy * c.dy, // ty
    0, 1,
  ]);
}

Future<Uint8List> _apply(_Job j, {BeautyParams? prev}) async {
  final width = j.imageSize.width.toInt();
  final height = j.imageSize.height.toInt();

  final ptsImg = j.faces468[j.selectedFace]
      .map((p) => Offset(p.dx * width, p.dy * height))
      .toList();

  // 기본 기하
  double minX = width.toDouble(), minY = height.toDouble(), maxX = 0, maxY = 0;
  for (final p in ptsImg) {
    if (p.dx < minX) minX = p.dx;
    if (p.dy < minY) minY = p.dy;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy > maxY) maxY = p.dy;
  }
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
  final faceCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);
  final faceW = (maxX - minX);
  final faceH = (maxY - minY);

  // ── Δ(변경량) 계산: '이전값'이 없으면 0으로 간주
  final prevP = prev ?? BeautyParams();
  final dSkin = j.params.skinTone - prevP.skinTone;
  final dEye = j.params.eyeTail - prevP.eyeTail;
  final dNose = j.params.noseAmount - prevP.noseAmount;
  final dSat = j.params.lipSatGain - prevP.lipSatGain;
  final dInt = j.params.lipIntensity - prevP.lipIntensity;
  final dHue = j.params.hueShift - prevP.hueShift;

  // 변경이 전혀 없으면 그대로 반환(중복 적용 방지)
  const eps = 1e-4;
  if (dSkin.abs() <= eps &&
      dEye.abs() <= eps &&
      dNose.abs() <= eps &&
      dSat.abs() <= eps &&
      dInt.abs() <= eps &&
      dHue.abs() <= eps) {
    return j.srcPng;
  }

  // ── 1) 마스크 (얼굴 타원 - 입술 - 눈 링) + 이마 보강(forehead cap)
  final faceOvalPath = polyPathFrom(ptsImg, faceOval);
  final lipOuterPath = polyPathFrom(ptsImg, lipsOuter);
  final lipInnerPath = polyPathFrom(ptsImg, lipsInner);
  final lipPath = Path.combine(
    PathOperation.difference,
    lipOuterPath,
    lipInnerPath,
  );

  final leftEyePath = polyPathFrom(ptsImg, leftEyeRing);
  final rightEyePath = polyPathFrom(ptsImg, rightEyeRing);
  final eyesPath = Path()
    ..addPath(leftEyePath, Offset.zero)
    ..addPath(rightEyePath, Offset.zero);

  var skinPath = Path.combine(PathOperation.difference, faceOvalPath, lipPath);
  skinPath = Path.combine(PathOperation.difference, skinPath, eyesPath);

  // ▶ 이마 보강: 타원을 위/세로로 살짝 키운 뒤 상반부만 union
  final expanded = Path()
    ..addPath(
      faceOvalPath,
      Offset.zero,
      matrix4: _scaleAbout(faceCenter, 1.07, 1.12),
    );
  final upperBand = Rect.fromLTWH(
    minX - faceW * 0.10, // 좌우 여유
    minY - faceH * 0.18, // 위로 확장
    faceW * 1.20,
    faceH * 0.58, // 상반부
  );
  final foreheadCap = Path.combine(
    PathOperation.intersect,
    expanded,
    Path()..addRect(upperBand),
  );
  skinPath = Path.combine(PathOperation.union, skinPath, foreheadCap);

  // 래스터화 & 가장자리 보정
  var lipMaskAlpha = await rasterizeMask(j.imageSize, lipPath, feather: 1.2);
  lipMaskAlpha = dilateAlpha(lipMaskAlpha, width, height, 1);
  lipMaskAlpha = blurAlpha(lipMaskAlpha, width, height, 1);

  var skinMaskAlpha = await rasterizeMask(j.imageSize, skinPath, feather: 1.2);
  // 이마 쪽 확보를 위해 팽창 -> 블러 (침식 X)
  skinMaskAlpha = dilateAlpha(skinMaskAlpha, width, height, 2);
  skinMaskAlpha = blurAlpha(skinMaskAlpha, width, height, 1);

  // ── 2) 워프(Δ만 적용) + 마스크 동기 워핑
  Uint8List cur = j.srcPng;

  if (dEye.abs() > 0.001) {
    final et = await eyeTailStretch(
      bytes: cur,
      leftRing: leftEyeRing,
      rightRing: rightEyeRing,
      ptsImg: ptsImg,
      faceCenter: faceCenter,
      amount: dEye, // ✔ 변경량만
      width: width,
      height: height,
      skinMask: skinMaskAlpha,
      lipMask: lipMaskAlpha,
    );
    cur = et.bytes;
    skinMaskAlpha = et.skinMask ?? skinMaskAlpha;
    lipMaskAlpha = et.lipMask ?? lipMaskAlpha;
  }

  Offset _noseCenter() {
    const cands = [1, 2, 4, 5, 197];
    for (final i in cands) {
      if (i >= 0 && i < ptsImg.length) return ptsImg[i];
    }
    return Offset(faceCenter.dx, minY + (maxY - minY) * 0.58);
  }

  final noseC = _noseCenter();
  final noseRadius = faceW * 0.18;

  if (dNose.abs() > 0.001) {
    final rz = await resizeRegionRadial(
      bytes: cur,
      center: noseC,
      radius: noseRadius,
      amount: dNose.clamp(-1.0, 1.0), // ✔ 변경량만
      width: width,
      height: height,
      skinMask: skinMaskAlpha,
      lipMask: lipMaskAlpha,
    );
    cur = rz.bytes;
    skinMaskAlpha = rz.skinMask ?? skinMaskAlpha;
    lipMaskAlpha = rz.lipMask ?? lipMaskAlpha;
  }

  // ── 3) 색 보정(Δ만 적용)
  if (dSkin.abs() > 0.001) {
    cur = await toneUpSkin(
      bytes: cur,
      maskAlpha: skinMaskAlpha,
      width: width,
      height: height,
      amount: dSkin,
    );
  }

  if (dSat.abs() > 0.001 || dHue.abs() > 0.001 || dInt.abs() > 0.001) {
    // NOTE: 립은 완전한 역변환이 불가능하므로, Δ 기반 누적 방식을 사용.
    // satGain/hueShift는 Δ만, intensity는 (prev+dInt)를 상한선으로 사용.
    cur = await tintLips(
      bytes: cur,
      lipMaskAlpha: lipMaskAlpha,
      width: width,
      height: height,
      satGain: dSat,
      hueShiftDeg: dHue,
      intensity: (prevP.lipIntensity + dInt).clamp(0.0, 1.0),
    );
  }

  return cur;
}
