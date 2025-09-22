import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:image/image.dart' as img;

// ---------- 공용 유틸 ----------

double _smoothstep(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _softInRange(double x, double min, double max, double feather) {
  if (x <= min - feather) return 0.0;
  if (x >= max + feather) return 0.0;
  if (x < min) return _smoothstep(min - feather, min, x); // 0→1
  if (x > max) return 1.0 - _smoothstep(max, max + feather, x); // 1→0
  return 1.0;
}

// 가장자리 안전 접근
img.Pixel _getClamped(img.Image im, int x, int y) =>
    im.getPixel(x.clamp(0, im.width - 1), y.clamp(0, im.height - 1));

/// 양선형 보간 → [r,g,b,a] (0~255)
List<int> _sampleBilinearRgba(img.Image im, double fx, double fy) {
  final x0 = fx.floor();
  final y0 = fy.floor();
  final x1 = x0 + 1;
  final y1 = y0 + 1;

  final tx = fx - x0;
  final ty = fy - y0;

  final p00 = _getClamped(im, x0, y0);
  final p10 = _getClamped(im, x1, y0);
  final p01 = _getClamped(im, x0, y1);
  final p11 = _getClamped(im, x1, y1);

  int _lerpNum(num a, num b, double t) => (a + (b - a) * t).round();

  final r0 = _lerpNum(p00.r, p10.r, tx);
  final g0 = _lerpNum(p00.g, p10.g, tx);
  final b0 = _lerpNum(p00.b, p10.b, tx);
  final a0 = _lerpNum(p00.a, p10.a, tx);

  final r1 = _lerpNum(p01.r, p11.r, tx);
  final g1 = _lerpNum(p01.g, p11.g, tx);
  final b1 = _lerpNum(p01.b, p11.b, tx);
  final a1 = _lerpNum(p01.a, p11.a, tx);

  final r = _lerpNum(r0, r1, ty).clamp(0, 255) as int;
  final g = _lerpNum(g0, g1, ty).clamp(0, 255) as int;
  final b = _lerpNum(b0, b1, ty).clamp(0, 255) as int;
  final a = _lerpNum(a0, a1, ty).clamp(0, 255) as int;
  return [r, g, b, a];
}

// ---------- 마스크/알파 유틸 ----------

/// Path → alpha(0~255) 버퍼
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

  // 마스크
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

// 팽창(두껍게)
Uint8List dilateAlpha(Uint8List a, int w, int h, int radius) {
  if (radius <= 0) return a;
  var out = Uint8List.fromList(a);
  for (int r = 0; r < radius; r++) {
    final src = Uint8List.fromList(out);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int maxv = 0;
        for (int yy = y - 1; yy <= y + 1; yy++) {
          if (yy < 0 || yy >= h) continue;
          final row = yy * w;
          for (int xx = x - 1; xx <= x + 1; xx++) {
            if (xx < 0 || xx >= w) continue;
            final v = src[row + xx];
            if (v > maxv) maxv = v;
          }
        }
        out[y * w + x] = maxv;
      }
    }
  }
  return out;
}

// 침식(안쪽으로)
Uint8List erodeAlpha(Uint8List a, int w, int h, int radius) {
  if (radius <= 0) return a;
  var out = Uint8List.fromList(a);
  for (int r = 0; r < radius; r++) {
    final src = Uint8List.fromList(out);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int minv = 255;
        for (int yy = y - 1; yy <= y + 1; yy++) {
          if (yy < 0 || yy >= h) continue;
          final row = yy * w;
          for (int xx = x - 1; xx <= x + 1; xx++) {
            if (xx < 0 || xx >= w) continue;
            final v = src[row + xx];
            if (v < minv) minv = v;
          }
        }
        out[y * w + x] = minv;
      }
    }
  }
  return out;
}

// 박스 블러(부드럽게)
Uint8List blurAlpha(Uint8List a, int w, int h, int radius) {
  if (radius <= 0) return a;
  var out = Uint8List.fromList(a);
  for (int r = 0; r < radius; r++) {
    final src = Uint8List.fromList(out);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int sum = 0, cnt = 0;
        for (int yy = y - 1; yy <= y + 1; yy++) {
          if (yy < 0 || yy >= h) continue;
          final row = yy * w;
          for (int xx = x - 1; xx <= x + 1; xx++) {
            if (xx < 0 || xx >= w) continue;
            sum += src[row + xx];
            cnt++;
          }
        }
        out[y * w + x] = (sum ~/ cnt);
      }
    }
  }
  return out;
}

// ---------- 피부 톤업(블러 X) ----------
Future<Uint8List> toneUpSkin({
  required Uint8List bytes,
  required Uint8List maskAlpha,
  required int width,
  required int height,
  double amount = 0.0, // -1~+1
}) async {
  if (amount.abs() <= 0.001) return bytes;

  final src = img.decodeImage(bytes);
  if (src == null) return bytes;

  final out = src.clone();

  // 대칭 계수 (가산형) — 필요시 미세 조정
  const double kL = 0.22; // Lightness 변화량
  const double kS = -0.08; // Saturation 변화량(밝게: 살짝 감소, 어둡게: 살짝 증가)

  int idx = 0;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++, idx++) {
      final m = maskAlpha[idx] / 255.0;
      if (m <= 0) {
        // 마스크 밖은 그대로 복사
        final p = src.getPixel(x, y);
        out.setPixelRgba(x, y, p.r, p.g, p.b, p.a);
        continue;
      }

      final p = src.getPixel(x, y);
      double r = p.r / 255.0, g = p.g / 255.0, b = p.b / 255.0;

      // RGB → HSL
      final hsl = _rgbToHsl(r, g, b);
      double h = hsl[0], s = hsl[1], l = hsl[2];

      // ★ 가산형/대칭 보정 (마스크 강도로 스케일)
      final dl = kL * amount * m;
      final ds = kS * amount * m;

      l = (l + dl).clamp(0.0, 1.0);
      s = (s + ds).clamp(0.0, 1.0);

      // HSL → RGB
      final rgb = _hslToRgb(h, s, l);
      final rr = (rgb[0] * 255).round();
      final gg = (rgb[1] * 255).round();
      final bb = (rgb[2] * 255).round();

      // 블렌딩 없이 바로 기록(가산형이므로 누적/되돌리기 정확)
      out.setPixelRgba(x, y, rr, gg, bb, p.a);
    }
  }
  return Uint8List.fromList(img.encodePng(out));
}

// ---------- 뒤트임(눈꼬리 드래그) ----------

void _dragGaussian({
  required img.Image src,
  required img.Image out,
  required double cx,
  required double cy,
  required double vx,
  required double vy,
  required double sigmaX,
  required double sigmaY,
  double holeCx = double.nan,
  double holeCy = double.nan,
  double holeSigma = 0.0,
}) {
  final w = src.width, h = src.height;
  final sx2 = sigmaX * sigmaX;
  final sy2 = sigmaY * sigmaY;
  final holeOn = holeSigma > 0 && !holeCx.isNaN && !holeCy.isNaN;
  final hs2 = holeSigma * holeSigma;

  final minx = math.max(0, (cx - sigmaX * 3).floor());
  final maxx = math.min(w - 1, (cx + sigmaX * 3).ceil());
  final miny = math.max(0, (cy - sigmaY * 3).floor());
  final maxy = math.min(h - 1, (cy + sigmaY * 3).ceil());

  for (int y = miny; y <= maxy; y++) {
    for (int x = minx; x <= maxx; x++) {
      final dx = x - cx;
      final dy = y - cy;
      final g = math.exp(-0.5 * ((dx * dx) / sx2 + (dy * dy) / sy2));

      double protect = 0.0;
      if (holeOn) {
        final hx = x - holeCx, hy = y - holeCy;
        protect = math.exp(-0.5 * (hx * hx + hy * hy) / hs2);
      }
      final wgt = (g * (1.0 - protect)).clamp(0.0, 1.0);
      if (wgt <= 0) continue;

      final sxp = x - vx * wgt;
      final syp = y - vy * wgt;

      final c = _sampleBilinearRgba(src, sxp, syp);
      out.setPixelRgba(x, y, c[0], c[1], c[2], c[3]);
    }
  }
}

/// 눈꼬리를 바깥쪽으로 미세 이동(동공 보호)
Future<WarpResult> eyeTailStretch({
  required Uint8List bytes,
  required List<int> leftRing,
  required List<int> rightRing,
  required List<ui.Offset> ptsImg,
  required ui.Offset faceCenter,
  required double amount,
  required int width,
  required int height,
  Uint8List? skinMask, // optional
  Uint8List? lipMask, // optional
}) async {
  if (amount.abs() <= 0.001) {
    return WarpResult(bytes, skinMask: skinMask, lipMask: lipMask);
  }

  final src = img.decodeImage(bytes);
  if (src == null) {
    return WarpResult(bytes, skinMask: skinMask, lipMask: lipMask);
  }
  var cur = src.clone();

  // 워크스페이스(원본을 그대로 넘기지 않도록 복사)
  Uint8List? skin = skinMask != null ? Uint8List.fromList(skinMask) : null;
  Uint8List? lips = lipMask != null ? Uint8List.fromList(lipMask) : null;

  Map<String, dynamic> _eyeInfo(List<int> ring) {
    double minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9, sx = 0, sy = 0;
    for (final i in ring) {
      final p = ptsImg[i];
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
      sx += p.dx;
      sy += p.dy;
    }
    final cx = sx / ring.length, cy = sy / ring.length;
    final w = (maxX - minX).abs();
    final h = (maxY - minY).abs();
    final sign = (cx - faceCenter.dx) >= 0 ? 1.0 : -1.0;
    final outerX = sign > 0 ? maxX : minX;
    final outerY = cy;
    return {
      'c': ui.Offset(cx, cy),
      'w': w,
      'h': h,
      'outer': ui.Offset(outerX, outerY),
      'dir': sign,
    };
  }

  void _applyOne(Map<String, dynamic> eye) {
    final c = eye['c'] as ui.Offset;
    final w = eye['w'] as double;
    final h = eye['h'] as double;
    final tail = eye['outer'] as ui.Offset;
    final dir = eye['dir'] as double;

    final mag = (w * 0.28) * amount;
    final vx = dir * mag;
    final vy = -0.08 * mag;
    final sigmaX = w * 0.55;
    final sigmaY = h * 0.40;
    final holeSigma = math.max(w, h) * 0.35;

    // 이미지 워프
    final outImg = cur.clone();
    _dragGaussian(
      src: cur,
      out: outImg,
      cx: tail.dx,
      cy: tail.dy,
      vx: vx,
      vy: vy,
      sigmaX: sigmaX,
      sigmaY: sigmaY,
      holeCx: c.dx,
      holeCy: c.dy,
      holeSigma: holeSigma,
    );
    cur = outImg;

    // 마스크도 같은 변형 적용 (‼️ 널 아님을 보장한 임시변수로 전달)
    if (skin != null) {
      final Uint8List s = skin!;
      final Uint8List skinOut = Uint8List.fromList(s);
      _dragGaussianAlpha(
        src: s,
        out: skinOut,
        width: width,
        height: height,
        cx: tail.dx,
        cy: tail.dy,
        vx: vx,
        vy: vy,
        sigmaX: sigmaX,
        sigmaY: sigmaY,
      );
      skin = skinOut;
    }
    if (lips != null) {
      final Uint8List l = lips!;
      final Uint8List lipsOut = Uint8List.fromList(l);
      _dragGaussianAlpha(
        src: l,
        out: lipsOut,
        width: width,
        height: height,
        cx: tail.dx,
        cy: tail.dy,
        vx: vx,
        vy: vy,
        sigmaX: sigmaX,
        sigmaY: sigmaY,
      );
      lips = lipsOut;
    }
  }

  _applyOne(_eyeInfo(leftRing));
  _applyOne(_eyeInfo(rightRing));

  return WarpResult(
    Uint8List.fromList(img.encodePng(cur)),
    skinMask: skin,
    lipMask: lips,
  );
}

// ---------- 국소 크기 조절(코 등) ----------
Future<WarpResult> resizeRegionRadial({
  required Uint8List bytes,
  required ui.Offset center,
  required double radius,
  required double amount,
  required int width,
  required int height,
  Uint8List? skinMask, // optional
  Uint8List? lipMask, // optional
}) async {
  if (amount.abs() <= 0.0) {
    return WarpResult(bytes, skinMask: skinMask, lipMask: lipMask);
  }

  final src = img.decodeImage(bytes);
  if (src == null) {
    return WarpResult(bytes, skinMask: skinMask, lipMask: lipMask);
  }

  final out = src.clone();
  final r = radius.clamp(4.0, math.min(width, height) * 0.8);
  final r2 = r * r;

  double scaleFor(double d) {
    final t = (1 - (d / r)).clamp(0.0, 1.0);
    return 1.0 + amount * (t * t);
  }

  final cx = center.dx, cy = center.dy;

  // 마스크 워크스페이스
  Uint8List? skin = skinMask != null ? Uint8List.fromList(skinMask) : null;
  Uint8List? lips = lipMask != null ? Uint8List.fromList(lipMask) : null;
  Uint8List? skinOut = skin == null ? null : Uint8List.fromList(skin!);
  Uint8List? lipsOut = lips == null ? null : Uint8List.fromList(lips!);

  for (int y = (cy - r).floor(); y <= (cy + r).ceil(); y++) {
    if (y < 0 || y >= height) continue;
    for (int x = (cx - r).floor(); x <= (cx + r).ceil(); x++) {
      if (x < 0 || x >= width) continue;

      final dx = x - cx, dy = y - cy;
      final dist2 = dx * dx + dy * dy;
      if (dist2 > r2) continue;

      final dist = math.sqrt(dist2);
      final s = scaleFor(dist);
      final srcX = (cx + dx / s);
      final srcY = (cy + dy / s);

      final c = _sampleBilinearRgba(src, srcX, srcY);
      out.setPixelRgba(x, y, c[0], c[1], c[2], c[3]);

      if (skinOut != null && skin != null) {
        skinOut[y * width + x] = _sampleAlphaBilinear(
          skin,
          width,
          height,
          srcX,
          srcY,
        );
      }
      if (lipsOut != null && lips != null) {
        lipsOut[y * width + x] = _sampleAlphaBilinear(
          lips,
          width,
          height,
          srcX,
          srcY,
        );
      }
    }
  }

  return WarpResult(
    Uint8List.fromList(img.encodePng(out)),
    skinMask: skinOut ?? skin,
    lipMask: lipsOut ?? lips,
  );
}

// ---------- 립 보정 + HSL ----------

Future<Uint8List> tintLips({
  required Uint8List bytes,
  required Uint8List lipMaskAlpha,
  required int width,
  required int height,
  double satGain = 0.2,
  double hueShiftDeg = 0.0, // UI에서 -40~+40만 전달 권장
  double intensity = 0.6,
}) async {
  final src = img.decodeImage(bytes);
  if (src == null) return bytes;

  final out = src.clone();
  int idx = 0;

  // 레드 축(350° 근처) 기준으로 ± hueShift
  final targetHue = ((350.0 + hueShiftDeg).clamp(0.0, 360.0)) / 360.0;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++, idx++) {
      final mask = lipMaskAlpha[idx] / 255.0;
      if (mask <= 0) continue;

      final p = out.getPixel(x, y);
      double r = p.r / 255.0, g = p.g / 255.0, b = p.b / 255.0;

      final hsl = _rgbToHsl(r, g, b);
      double h = hsl[0], s = hsl[1], l = hsl[2];

      s = (s * (1.0 + satGain)).clamp(0.0, 1.0);
      h = _lerpHue(h, targetHue, 0.85);

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

// HSL helpers
List<double> _rgbToHsl(double r, double g, double b) {
  final maxv = [r, g, b].reduce((a, b) => a > b ? a : b);
  final minv = [r, g, b].reduce((a, b) => a < b ? a : b);
  double h = 0, s = 0;
  final l = (maxv + minv) / 2.0;

  if (maxv != minv) {
    final d = maxv - minv;
    s = l > 0.5 ? d / (2.0 - maxv - minv) : d / (maxv + minv);
    if (maxv == r) {
      h = ((g - b) / d + (g < b ? 6 : 0)) / 6.0;
    } else if (maxv == g) {
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

// 원형 Hue 보간(0~1)
double _lerpHue(double a, double b, double t) {
  double d = (b - a);
  if (d > 0.5) d -= 1.0;
  if (d < -0.5) d += 1.0;
  double out = a + d * t;
  if (out < 0) out += 1.0;
  if (out > 1) out -= 1.0;
  return out;
}

// 파일 상단 import 아래 아무 곳에 추가
class WarpResult {
  final Uint8List bytes;
  final Uint8List? skinMask;
  final Uint8List? lipMask;
  WarpResult(this.bytes, {this.skinMask, this.lipMask});
}

// Uint8List 알파(0~255) bilinear 샘플링
int _sampleAlphaBilinear(Uint8List a, int w, int h, double fx, double fy) {
  final x0 = fx.floor();
  final y0 = fy.floor();
  final x1 = x0 + 1;
  final y1 = y0 + 1;
  final tx = fx - x0;
  final ty = fy - y0;

  int getA(int x, int y) {
    if (x < 0) x = 0;
    if (x >= w) x = w - 1;
    if (y < 0) y = 0;
    if (y >= h) y = h - 1;
    return a[y * w + x];
  }

  final a00 = getA(x0, y0);
  final a10 = getA(x1, y0);
  final a01 = getA(x0, y1);
  final a11 = getA(x1, y1);

  final a0 = (a00 + (a10 - a00) * tx);
  final a1 = (a01 + (a11 - a01) * tx);
  final aa = (a0 + (a1 - a0) * ty).clamp(0.0, 255.0);
  return aa.round();
}

void _dragGaussianAlpha({
  required Uint8List src,
  required Uint8List out,
  required int width,
  required int height,
  required double cx,
  required double cy,
  required double vx,
  required double vy,
  required double sigmaX,
  required double sigmaY,
}) {
  final sx2 = sigmaX * sigmaX;
  final sy2 = sigmaY * sigmaY;

  final minx = math.max(0, (cx - sigmaX * 3).floor());
  final maxx = math.min(width - 1, (cx + sigmaX * 3).ceil());
  final miny = math.max(0, (cy - sigmaY * 3).floor());
  final maxy = math.min(height - 1, (cy + sigmaY * 3).ceil());

  for (int y = miny; y <= maxy; y++) {
    for (int x = minx; x <= maxx; x++) {
      final dx = x - cx;
      final dy = y - cy;
      final g = math.exp(-0.5 * ((dx * dx) / sx2 + (dy * dy) / sy2));
      if (g <= 1e-6) continue;

      final sxp = x - vx * g;
      final syp = y - vy * g;

      final a = _sampleAlphaBilinear(src, width, height, sxp, syp);
      out[y * width + x] = a;
    }
  }
}
