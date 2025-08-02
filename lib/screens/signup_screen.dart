import 'package:flutter/material.dart';

class SignUpScreen extends StatelessWidget {
  const SignUpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EBFE),
      body: Center(
        child: Container(
          width: 350,  // ✅ 가로 고정
          height: 380, // ✅ 세로 고정 (로그인 화면과 동일하게 설정)
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F9FF),
            borderRadius: BorderRadius.circular(32),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildGradientButton('이메일 주소로 회원가입'),
              const SizedBox(height: 24),
              const Text(
                '소셜 계정으로 가입할 수 있습니다.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF404040),
                ),
              ),
              const SizedBox(height: 12),
              Image.asset(
                'assets/images/google_logo.png',
                width: 40,
                height: 40,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGradientButton(String text) {
    return Container(
      width: double.infinity,
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
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
