import 'package:flutter/material.dart';

class EmailInputPopup extends StatelessWidget {
  const EmailInputPopup({super.key});

  @override
  Widget build(BuildContext context) {
    final TextEditingController controller = TextEditingController();

    return Dialog(
      backgroundColor: const Color(0xFFF6F9FF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF625F8C), width: 2),
      ),
      child: Container(
        width: 300,
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '사용자의 이메일을 입력 해주세요.',
              style: TextStyle(color: Color(0xFF625F8C), fontSize: 16),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: '입력',
                hintStyle: const TextStyle(color: Color(0xFF625F8C)),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Color(0xFF625F8C)),
                  borderRadius: BorderRadius.circular(30),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(
                    color: Color(0xFF625F8C),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              cursorColor: const Color(0xFF625F8C),
              style: const TextStyle(color: Color(0xFF625F8C)),
            ),
            const SizedBox(height: 30),
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                // 이메일 처리 로직 추가 가능
              },
              child: Container(
                width: 120,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFC6DCFF),
                      Color(0xFFD2D1FF),
                      Color(0xFFF5CFFF),
                    ],
                  ),
                ),
                alignment: Alignment.center,
                child: const Text(
                  '확인',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
