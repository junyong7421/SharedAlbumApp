import 'package:flutter/material.dart';

class AddMemberPopup extends StatelessWidget {
  final List<String> alreadyInvited;

  const AddMemberPopup({super.key, required this.alreadyInvited});

  @override
  Widget build(BuildContext context) {
    // ✅ 현재 로그인한 사용자 이메일
    final String currentUserEmail = 'rhdrudwls@gmail.com';

    // ✅ 친구 이메일 리스트 (본인을 제외함)
    final friends = [
      'rhdrudwls@gmail.com',
      'friend1@email.com',
      'friend2@email.com',
      'friend3@email.com',
      'friend4@email.com',
      'friend5@email.com',
      /*'friend6@email.com',
      'friend7@email.com',
      'friend8@email.com',
      'friend9@email.com',
      'friend10@email.com',*/
    ];

    final filteredFriends = friends
        .where((f) => f != currentUserEmail)
        .toList();

    return Dialog(
      backgroundColor: const Color(0xFFF6F9FF),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFF625F8C), width: 2),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '친구 초대',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF625F8C),
              ),
            ),
            const SizedBox(height: 20),
            ...filteredFriends.map((email) {
              final isInvited = alreadyInvited.contains(email);
              return ListTile(
                title: Text(
                  email,
                  style: TextStyle(
                    color: isInvited ? Colors.grey : const Color(0xFF625F8C),
                  ),
                ),
                enabled: !isInvited,
                onTap: isInvited ? null : () => Navigator.pop(context, email),
              );
            }),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildGradientButton("취소", () {
                  Navigator.pop(context);
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientButton(String label, VoidCallback onTap) {
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
}
