import 'package:flutter/material.dart';
import 'package:sharedalbumapp/screens/login_screen.dart';
import '../screens/login_choice_screen.dart';

// [유지] Firebase/GoogleSignIn
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class UserIconButton extends StatelessWidget {
  // ===================== 변경 포인트 =====================
  // [추가] 구글 프로필 사진 URL(없으면 에셋/아이콘으로 폴백)
  final String? photoUrl;

  // [추가] 크기 커스터마이즈(기본 48)
  final double radius;

  const UserIconButton({
    super.key,
    this.photoUrl,        // [추가]
    this.radius = 24,     // [추가]
  });
  // =====================================================

  // [유지] 완전 로그아웃
  Future<void> _signOutCompletely() async {
    try {
      await FirebaseAuth.instance.signOut();

      final g = GoogleSignIn();
      try {
        await g.disconnect(); // 토큰 revoke
      } catch (_) { /* 연결 없을 수 있음 */ }
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
                    // [유지] 확인: 완전 로그아웃 후 로그인 화면으로 이동
                    _buildGradientActionButton("확인", () async {
                      await _signOutCompletely();
                      if (context.mounted) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LoginScreen(),
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
    // ===================== 변경 포인트 =====================
    // [변경] 항상 같은 버튼이지만, 이미지 표현은 photoUrl 우선
    return GestureDetector(
      onTap: () => _showLogoutDialog(context),
      child: CircleAvatar(
        radius: radius,
        backgroundImage: (photoUrl != null && photoUrl!.isNotEmpty)
            ? NetworkImage(photoUrl!)
            : null,
        backgroundColor: const Color(0xFFD9E2FF),
        child: (photoUrl == null || photoUrl!.isEmpty)
            // [변경] photoUrl 없으면 기존 에셋(또는 아이콘)로 폴백
            ? ClipOval(
                child: Image.asset(
                  'assets/icons/user.png', // 기존 에셋 유지
                  width: radius * 2,
                  height: radius * 2,
                  fit: BoxFit.cover,
                ),
              )
            : null,
      ),
    );
    // =====================================================
  }
}