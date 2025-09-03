import 'package:flutter/material.dart';
import 'package:sharedalbumapp/services/auth_service.dart';
// AuthService 경로에 맞게 수정하세요
import 'shared_album_screen.dart';

class LoginScreen extends StatelessWidget {
  LoginScreen({super.key});

  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EBFE),
      body: Center(
        child: Container(
          width: 350,
          height: 300,
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F9FF),
            borderRadius: BorderRadius.circular(32),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '소셜 계정으로 로그인',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF404040),
                  decoration: TextDecoration.underline,
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  final user = await _authService.signInWithGoogle();
                  if (user != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${user.displayName}님 환영합니다!')),
                    );

                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SharedAlbumScreen(),
                      ),
                    );
                    // TODO: 로그인 성공 후 홈 화면으로 이동 처리
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('로그인에 실패했습니다.')),
                    );
                  }
                },
                child: _buildGradientButton('Google로 로그인'),
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
          colors: [Color(0xFFC6DCFF), Color(0xFFD2D1FF), Color(0xFFF5CFFF)],
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
