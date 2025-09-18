// lib/edit_tools/image_ops.dart
import 'dart:typed_data';
import 'dart:ui'; // Size, Rect
import 'package:flutter/painting.dart' show BoxFit, applyBoxFit; // ⬅️ 추가!
import 'package:image/image.dart' as img;

class ImageOps {
  // stage에 BoxFit.cover로 그려졌다고 가정한 경우, 이미지가 stage 안에서 차지하는 실제 사각형(px)
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

  /// 자르기: stage 사각형 기준으로 선택된 cropRect를 원본 이미지 좌표로 변환해서 crop
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

  /// 밝기 조절: amount -0.5 ~ +0.5 추천 (가산)
  static Uint8List adjustBrightness(Uint8List srcBytes, double amount) {
    final im = img.decodeImage(srcBytes);
    if (im == null) return srcBytes;

    final int delta = (amount * 255).round();
    final out = im.clone();

    int clamp8(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);

    for (int y = 0; y < out.height; y++) {
      for (int x = 0; x < out.width; x++) {
        final p = out.getPixel(x, y); // Pixel (r,g,b,a 는 num)

        final int a = (p.a as num).toInt();
        final int r = clamp8(((p.r as num) + delta).toInt());
        final int g = clamp8(((p.g as num) + delta).toInt());
        final int b = clamp8(((p.b as num) + delta).toInt());

        out.setPixelRgba(x, y, r, g, b, a); // <- int 전달
      }
    }
    return Uint8List.fromList(img.encodePng(out));
  }

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
}
