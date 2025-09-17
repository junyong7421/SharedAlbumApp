// lib/beauty/beauty_panel.dart
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'beauty_controller.dart';

class BeautyPanel extends StatefulWidget {
  final Uint8List srcPng; // 현재 캡처/편집 이미지 PNG 바이트
  final List<List<Offset>> faces468; // 전체 얼굴 랜드마크
  final int selectedFace; // 어느 얼굴에 적용할지
  final Size imageSize; // 캔버스 사이즈
  const BeautyPanel({
    super.key,
    required this.srcPng,
    required this.faces468,
    required this.selectedFace,
    required this.imageSize,
  });

  @override
  State<BeautyPanel> createState() => _BeautyPanelState();
}

class _BeautyPanelState extends State<BeautyPanel> {
  final _params = BeautyParams();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  '얼굴 보정',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const Spacer(),
                if (_busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            _slider01('피부 부드럽게', _params.skinStrength,
  (v) => setState(() => _params.skinStrength = v),
),
_slider01('눈 확대', _params.eyeAmount,
  (v) => setState(() => _params.eyeAmount = v),
),
_slider01('입술 채도', _params.lipSatGain,
  (v) => setState(() => _params.lipSatGain = v),
),

// 각도(°)는 전용 헬퍼 사용
_sliderDeg('입술 색조(°)', _params.hueShift,
  (deg) => setState(() => _params.hueShift = deg),
),

_slider01('립 강도', _params.lipIntensity,
  (v) => setState(() => _params.lipIntensity = v),
),


            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy ? null : _apply,
                child: const Text('적용'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 0~1 범위 공통 슬라이더
Widget _slider01(String label, double value, ValueChanged<double> onChanged) {
  return Row(
    children: [
      SizedBox(width: 90, child: Text(label)),
      Expanded(
        child: Slider(
          min: 0, max: 1,
          value: value.clamp(0.0, 1.0),
          onChanged: (v) => onChanged(v.clamp(0.0, 1.0)),
        ),
      ),
    ],
  );
}

// 각도(0~360°)용 슬라이더: 내부적으로 0~1로 매핑
Widget _sliderDeg(String label, double deg, ValueChanged<double> onChangedDeg) {
  final uiValue = (deg / 360.0).clamp(0.0, 1.0);
  return Row(
    children: [
      SizedBox(width: 90, child: Text(label)),
      Expanded(
        child: Slider(
          min: 0, max: 1,
          value: uiValue,
          onChanged: (v) => onChangedDeg((v.clamp(0.0, 1.0)) * 360.0),
        ),
      ),
    ],
  );
}


  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      final ctrl = BeautyController();
      final out = await ctrl.applyAll(
        srcPng: widget.srcPng,
        faces468: widget.faces468,
        selectedFace: widget.selectedFace,
        imageSize: widget.imageSize,
        params: _params,
      );
      if (mounted) Navigator.pop(context, out);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
