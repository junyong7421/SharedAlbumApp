import 'package:flutter/material.dart';
import 'signup_screen.dart';
import 'shared_album_screen.dart'; // 🔹 로그인 성공 시 이동할 화면 import

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  // 🔹 하드코딩된 이메일과 비밀번호
  final String _validEmail = 'rhdrudwls@gmail.com';
  final String _validPassword = 'rhdrudwls';

  @override
  Widget build(BuildContext context) {
    // 🔹 컨트롤러 추가
    final TextEditingController emailController = TextEditingController();
    final TextEditingController passwordController = TextEditingController();

    return Scaffold(
      backgroundColor: const Color(0xFFE6EBFE),
      body: Center(
        child: Container(
          width: 350,
          height: 400, // 🔹 높이 살짝 늘림
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F9FF),
            borderRadius: BorderRadius.circular(32),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTextField('가입 시 입력한 이메일 주소', false, emailController),
              const SizedBox(height: 12),
              _buildTextField('비밀번호', true, passwordController),
              const SizedBox(height: 20),

              // 🔹 로그인 버튼 클릭 처리
              GestureDetector(
                onTap: () {
                  final enteredEmail = emailController.text.trim();
                  final enteredPassword = passwordController.text.trim();

                  if (enteredEmail == _validEmail && enteredPassword == _validPassword) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const SharedAlbumScreen()),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('이메일 또는 비밀번호가 올바르지 않습니다.')),
                    );
                  }
                },
                child: _buildGradientButton('Login'),
              ),

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
                    decoration: TextDecoration.underline,
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

  Widget _buildTextField(String hint, bool isPassword, TextEditingController controller) {
    return TextField(
      controller: controller,
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
      child: Center(
        child: Text(
          text, // 🔹 하드코딩된 'Login' → 매개변수로 변경됨
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
