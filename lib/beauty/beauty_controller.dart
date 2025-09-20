import 'dart:typed_data';
import 'dart:ui';

import 'face_regions.dart';
import 'filters.dart';

class BeautyParams {
  double skinStrength; // 0~1
  double eyeAmount; // 0~1
  double lipSatGain; // 0~1
  double lipIntensity; // 0~1
  double hueShift; // deg
  double noseAmount; // -1~+1 (음수=축소, 양수=확대)
  double faceAmount; // -1~+1

  BeautyParams({
    this.skinStrength = 0.35,
    this.eyeAmount = 0.25,
    this.lipSatGain = 0.25,
    this.lipIntensity = 0.6,
    this.hueShift = 0.0,
    this.noseAmount = 0.0,
    this.faceAmount = 0.0,
  });

  BeautyParams copyWith({
    double? skinStrength,
    double? eyeAmount,
    double? lipSatGain,
    double? lipIntensity,
    double? hueShift,
    double? noseAmount,
    double? faceAmount,
  }) => BeautyParams(
    skinStrength: skinStrength ?? this.skinStrength,
    eyeAmount: eyeAmount ?? this.eyeAmount,
    lipSatGain: lipSatGain ?? this.lipSatGain,
    lipIntensity: lipIntensity ?? this.lipIntensity,
    hueShift: hueShift ?? this.hueShift,
    noseAmount: noseAmount ?? this.noseAmount,
    faceAmount: faceAmount ?? this.faceAmount,
  );
}

class BeautyController {
  Future<Uint8List> applyAll({
    required Uint8List srcPng,
    required List<List<Offset>> faces468,
    required int selectedFace,
    required Size imageSize,
    required BeautyParams params,
  }) async {
    final job = _Job(srcPng, faces468, selectedFace, imageSize, params);
    return _apply(job);
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

Future<Uint8List> _apply(_Job j) async {
  final width = j.imageSize.width.toInt();
  final height = j.imageSize.height.toInt();

  // 1) 선택 얼굴의 이미지 좌표
  final ptsImg = j.faces468[j.selectedFace]
      .map((p) => Offset(p.dx * width, p.dy * height))
      .toList();

  // 2) 입술/피부 마스크
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

  // 3) 편의 포인트들
  Offset _center(List<int> idx) {
    double sx = 0, sy = 0;
    for (final i in idx) {
      sx += ptsImg[i].dx;
      sy += ptsImg[i].dy;
    }
    return Offset(sx / idx.length, sy / idx.length);
  }

  // 눈
  final lc = _center(leftEyeRing);
  final rc = _center(rightEyeRing);
  final eyeRadius = ((maxX - minX) * 0.10).clamp(12, 48).toDouble();

  // 얼굴 중심/반경
  final faceCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);
  final faceRadius = (maxX - minX) * 0.55; // bbox보다 살짝 크게

  // 코 중심(대부분 FaceMesh 1번이 코팁)
  Offset _noseCenter() {
    const candidates = [1, 2, 4, 5, 197];
    for (final i in candidates) {
      if (i >= 0 && i < ptsImg.length) return ptsImg[i];
    }
    return Offset(faceCenter.dx, minY + (maxY - minY) * 0.58);
  }

  final noseC = _noseCenter();
  final noseRadius = (maxX - minX) * 0.18;

  // 4) 필터 적용
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
    radius: eyeRadius,
    amount: j.params.eyeAmount,
    width: width,
    height: height,
  );

  // 코 크기 (음수=축소, 양수=확대)
  if (j.params.noseAmount.abs() > 0.001) {
    cur = await resizeRegionRadial(
      bytes: cur,
      center: noseC,
      radius: noseRadius,
      amount: j.params.noseAmount.clamp(-1.0, 1.0),
      width: width,
      height: height,
    );
  }

  // 얼굴 전체 크기 (틀 포함)
  // ✅ 얼굴 전체 크기(자연스러운 와핑)
  if (j.params.faceAmount.abs() > 0.001) {
    cur = await resizeRegionRadial(
      bytes: cur,
      center: faceCenter,
      radius: faceRadius,
      amount: j.params.faceAmount.clamp(-1.0, 1.0),
      width: width,
      height: height,
    );
  }

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
