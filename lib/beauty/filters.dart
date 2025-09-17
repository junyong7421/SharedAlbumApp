// lib/beauty/filters.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Path → 알파(0~255) 버퍼
Future<Uint8List> rasterizeMask(
  ui.Size size,
  ui.Path mask, {
  double feather = 3,
}) async {
  final w = size.width.toInt();
  final h = size.height.toInt();

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final rect = ui.Rect.fromLTWH(0, 0, size.width, size.height);

  // 배경 투명
  canvas.drawRect(rect, ui.Paint()..color = const ui.Color(0x00000000));

  // 마스크(흰색 채움 + feather blur)
  final paint = ui.Paint()
    ..color = const ui.Color(0xffffffff)
    ..style = ui.PaintingStyle.fill
    ..isAntiAlias = true;
  if (feather > 0) {
    paint.maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, feather);
  }
  canvas.drawPath(mask, paint);

  final picture = recorder.endRecording();
  final uiImage = await picture.toImage(w, h);
  final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (byteData == null) return Uint8List(w * h);

  // RGBA → A만 추출
  final rgba = byteData.buffer.asUint8List();
  final alpha = Uint8List(w * h);
  for (int i = 0, src = 3; i < alpha.length; i++, src += 4) {
    alpha[i] = rgba[src];
  }
  return alpha;
}

/// 피부 보정(블러 + 마스크 블렌딩)
Future<Uint8List> smoothSkin({
  required Uint8List bytes,
  required Uint8List maskAlpha,
  required int width,
  required int height,
  double strength = 0.4,
}) async {
  final src = img.decodeImage(bytes);
  if (src == null) return bytes;

  final radius = ((strength * 6).clamp(1.0, 12.0)).round();
  final blurred = img.gaussianBlur(src.clone(), radius: radius);
  final out = src.clone();

  int idx = 0;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++, idx++) {
      final a = (maskAlpha[idx] / 255.0) * strength;
      if (a <= 0) continue;

      final p0 = out.getPixel(x, y);
      final p1 = blurred.getPixel(x, y);

      final r = ((1 - a) * p0.r + a * p1.r).round();
      final g = ((1 - a) * p0.g + a * p1.g).round();
      final b = ((1 - a) * p0.b + a * p1.b).round();
      out.setPixelRgba(x, y, r, g, b, p0.a);
    }
  }
  return Uint8List.fromList(img.encodePng(out));
}

/// 눈 확대(국소 와핑)
Future<Uint8List> enlargeEyes({
  required Uint8List bytes,
  required ui.Offset leftCenter,
  required ui.Offset rightCenter,
  required double radius,
  required double amount, // 0~1
  required int width,
  required int height,
}) async {
  if (amount <= 0) return bytes;

  final src = img.decodeImage(bytes);
  if (src == null) return bytes;
  final out = src.clone();

  final r = radius;
  final r2 = r * r;

  double scaleFor(double d) {
    final t = (1 - (d / r)).clamp(0.0, 1.0);
    return 1.0 + amount * (t * t);
  }

  img.Pixel _get(img.Image im, int x, int y) =>
      im.getPixel(x.clamp(0, width - 1), y.clamp(0, height - 1));

  void warpAt(ui.Offset c) {
    final cx = c.dx;
    final cy = c.dy;
    for (int y = (cy - r).floor(); y <= (cy + r).ceil(); y++) {
      if (y < 0 || y >= height) continue;
      for (int x = (cx - r).floor(); x <= (cx + r).ceil(); x++) {
        if (x < 0 || x >= width) continue;

        final dx = x - cx;
        final dy = y - cy;
        final dist2 = dx * dx + dy * dy;
        if (dist2 > r2) continue;

        final dist = math.sqrt(dist2);
        final s = scaleFor(dist);
        final srcX = (cx + dx / s).round();
        final srcY = (cy + dy / s).round();

        final p = _get(src, srcX, srcY);
        out.setPixelRgba(x, y, p.r, p.g, p.b, p.a);
      }
    }
  }

  warpAt(leftCenter);
  warpAt(rightCenter);

  return Uint8List.fromList(img.encodePng(out));
}

/// 코 등 국소 크기 조절(반경형)
Future<Uint8List> resizeRegionRadial({
  required Uint8List bytes,
  required ui.Offset center,
  required double radius,
  required double amount, // -1.0 ~ +1.0
  required int width,
  required int height,
}) async {
  if (amount.abs() <= 0) return bytes;

  final src = img.decodeImage(bytes);
  if (src == null) return bytes;

  final out = src.clone();
  final r = radius.clamp(4.0, math.min(width, height) * 0.8);
  final r2 = r * r;

  double scaleFor(double d) {
    final t = (1 - (d / r)).clamp(0.0, 1.0);
    return 1.0 + amount * (t * t);
  }

  img.Pixel _get(img.Image im, int x, int y) =>
      im.getPixel(x.clamp(0, width - 1), y.clamp(0, height - 1));

  final cx = center.dx;
  final cy = center.dy;

  for (int y = (cy - r).floor(); y <= (cy + r).ceil(); y++) {
    if (y < 0 || y >= height) continue;
    for (int x = (cx - r).floor(); x <= (cx + r).ceil(); x++) {
      if (x < 0 || x >= width) continue;

      final dx = x - cx;
      final dy = y - cy;
      final dist2 = dx * dx + dy * dy;
      if (dist2 > r2) continue;

      final dist = math.sqrt(dist2);
      final s = scaleFor(dist);
      final srcX = (cx + dx / s).round();
      final srcY = (cy + dy / s).round();

      final p = _get(src, srcX, srcY);
      out.setPixelRgba(x, y, p.r, p.g, p.b, p.a);
    }
  }

  return Uint8List.fromList(img.encodePng(out));
}

/// 얼굴 박스(틀 포함) 전체 스케일
Future<Uint8List> resizeFaceBox({
  required Uint8List bytes,
  required int width,
  required int height,
  required double minX,
  required double minY,
  required double maxX,
  required double maxY,
  required double amount, // -1.0 ~ +1.0
}) async {
  if (amount.abs() <= 0.001) return bytes;

  final src = img.decodeImage(bytes);
  if (src == null) return bytes;

  final out = src.clone();

  final faceW = (maxX - minX).toInt();
  final faceH = (maxY - minY).toInt();
  if (faceW <= 0 || faceH <= 0) return bytes;

  // 1) crop  (v4.1.0: named)
  final crop = img.copyCrop(
    src,
    x: minX.toInt(),
    y: minY.toInt(),
    width: faceW,
    height: faceH,
  );

  // 2) resize (v4.1.0: 첫 인자 named `image`)
  final scale = (1.0 + amount).clamp(0.2, 2.5);
  final newW = (faceW * scale).clamp(1, width).toInt();
  final newH = (faceH * scale).clamp(1, height).toInt();

  final resized = img.copyResize(
    crop,
    width: newW,
    height: newH,
    interpolation: img.Interpolation.cubic,
  );

  // 3) composite (blend는 생략해 호환성 확보)
  final cx = ((minX + maxX) / 2).round();
  final cy = ((minY + maxY) / 2).round();
  final drawX = (cx - newW ~/ 2).clamp(0, width - newW);
  final drawY = (cy - newH ~/ 2).clamp(0, height - newH);

  img.compositeImage(
    out,
    resized,
    dstX: drawX,
    dstY: drawY,
    // blend: 기본값 사용 (버전별 enum 차이 회피)
  );

  return Uint8List.fromList(img.encodePng(out));
}

/// 립 색 보정
Future<Uint8List> tintLips({
  required Uint8List bytes,
  required Uint8List lipMaskAlpha,
  required int width,
  required int height,
  double satGain = 0.2,
  double hueShiftDeg = 0.0,
  double intensity = 0.6,
}) async {
  final src = img.decodeImage(bytes);
  if (src == null) return bytes;

  final out = src.clone();
  int idx = 0;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++, idx++) {
      final mask = lipMaskAlpha[idx] / 255.0;
      if (mask <= 0) continue;

      final p = out.getPixel(x, y);
      double r = p.r / 255.0, g = p.g / 255.0, b = p.b / 255.0;

      final hsl = _rgbToHsl(r, g, b);
      double h = hsl[0], s = hsl[1], l = hsl[2];

      s = (s * (1.0 + satGain)).clamp(0.0, 1.0);
      h = (h + hueShiftDeg / 360.0) % 1.0;

      final rgb = _hslToRgb(h, s, l);
      final rr = (rgb[0] * 255).round();
      final gg = (rgb[1] * 255).round();
      final bb = (rgb[2] * 255).round();

      final a = (mask * intensity).clamp(0.0, 1.0);
      final fr = ((1 - a) * p.r + a * rr).round();
      final fg = ((1 - a) * p.g + a * gg).round();
      final fb = ((1 - a) * p.b + a * bb).round();

      out.setPixelRgba(x, y, fr, fg, fb, p.a);
    }
  }
  return Uint8List.fromList(img.encodePng(out));
}

// ===== HSL helpers =====
List<double> _rgbToHsl(double r, double g, double b) {
  final max = [r, g, b].reduce((a, b) => a > b ? a : b);
  final min = [r, g, b].reduce((a, b) => a < b ? a : b);
  double h = 0, s = 0;
  final l = (max + min) / 2.0;

  if (max != min) {
    final d = max - min;
    s = l > 0.5 ? d / (2.0 - max - min) : d / (max + min);
    if (max == r) {
      h = ((g - b) / d + (g < b ? 6 : 0)) / 6.0;
    } else if (max == g) {
      h = ((b - r) / d + 2) / 6.0;
    } else {
      h = ((r - g) / d + 4) / 6.0;
    }
  }
  return [h, s, l];
}

double _hue2rgb(double p, double q, double t) {
  if (t < 0) t += 1;
  if (t > 1) t -= 1;
  if (t < 1 / 6) return p + (q - p) * 6 * t;
  if (t < 1 / 2) return q;
  if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
  return p;
}

List<double> _hslToRgb(double h, double s, double l) {
  double r, g, b;
  if (s == 0) {
    r = g = b = l;
  } else {
    final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final p = 2 * l - q;
    r = _hue2rgb(p, q, h + 1 / 3);
    g = _hue2rgb(p, q, h);
    b = _hue2rgb(p, q, h - 1 / 3);
  }
  return [r, g, b];
}
