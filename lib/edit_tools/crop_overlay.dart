// lib/edit_tools/crop_overlay.dart
import 'package:flutter/material.dart';

enum CropHandle { none, move, tl, tr, bl, br, top, right, bottom, left }

class CropOverlay extends StatefulWidget {
  final Rect? initRect;
  final ValueChanged<Rect> onChanged;
  final ValueChanged<Size> onStageSize;

  const CropOverlay({
    super.key,
    required this.initRect,
    required this.onChanged,
    required this.onStageSize,
  });

  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<CropOverlay> {
  Rect? rect;
  CropHandle handle = CropHandle.none;
  Offset? dragStart;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final stage = Size(c.maxWidth, c.maxHeight);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onStageSize(stage);
        });

        rect ??=
            widget.initRect ??
            Rect.fromLTWH(
              stage.width * 0.1,
              stage.height * 0.1,
              stage.width * 0.8,
              stage.height * 0.8,
            );

        return GestureDetector(
          onPanStart: (d) {
            dragStart = d.localPosition;
            handle = _hitHandle(d.localPosition, rect!);
          },
          onPanUpdate: (d) {
            if (dragStart == null) return;
            final delta = d.localPosition - dragStart!;
            dragStart = d.localPosition;
            setState(() {
              rect = _update(rect!, delta, stage, handle);
              widget.onChanged(rect!);
            });
          },
          onPanEnd: (_) => handle = CropHandle.none,
          child: CustomPaint(painter: _CropPainter(rect!)),
        );
      },
    );
  }

  CropHandle _hitHandle(Offset p, Rect r) {
    const k = 18.0;
    final corners = {
      CropHandle.tl: r.topLeft,
      CropHandle.tr: r.topRight,
      CropHandle.bl: r.bottomLeft,
      CropHandle.br: r.bottomRight,
    };
    for (final e in corners.entries) {
      if ((p - e.value).distance <= k) return e.key;
    }
    if ((p.dy - r.top).abs() <= 12 && p.dx >= r.left && p.dx <= r.right)
      return CropHandle.top;
    if ((p.dy - r.bottom).abs() <= 12 && p.dx >= r.left && p.dx <= r.right)
      return CropHandle.bottom;
    if ((p.dx - r.left).abs() <= 12 && p.dy >= r.top && p.dy <= r.bottom)
      return CropHandle.left;
    if ((p.dx - r.right).abs() <= 12 && p.dy >= r.top && p.dy <= r.bottom)
      return CropHandle.right;
    if (r.contains(p)) return CropHandle.move;
    return CropHandle.none;
  }

  Rect _update(Rect r, Offset d, Size stage, CropHandle h) {
    double l = r.left, t = r.top, w = r.width, hgt = r.height;
    switch (h) {
      case CropHandle.move:
        l += d.dx;
        t += d.dy;
        break;
      case CropHandle.tl:
        l += d.dx;
        t += d.dy;
        w -= d.dx;
        hgt -= d.dy;
        break;
      case CropHandle.tr:
        t += d.dy;
        w += d.dx;
        hgt -= d.dy;
        break;
      case CropHandle.bl:
        l += d.dx;
        w -= d.dx;
        hgt += d.dy;
        break;
      case CropHandle.br:
        w += d.dx;
        hgt += d.dy;
        break;
      case CropHandle.top:
        t += d.dy;
        hgt -= d.dy;
        break;
      case CropHandle.bottom:
        hgt += d.dy;
        break;
      case CropHandle.left:
        l += d.dx;
        w -= d.dx;
        break;
      case CropHandle.right:
        w += d.dx;
        break;
      case CropHandle.none:
        break;
    }
    const minSize = 40.0;
    w = w.clamp(minSize, stage.width);
    hgt = hgt.clamp(minSize, stage.height);
    l = l.clamp(0, stage.width - w);
    t = t.clamp(0, stage.height - hgt);
    return Rect.fromLTWH(l, t, w, hgt);
  }
}

class _CropPainter extends CustomPainter {
  final Rect r;
  _CropPainter(this.r);

  @override
  void paint(Canvas c, Size s) {
    final bg = Paint()..color = const Color(0x66000000);
    c.drawRect(Offset.zero & s, bg);

    final clear = Paint()..blendMode = BlendMode.clear;
    c.saveLayer(Offset.zero & s, Paint());
    c.drawRect(r, clear);
    c.restore();

    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    c.drawRect(r, border);

    const rad = 6.0;
    final dot = Paint()..color = Colors.white;
    for (final p in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      c.drawCircle(p, rad, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) => old.r != r;
}
