// lib/beauty/filters.dart
import 'dart:typed_data';
import 'dart:ui' as ui show Size, Path, Offset;
import 'package:image/image.dart' as img;

/// (임시) Path -> 알파(0~255) 버퍼
Future<Uint8List> rasterizeMask(
  ui.Size size,
  ui.Path mask, {
  double feather = 3,
}) async {
  final w = size.width.toInt();
  final h = size.height.toInt();
  final out = Uint8List(w * h);
  out.fillRange(0, out.length, 255); // 전부 255
  return out;
}

/// 피부 보정: 블러 이미지를 마스크 알파로 블렌딩
Future<Uint8List> smoothSkin({
  required Uint8List bytes,
  required Uint8List maskAlpha, // 0~255
  required int width,
  required int height,
  double strength = 0.4, // 0~1
}) async {
  final src = img.decodeImage(bytes);
  if (src == null) return bytes;

  // image v4: named parameter
  final int radius = ((strength * 6).clamp(1.0, 12.0)).round();
  final blurred = img.gaussianBlur(src.clone(), radius: radius);
  final out = src.clone();

  int idx = 0;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++, idx++) {
      final a = (maskAlpha[idx] / 255.0) * strength; // 블렌딩 계수(0~strength)
      if (a <= 0) continue;

      // v4: Pixel 객체 사용
      final p0 = out.getPixel(x, y); // 원본 픽셀 (Pixel)
      final p1 = blurred.getPixel(x, y); // 블러 픽셀 (Pixel)

      final r = ((1 - a) * p0.r + a * p1.r).round();
      final g = ((1 - a) * p0.g + a * p1.g).round();
      final b = ((1 - a) * p0.b + a * p1.b).round();

      out.setPixelRgba(x, y, r, g, b, p0.a); // 알파는 원본 유지
    }
  }

  return Uint8List.fromList(img.encodePng(out));
}

/// 눈 키우기 (스텁)
Future<Uint8List> enlargeEyes({
  required Uint8List bytes,
  required ui.Offset leftCenter,
  required ui.Offset rightCenter,
  required double radius,
  required double amount, // 0~1
  required int width,
  required int height,
}) async {
  // TODO: 와핑 구현 예정
  return bytes;
}

/// 립 색 보정 (스텁)
Future<Uint8List> tintLips({
  required Uint8List bytes,
  required Uint8List lipMaskAlpha,
  required int width,
  required int height,
  double satGain = 0.2,
  double hueShiftDeg = 0.0,
  double intensity = 0.6,
}) async {
  // TODO: HSL 변환 후 lipMaskAlpha로 블렌딩
  return bytes;
}
