import 'package:flutter/material.dart';
import 'signup_screen.dart'; // 🔹 회원가입 화면 import

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EBFE),
      body: Center(
        child: Container(
          width: 350,   // ✅ 가로 고정
          height: 380,  // ✅ 세로 고정
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F9FF),
            borderRadius: BorderRadius.circular(32),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTextField('가입 시 입력한 이메일 주소', false),
              const SizedBox(height: 12),
              _buildTextField('비밀번호', true),
              const SizedBox(height: 20),
              _buildGradientButton('Login'),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SignUpScreen()),
                  );
                },
                child: const Text(
                  '소셜 계정으로 로그인',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF404040),
                    decoration: TextDecoration.underline, // 누를 수 있는 느낌
                  ),
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

  Widget _buildTextField(String hint, bool isPassword) {
    return TextField(
      obscureText: isPassword,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        hintStyle: const TextStyle(color: Colors.black54),
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
      child: const Center(
        child: Text(
          'Login',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
