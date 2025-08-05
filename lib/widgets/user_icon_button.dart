import 'package:flutter/material.dart';
import '../screens/login_choice_screen.dart';

class UserIconButton extends StatelessWidget {
  const UserIconButton({super.key});

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('로그아웃'),
          content: const Text('로그아웃 하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LoginChoiceScreen(),
                  ),
                  (route) => false,
                );
              },
              child: const Text('확인'),
            ),
          ],
        );
      },
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