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
            _slider(
              '피부 부드럽게',
              _params.skinStrength,
              (v) => setState(() => _params.skinStrength = v),
            ),
            _slider(
              '눈 확대',
              _params.eyeAmount,
              (v) => setState(() => _params.eyeAmount = v),
            ),
            _slider(
              '입술 채도',
              _params.lipSatGain,
              (v) => setState(() => _params.lipSatGain = v),
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

  Widget _slider(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label)),
        Expanded(
          child: Slider(value: value, min: 0, max: 1, onChanged: onChanged),
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
