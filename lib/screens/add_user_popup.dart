import 'package:flutter/material.dart';

class AddUserPopup extends StatelessWidget {
  const AddUserPopup({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFF6F9FF),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFF625F8C), width: 5),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildGradientButton('기존 사용자 추가'),
            const SizedBox(height: 20),
            _buildGradientButton('새로운 사용자 추가'),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientButton(String label) {
    return Container(
      width: 220,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [Color(0xFFC6DCFF), Color(0xFFD2D1FF), Color(0xFFF5CFFF)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
    );
  }
}
