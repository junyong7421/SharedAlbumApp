import 'package:flutter/material.dart';
import '../screens/login_choice_screen.dart';

// [변경] Firebase/GoogleSignIn 추가
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class UserIconButton extends StatelessWidget {
  const UserIconButton({super.key});

  // [변경] 완전 로그아웃 함수: Firebase + Google 세션 해제
  Future<void> _signOutCompletely() async {
    try {
      // FirebaseAuth 로그아웃
      await FirebaseAuth.instance.signOut();

      // GoogleSignIn 연결 해제 및 로그아웃
      final g = GoogleSignIn();
      try {
        await g.disconnect(); // 토큰 revoke
      } catch (_) {
        // 이미 연결이 없을 수 있어 무시
      }
      await g.signOut();
    } catch (e) {
      debugPrint('로그아웃 실패: $e');
    }
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: const Color(0xFFF6F9FF),
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFF625F8C), width: 2),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  "로그아웃",
                  style: TextStyle(
                    fontSize: 20,
                    color: Color(0xFF625F8C),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "로그아웃 하시겠습니까?",
                  style: TextStyle(fontSize: 16, color: Color(0xFF625F8C)),
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildGradientActionButton("취소", () {
                      Navigator.pop(context);
                    }),
                    // [변경] 확인: 완전 로그아웃 후 로그인 화면으로 이동
                    _buildGradientActionButton("확인", () async {
                      await _signOutCompletely(); // [변경]
                      if (context.mounted) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LoginChoiceScreen(),
                          ),
                          (route) => false,
                        );
                      }
                    }),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGradientActionButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFFC6DCFF), Color(0xFFD2D1FF), Color(0xFFF5CFFF)],
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showLogoutDialog(context),
      child: Image.asset(
        'assets/icons/user.png',
        width: 50,
        height: 50,
      ),
    );
  }
}