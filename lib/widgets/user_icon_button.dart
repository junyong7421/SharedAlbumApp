import 'package:flutter/material.dart';
import '../screens/login_choice_screen.dart';

class UserIconButton extends StatelessWidget {
  const UserIconButton({super.key});

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
                    _buildGradientActionButton("확인", () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LoginChoiceScreen(),
                        ),
                        (route) => false,
                      );
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
