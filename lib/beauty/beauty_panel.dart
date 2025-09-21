// lib/beauty/beauty_panel.dart
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'beauty_controller.dart';

class BeautyPanel extends StatefulWidget {
  final Uint8List srcPng;
  final List<List<Offset>> faces468;
  final int selectedFace;
  final Size imageSize;
  final BeautyParams? initialParams;

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
  late final BeautyParams _baseline; // 패널 오픈 당시 값(눈금/Δ 기준)
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _params = (widget.initialParams ?? BeautyParams()).copyWith();
    _baseline = (widget.initialParams ?? BeautyParams()).copyWith();
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

            // -1~1 (중앙 0 눈금)
            _sliderSigned(
              '피부 톤업',
              _params.skinTone,
              (v) => setState(() => _params.skinTone = v),
            ),
            _sliderSigned(
              '눈 뒤트임',
              _params.eyeTail,
              (v) => setState(() => _params.eyeTail = v),
            ),

            // 0~1 슬라이더 + “기준 눈금” (패널 입장 당시 값 위치에 얇은 라인)
            _slider01WithTick(
              '입술 채도',
              _params.lipSatGain,
              _baseline.lipSatGain,
              (v) => setState(() => _params.lipSatGain = v),
            ),
            _sliderHueWithZeroTick(
              '립 색상',
              _params.hueShift,
              (deg) => setState(() => _params.hueShift = deg),
            ),
            _slider01WithTick(
              '립 강도',
              _params.lipIntensity,
              _baseline.lipIntensity,
              (v) => setState(() => _params.lipIntensity = v),
            ),

            const Divider(height: 24),
            _sliderSigned(
              '코 크기',
              _params.noseAmount,
              (v) => setState(() => _params.noseAmount = v),
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

  // 중앙 0 눈금 (-1~1)
  // lib/beauty/beauty_panel.dart 중

  // 중앙 0 눈금(-1~1) + 값 표시
  Widget _sliderSigned(String label, double v, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(label)),
        Expanded(
          child: SizedBox(
            height: 36,
            child: Stack(
              alignment: Alignment.center,
              children: [
                IgnorePointer(
                  child: Container(width: 2, height: 14, color: Colors.black26),
                ),
                Slider(
                  min: -1,
                  max: 1,
                  value: v.clamp(-1.0, 1.0),
                  onChanged: (nv) => onChanged(nv.clamp(-1.0, 1.0)),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 54,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              v.toStringAsFixed(2),
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 0~1 + 기준 눈금(초기값 위치) + 값 표시
  Widget _slider01WithTick(
    String label,
    double value,
    double tickAt,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(label)),
        Expanded(
          child: SizedBox(
            height: 36,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment((tickAt * 2) - 1, 0),
                  child: IgnorePointer(
                    child: Container(
                      width: 2,
                      height: 14,
                      color: Colors.black26,
                    ),
                  ),
                ),
                Slider(
                  min: 0,
                  max: 1,
                  value: value.clamp(0.0, 1.0),
                  onChanged: (v) => onChanged(v.clamp(0.0, 1.0)),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 54,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              value.toStringAsFixed(2),
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // -40°~+40° + 중앙(0°) 눈금 + 값 표시
  Widget _sliderHueWithZeroTick(
    String label,
    double deg,
    ValueChanged<double> onChangedDeg,
  ) {
    const minDeg = -40.0, maxDeg = 40.0;
    final uiValue = ((deg - minDeg) / (maxDeg - minDeg)).clamp(0.0, 1.0);
    final zeroPos = ((0 - minDeg) / (maxDeg - minDeg)).clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(width: 90, child: Text(label)),
        Expanded(
          child: SizedBox(
            height: 36,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment(zeroPos * 2 - 1, 0),
                  child: IgnorePointer(
                    child: Container(
                      width: 2,
                      height: 14,
                      color: Colors.black26,
                    ),
                  ),
                ),
                Slider(
                  min: 0,
                  max: 1,
                  value: uiValue,
                  onChanged: (v) =>
                      onChangedDeg(minDeg + v * (maxDeg - minDeg)),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 54,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${deg.toStringAsFixed(0)}°',
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
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
        srcPng: widget.srcPng, // 패널 진입 시 스냅샷(누적 방지)
        faces468: widget.faces468,
        selectedFace: widget.selectedFace,
        imageSize: widget.imageSize,
        params: _params,
        prevParams: _baseline, // ❗ Δ 기준(중복 적용 방지)
      );
      if (mounted) Navigator.pop(context, (image: out, params: _params));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
