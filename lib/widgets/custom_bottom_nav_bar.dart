import 'package:flutter/material.dart';
import '../screens/shared_album_screen.dart';
import '../screens/shared_album_list_screen.dart';
import '../screens/edit_album_list_screen.dart';
import '../screens/friend_manage_screen.dart';

class CustomBottomNavBar extends StatelessWidget {
  final int selectedIndex;

  const CustomBottomNavBar({super.key, required this.selectedIndex});

  @override
  Widget build(BuildContext context) {
    final List<String> iconPathsOn = [
      'assets/icons/image_on.png',
      'assets/icons/list_on.png',
      'assets/icons/edit_on.png',
      'assets/icons/friend_on.png',
    ];

    final List<String> iconPathsOff = [
      'assets/icons/image_off.png',
      'assets/icons/list_off.png',
      'assets/icons/edit_off.png',
      'assets/icons/friend_off.png',
    ];

    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: const Color(0xFFF6F9FF),
        borderRadius: BorderRadius.circular(35),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(2, 2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(4, (index) {
          return GestureDetector(
            onTap: () {
              if (index == selectedIndex) return;

              // 🔹 선택한 탭에 따라 다른 화면으로 이동
              Widget nextScreen;
              if (index == 0) {
                nextScreen = const SharedAlbumScreen();
              } else if (index == 1)
                nextScreen = const SharedAlbumListScreen();
              else if (index == 2)
                nextScreen = const EditAlbumListScreen();
              else
                nextScreen = const FriendManageScreen();

              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => nextScreen),
              );
            },
            child: Image.asset(
              selectedIndex == index ? iconPathsOn[index] : iconPathsOff[index],
              width: index == 2 ? 38 : 36,
              height: index == 2 ? 38 : 36,
              fit: BoxFit.contain,
            ),
          );
        }),
      ),
    );
  }
}