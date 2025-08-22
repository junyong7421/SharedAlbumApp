import 'package:flutter/material.dart';

class AddUserPopup extends StatefulWidget {
  const AddUserPopup({super.key});

  @override
  State<AddUserPopup> createState() => _AddUserPopupState();
}

class _AddUserPopupState extends State<AddUserPopup> {
  final _controller = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFF6F9FF),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFF625F8C), width: 5),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '친구 추가',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF625F8C),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.emailAddress,
              cursorColor: const Color(0xFF625F8C),
              style: const TextStyle(color: Color(0xFF625F8C)),
              decoration: InputDecoration(
                hintText: "이메일을 입력하세요",
                hintStyle: const TextStyle(color: Color(0xFF625F8C)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: Color(0xFF625F8C)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(
                    color: Color(0xFF625F8C),
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              onSubmitted: _submit,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _gradientButton('취소', () => Navigator.pop(context, null)),
                _gradientButton(
                  _loading ? '처리중...' : '추가',
                  _loading ? null : () => _submit(_controller.text),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _submit(String value) async {
    final email = value.trim();
    if (email.isEmpty) return;
    setState(() => _loading = true);
    // 팝업은 입력만 담당 → 이메일을 호출자에게 반환
    Navigator.pop(context, email);
  }

  Widget _gradientButton(String label, VoidCallback? onTap) {
    final disabled = onTap == null;

    return Opacity(
      // 투명도는 위젯 레벨에서 처리
      opacity: disabled ? 0.6 : 1.0,
      child: IgnorePointer(
        // 비활성 시 터치 차단
        ignoring: disabled,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 120,
            height: 44,
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
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ),
      ),
    );
  }
}
