// lib/edit_tools/image_ops.dart
import 'dart:typed_data';
import 'dart:ui'
    show Size, Rect, BoxFit, applyBoxFit; // ← BoxFit/applyBoxFit 를 ui에서!
import 'package:image/image.dart' as img;
import 'package:flutter/painting.dart' show BoxFit, applyBoxFit;

class ImageOps {
  // ---------- helpers ----------
  static int _clamp8Int(num v) {
    if (v <= 0) return 0;
    if (v >= 255) return 255;
    return v.toInt();
  }

  // stage(BoxFit.cover 가정) 안에서 실제로 이미지가 차지하는 사각형(px)
  static Rect _fittedRect(
    Size stage,
    int iw,
    int ih, {
    BoxFit fit = BoxFit.cover,
  }) {
    final src = Size(iw.toDouble(), ih.toDouble());
    final fitted = applyBoxFit(fit, src, stage).destination;
    final dx = (stage.width - fitted.width) / 2.0;
    final dy = (stage.height - fitted.height) / 2.0;
    return Rect.fromLTWH(dx, dy, fitted.width, fitted.height);
  }

  // ---------- crop ----------
  /// stage 사각형 기준 cropRect를 원본 좌표로 변환하여 crop
  static Uint8List cropFromStageRect({
    required Uint8List srcBytes,
    required Rect stageCropRect,
    required Size stageSize,
    BoxFit fit = BoxFit.cover,
  }) {
    final im = img.decodeImage(srcBytes);
    if (im == null || stageCropRect.isEmpty) return srcBytes;

    final fitted = _fittedRect(stageSize, im.width, im.height, fit: fit);
    final inter = stageCropRect.intersect(fitted);
    if (inter.isEmpty) return srcBytes;

    final nx = ((inter.left - fitted.left) / fitted.width).clamp(0.0, 1.0);
    final ny = ((inter.top - fitted.top) / fitted.height).clamp(0.0, 1.0);
    final nw = (inter.width / fitted.width).clamp(0.0, 1.0);
    final nh = (inter.height / fitted.height).clamp(0.0, 1.0);

    final x = (nx * im.width).round();
    final y = (ny * im.height).round();
    final w = (nw * im.width).round().clamp(1, im.width - x);
    final h = (nh * im.height).round().clamp(1, im.height - y);

    final cropped = img.copyCrop(im, x: x, y: y, width: w, height: h);
    return Uint8List.fromList(img.encodePng(cropped));
  }

  // ---------- brightness ----------
  /// 밝기: amount -0.5~+0.5 권장 (가산)
  static Uint8List adjustBrightness(Uint8List srcBytes, double amount) {
    final im = img.decodeImage(srcBytes);
    if (im == null) return srcBytes;

    final out = im.clone();
    final delta = (amount * 255).round();

    for (int y = 0; y < out.height; y++) {
      for (int x = 0; x < out.width; x++) {
        final p = out.getPixel(x, y); // Pixel
        final r = _clamp8Int(p.r + delta);
        final g = _clamp8Int(p.g + delta);
        final b = _clamp8Int(p.b + delta);
        out.setPixelRgba(x, y, r, g, b, p.a);
      }
    }
    return Uint8List.fromList(img.encodePng(out));
  }

  // 채도 조절: satAmt -1.0 ~ +1.0 (0이면 원본 유지)
  // 채도 조절: satAmt -1.0 ~ +1.0 (0이면 원본 유지)
  static Uint8List adjustSaturation(Uint8List srcBytes, double satAmt) {
    if (satAmt == 0.0) return srcBytes;

    final im = img.decodeImage(srcBytes);
    if (im == null) return srcBytes;

    final out = im.clone();

    for (int y = 0; y < out.height; y++) {
      for (int x = 0; x < out.width; x++) {
        // image 4.x: Pixel.{r,g,b,a}는 num -> int로 변환해서 사용
        final img.Pixel p = out.getPixel(x, y);

        // RGB → HSL (double)
        final (double h, double s0, double l) = _rgbToHsl(
          p.r.toInt(),
          p.g.toInt(),
          p.b.toInt(),
        );

        // 채도 변경
        double s = s0 + (satAmt >= 0 ? (1.0 - s0) * satAmt : s0 * satAmt);
        if (s < 0)
          s = 0;
        else if (s > 1)
          s = 1;

        // HSL → RGB (int)
        final (int r, int g, int b) = _hslToRgb(h, s, l);

        // a도 int 필요
        out.setPixelRgba(x, y, r, g, b, p.a.toInt());
        // 만약 setPixelRgba가 없다면 ↓로 교체
        // out.setPixel(x, y, img.getColor(r, g, b, p.a.toInt()));
      }
    }

    return Uint8List.fromList(img.encodePng(out));
  }

  // ---------- sharpen ----------
  /// 선명도: amount 0.0~1.0 권장 (0=원본). 3x3 샤픈 커널.
  static Uint8List sharpen(Uint8List srcBytes, double amount) {
    if (amount <= 0) return srcBytes;
    final im = img.decodeImage(srcBytes);
    if (im == null) return srcBytes;

    final out = im.clone();
    final w = out.width, h = out.height;

    // 가중치: center 1 + amount*4, side -amount
    final cCenter = 1.0 + amount * 4.0;
    final cSide = -amount;

    // 원본 참조용 복사본
    final src = out.clone();

    int idx(int x, int y) {
      if (x < 0)
        x = 0;
      else if (x >= w)
        x = w - 1;
      if (y < 0)
        y = 0;
      else if (y >= h)
        y = h - 1;
      return y * w + x;
    }

    for (int y0 = 0; y0 < h; y0++) {
      for (int x0 = 0; x0 < w; x0++) {
        final pC = src.getPixel(x0, y0);
        final pL = src.getPixel(x0 - 1 < 0 ? 0 : x0 - 1, y0);
        final pR = src.getPixel(x0 + 1 >= w ? w - 1 : x0 + 1, y0);
        final pT = src.getPixel(x0, y0 - 1 < 0 ? 0 : y0 - 1);
        final pB = src.getPixel(x0, y0 + 1 >= h ? h - 1 : y0 + 1);

        final r = _clamp8Int(
          pC.r * cCenter +
              pL.r * cSide +
              pR.r * cSide +
              pT.r * cSide +
              pB.r * cSide,
        );
        final g = _clamp8Int(
          pC.g * cCenter +
              pL.g * cSide +
              pR.g * cSide +
              pT.g * cSide +
              pB.g * cSide,
        );
        final b = _clamp8Int(
          pC.b * cCenter +
              pL.b * cSide +
              pR.b * cSide +
              pT.b * cSide +
              pB.b * cSide,
        );

        out.setPixelRgba(x0, y0, r, g, b, pC.a);
      }
    }
    return Uint8List.fromList(img.encodePng(out));
  }

  // ---------- rotate/flip ----------
  static Uint8List rotate(Uint8List srcBytes, int degrees) {
    final im = img.decodeImage(srcBytes);
    if (im == null) return srcBytes;
    final rotated = img.copyRotate(im, angle: degrees);
    return Uint8List.fromList(img.encodePng(rotated));
  }

  static Uint8List flipHorizontal(Uint8List srcBytes) {
    final im = img.decodeImage(srcBytes);
    if (im == null) return srcBytes;
    return Uint8List.fromList(img.encodePng(img.flipHorizontal(im)));
  }

  static Uint8List flipVertical(Uint8List srcBytes) {
    final im = img.decodeImage(srcBytes);
    if (im == null) return srcBytes;
    return Uint8List.fromList(img.encodePng(img.flipVertical(im)));
  }

  // ---------- RGB <-> HSL ----------
  // h,s,l ∈ [0,1]
  static (double, double, double) _rgbToHsl(int r, int g, int b) {
    final rf = r / 255.0, gf = g / 255.0, bf = b / 255.0;
    final max = [rf, gf, bf].reduce((a, b) => a > b ? a : b);
    final min = [rf, gf, bf].reduce((a, b) => a < b ? a : b);
    double h = 0, s = 0;
    final l = (max + min) / 2.0;

    final d = max - min;
    if (d != 0) {
      s = l > 0.5 ? d / (2.0 - max - min) : d / (max + min);
      if (max == rf) {
        h = (gf - bf) / d + (gf < bf ? 6 : 0);
      } else if (max == gf) {
        h = (bf - rf) / d + 2;
      } else {
        h = (rf - gf) / d + 4;
      }
      h /= 6.0;
    }
    return (h, s, l);
  }

  static (int, int, int) _hslToRgb(double h, double s, double l) {
    if (s == 0) {
      final v = _clamp8Int(l * 255.0);
      return (v, v, v);
    }

    double hue2rgb(double p, double q, double t) {
      if (t < 0) t += 1;
      if (t > 1) t -= 1;
      if (t < 1 / 6) return p + (q - p) * 6 * t;
      if (t < 1 / 2) return q;
      if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
      return p;
    }

    final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final p = 2 * l - q;

    final r = _clamp8Int(hue2rgb(p, q, h + 1 / 3) * 255.0);
    final g = _clamp8Int(hue2rgb(p, q, h) * 255.0);
    final b = _clamp8Int(hue2rgb(p, q, h - 1 / 3) * 255.0);
    return (r, g, b);
  }
}
