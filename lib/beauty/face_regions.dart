// lib/beauty/face_regions.dart
import 'dart:ui';

/// MediaPipe FaceMesh - 자주 쓰는 영역 (대표 인덱스)
/// 정확한 인덱스는 모델 버전마다 소폭 다를 수 있지만, 아래는 많이 쓰는 관용 세트입니다.
/// 필요하면 나중에 미세 조정 가능.
const leftEyeRing = [33, 246, 161, 160, 159, 158, 157, 173];
const rightEyeRing = [362, 398, 384, 385, 386, 387, 388, 466];

const lipsOuter = [
  61,
  146,
  91,
  181,
  84,
  17,
  314,
  405,
  321,
  375,
  291,
  308,
  324,
  318,
  402,
  317,
  14,
  87,
  178,
  88,
  95,
  185,
  40,
  39,
  37,
  0,
  267,
  269,
  270,
  409,
  415,
  310,
  311,
  312,
  13,
  82,
];

/// 랜드마크(정규화 0~1) → 이미지 좌표로 변환
List<Offset> toImagePoints(List<Offset> norm, Size imgSize) => norm
    .map((p) => Offset(p.dx * imgSize.width, p.dy * imgSize.height))
    .toList();

/// index 모음으로 다각형 Path 만들기
Path polyPathFrom(List<Offset> imgPoints, List<int> indices) {
  final p = Path();
  if (indices.isEmpty) return p;
  p.moveTo(imgPoints[indices.first].dx, imgPoints[indices.first].dy);
  for (int i = 1; i < indices.length; i++) {
    final pt = imgPoints[indices[i]];
    p.lineTo(pt.dx, pt.dy);
  }
  p.close();
  return p;
}
