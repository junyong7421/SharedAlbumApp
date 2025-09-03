import 'package:flutter/material.dart';

/// 추후 flutter_webrtc 붙일 실제 통화 화면.
/// 지금은 빌드만 통과하는 심플한 자리표시자 UI입니다.
class VoiceCallScreen extends StatelessWidget {
  final String roomId;
  final String title;

  const VoiceCallScreen({
    super.key,
    required this.roomId,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EBFE),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF625F8C),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.headset_mic, size: 72, color: Color(0xFF625F8C)),
            const SizedBox(height: 12),
            Text(
              '보이스 방 입장됨\n(roomId: $roomId)',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF625F8C),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.call_end),
              label: const Text('나가기'),
            ),
          ],
        ),
      ),
    );
  }
}
