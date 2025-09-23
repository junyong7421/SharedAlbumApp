//beauty_controller.dart

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
  /// (기존) 단일 얼굴 Δ 적용
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

  /// ★ (신규) 여러 명을 한 번에 누적 적용
  /// - 항상 base PNG(`srcPng`)에서 시작해 `paramsByFace`의 **절대값**을
  ///   얼굴 인덱스 오름차순으로 차례대로 누적 반영.
  Future<Uint8List> applyCumulative({
    required Uint8List srcPng,
    required List<List<Offset>> faces468,
    required Size imageSize,
    required Map<int, BeautyParams> paramsByFace,
  }) async {
    Uint8List cur = srcPng;

    // 안정적/일관된 순서를 위해 인덱스 정렬
    final keys = paramsByFace.keys.toList()..sort();

    for (final idx in keys) {
      // 감시: 범위를 벗어나는 얼굴 인덱스는 스킵
      if (idx < 0 || idx >= faces468.length) continue;

      final p = paramsByFace[idx];
      if (p == null) continue;
      if (_isZeroParams(p)) continue; // 완전 0이면 스킵(속도 ↑)

      // prev=0(기준값)으로 두고 '절대값'을 누적 적용
      final job = _Job(cur, faces468, idx, imageSize, p);
      cur = await _apply(job, prev: BeautyParams());
    }
    return cur;
  }

  // 파라미터가 모두 0인지 판정
  bool _isZeroParams(BeautyParams p) {
    const eps = 1e-6;
    return p.skinTone.abs() <= eps &&
        p.eyeTail.abs() <= eps &&
        p.noseAmount.abs() <= eps &&
        p.hueShift.abs() <= eps &&
        p.lipSatGain.abs() <= eps &&
        p.lipIntensity.abs() <= eps;
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

  // ===== 기본 기하 =====
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

  final faceCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);
  final faceW = (maxX - minX), faceH = (maxY - minY);

  // ===== Δ(변경량) =====
  final prevP = prev ?? BeautyParams();
  final dEye = j.params.eyeTail - prevP.eyeTail;
  final dNose = j.params.noseAmount - prevP.noseAmount;
  final dSat = j.params.lipSatGain - prevP.lipSatGain;
  final dInt = j.params.lipIntensity - prevP.lipIntensity;
  final dHue = j.params.hueShift - prevP.hueShift;
  final dSkin = j.params.skinTone - prevP.skinTone; // 0.0 → 진짜 원본

  // ===== 마스크(오벌/입/눈) =====
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

  // 오벌 확장(이마 여유)
  final expandedOval = Path()
    ..addPath(
      faceOvalPath,
      Offset.zero,
      matrix4: _scaleAbout(faceCenter, 1.06, 1.36),
    ); // ★ 1.14 → 1.36

  // (A) 이마 상단 밴드(더 위로/더 두껍게)
  final upperBand = Rect.fromLTWH(
    minX - faceW * 0.05,
    minY - faceH * 0.22, // ★ -0.12 → -0.22
    faceW * 1.10,
    faceH * 0.52, // ★ 0.38 → 0.52
  );
  final foreheadCapA = Path.combine(
    PathOperation.intersect,
    expandedOval,
    Path()..addRect(upperBand),
  );

  // (B) 이마 돔
  Offset _ptSafe(int idx, Offset fb) =>
      (idx >= 0 && idx < ptsImg.length) ? ptsImg[idx] : fb;
  final leftTemple = _ptSafe(
    127,
    Offset(minX + faceW * 0.18, minY + faceH * 0.22),
  );
  final rightTemple = _ptSafe(
    356,
    Offset(maxX - faceW * 0.18, minY + faceH * 0.22),
  );
  final topForehead = _ptSafe(10, Offset(faceCenter.dx, minY + faceH * 0.07));

  final domeThickness = faceH * 0.20; // ★ 0.16 → 0.20
  final domeCtrlLift = faceH * 0.08; // ★ 0.06 → 0.08

  final dome = Path()
    ..moveTo(leftTemple.dx, leftTemple.dy)
    ..quadraticBezierTo(
      topForehead.dx,
      topForehead.dy - domeCtrlLift,
      rightTemple.dx,
      rightTemple.dy,
    )
    ..lineTo(rightTemple.dx, rightTemple.dy + domeThickness)
    ..quadraticBezierTo(
      topForehead.dx,
      minY + faceH * 0.18,
      leftTemple.dx,
      leftTemple.dy + domeThickness,
    )
    ..close();

  // 돔 상한 클립(더 크게)
  final outerClip = Path()
    ..addPath(
      faceOvalPath,
      Offset.zero,
      matrix4: _scaleAbout(faceCenter, 1.10, 1.42),
    ); // ★ 1.28 → 1.42
  final foreheadCapB = Path.combine(PathOperation.intersect, outerClip, dome);

  // ---- 코어 스킨 경로 (입/눈 제외)
  var skinCorePath = Path.combine(
    PathOperation.union,
    faceOvalPath,
    foreheadCapA,
  );
  skinCorePath = Path.combine(PathOperation.union, skinCorePath, foreheadCapB);
  skinCorePath = Path.combine(PathOperation.difference, skinCorePath, lipPath);
  skinCorePath = Path.combine(PathOperation.difference, skinCorePath, eyesPath);

  // ---- 이마 전용 경로 (입/눈 제외)
  var foreheadOnlyPath = Path.combine(
    PathOperation.union,
    foreheadCapA,
    foreheadCapB,
  );
  foreheadOnlyPath = Path.combine(
    PathOperation.difference,
    foreheadOnlyPath,
    lipPath,
  );
  foreheadOnlyPath = Path.combine(
    PathOperation.difference,
    foreheadOnlyPath,
    eyesPath,
  );

  // ===== 래스터화/형태학 =====
  var lipMaskAlpha = await rasterizeMask(j.imageSize, lipPath, feather: 1.2);
  lipMaskAlpha = dilateAlpha(lipMaskAlpha, width, height, 1);
  lipMaskAlpha = blurAlpha(lipMaskAlpha, width, height, 1);

  // 코어: 머리카락 억제. erosion 살짝만(2→1) 후 dilate
  var skinCoreAlpha = await rasterizeMask(
    j.imageSize,
    skinCorePath,
    feather: 1.4,
  );
  skinCoreAlpha = erodeAlpha(skinCoreAlpha, width, height, 1); // ★ 2 → 1
  skinCoreAlpha = dilateAlpha(skinCoreAlpha, width, height, 1);

  // 이마: erosion 없이 확장만
  var foreheadAlpha = await rasterizeMask(
    j.imageSize,
    foreheadOnlyPath,
    feather: 1.8,
  );
  foreheadAlpha = dilateAlpha(foreheadAlpha, width, height, 2);

  // 픽셀별 max 병합 + 경계 스무딩(줄무늬 제거용)
  final merged = Uint8List.fromList(skinCoreAlpha);
  for (int i = 0; i < merged.length; i++) {
    final a = merged[i], b = foreheadAlpha[i];
    merged[i] = a > b ? a : b;
  }
  // ★ 경계 매끈: 살짝 팽창 후 블러
  var skinMaskAlpha = dilateAlpha(merged, width, height, 1);
  skinMaskAlpha = blurAlpha(skinMaskAlpha, width, height, 2); // ★ 1 → 2

  // ===== 워프(Δ만) + 마스크 동기 워핑 =====
  Uint8List cur = j.srcPng;

  if (dEye.abs() > 0.001) {
    final et = await eyeTailStretch(
      bytes: cur,
      leftRing: leftEyeRing,
      rightRing: rightEyeRing,
      ptsImg: ptsImg,
      faceCenter: faceCenter,
      amount: dEye,
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

  if (dNose.abs() > 0.001) {
    final rz = await resizeRegionRadial(
      bytes: cur,
      center: _noseCenter(),
      radius: faceW * 0.18,
      amount: dNose.clamp(-1.0, 1.0),
      width: width,
      height: height,
      skinMask: skinMaskAlpha,
      lipMask: lipMaskAlpha,
    );
    cur = rz.bytes;
    skinMaskAlpha = rz.skinMask ?? skinMaskAlpha;
    lipMaskAlpha = rz.lipMask ?? lipMaskAlpha;
  }

  // ===== 색 보정(Δ만 적용 → 0.0에서 즉시 원본) =====
  if (dSkin.abs() > 1e-4) {
    cur = await toneUpSkin(
      bytes: cur,
      maskAlpha: skinMaskAlpha,
      width: width,
      height: height,
      amount: dSkin,
    );
  }
  if (dSat.abs() > 0.001 || dHue.abs() > 0.001 || dInt.abs() > 0.001) {
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
