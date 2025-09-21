import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'beauty_controller.dart';

class BeautyPanel extends StatefulWidget {
  final Uint8List srcPng; // 기준 PNG (누적 방지)
  final List<List<Offset>> faces468;
  final int selectedFace;
  final Size imageSize;

  final BeautyParams? initialParams; // 이전 값 유지

  const BeautyPanel({
    super.key,
    required this.srcPng,
    required this.faces468,
    required this.selectedFace,
    required this.imageSize,
    this.initialParams,
  });

  @override
  State<BeautyPanel> createState() => _BeautyPanelState();
}

class _BeautyPanelState extends State<BeautyPanel> {
  late BeautyParams _params;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _params = (widget.initialParams ?? BeautyParams()).copyWith();
  }

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

            _slider01(
              '피부 부드럽게',
              _params.skinStrength,
              (v) => setState(() => _params.skinStrength = v),
            ),
            _slider01(
              '눈 확대',
              _params.eyeAmount,
              (v) => setState(() => _params.eyeAmount = v),
            ),
            _slider01(
              '입술 채도',
              _params.lipSatGain,
              (v) => setState(() => _params.lipSatGain = v),
            ),
            _sliderLipHue(
              '립 색상',
              _params.hueShift,
              (deg) => setState(() => _params.hueShift = deg),
            ),
            _slider01(
              '립 강도',
              _params.lipIntensity,
              (v) => setState(() => _params.lipIntensity = v),
            ),

            const Divider(height: 24),

            _sliderSigned(
              '코 크기',
              _params.noseAmount,
              (v) => setState(() => _params.noseAmount = v),
            ),
            _sliderSigned(
              '얼굴 크기',
              _params.faceAmount,
              (v) => setState(() => _params.faceAmount = v),
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

  // 0~1 슬라이더
  Widget _slider01(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(label)),
        Expanded(
          child: Slider(
            min: 0,
            max: 1,
            value: value.clamp(0.0, 1.0),
            onChanged: (v) => onChanged(v.clamp(0.0, 1.0)),
          ),
        ),
      ],
    );
  }

  // 각도 0~360° (내부 0~1 매핑)
  // 기존 _sliderDeg(...) 대신 아래로 교체
  Widget _sliderLipHue(
    String label,
    double deg,
    ValueChanged<double> onChangedDeg,
  ) {
    const double minDeg = -40.0; // 레드에서 -40° (코럴/오렌지 쪽)
    const double maxDeg = 40.0; // 레드에서 +40° (핑크/플럼 쪽)
    final uiValue = ((deg - minDeg) / (maxDeg - minDeg)).clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(width: 90, child: Text(label)),
        Expanded(
          child: Slider(
            min: 0,
            max: 1,
            value: uiValue,
            onChanged: (v) => onChangedDeg(minDeg + v * (maxDeg - minDeg)),
          ),
        ),
      ],
    );
  }

  // -1 ~ +1 (중앙 0)
  Widget _sliderSigned(String label, double v, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(label)),
        Expanded(
          child: Slider(
            min: -1,
            max: 1,
            value: v.clamp(-1.0, 1.0),
            onChanged: (nv) => onChanged(nv.clamp(-1.0, 1.0)),
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
        srcPng: widget.srcPng, // 항상 기준 PNG에서 시작(누적 방지)
        faces468: widget.faces468,
        selectedFace: widget.selectedFace,
        imageSize: widget.imageSize,
        params: _params,
      );
      if (mounted) Navigator.pop(context, (image: out, params: _params));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
