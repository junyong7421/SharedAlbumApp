import 'package:flutter/material.dart';

class LoginChoiceScreen extends StatelessWidget {
  const LoginChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EBFE), // 전체 배경색
      body: Center(
        child: Container(
          width: 350,
          height: 700, // ✅ 세로 길이 확장
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F9FF), // 내부 박스 색
            borderRadius: BorderRadius.circular(32),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start, // ✅ 위부터 정렬
            mainAxisSize: MainAxisSize.max,
            children: [
              const SizedBox(height: 200), // ✅ 위쪽 여백 주기
              Center(child: _buildGradientButton(context, 'Login')),
              const SizedBox(height: 16),
              Center(child: _buildGradientButton(context, 'Sign Up')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGradientButton(BuildContext context, String text) {
    return Container(
      width: 200, // ✅ 가로 줄임
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFC6DCFF),
            Color(0xFFD2D1FF),
            Color(0xFFF5CFFF),
          ],
        ),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white, // 글씨색
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
