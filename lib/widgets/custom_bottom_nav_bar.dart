// lib/widgets/custom_bottom_nav_bar.dart
import 'package:flutter/material.dart';
import '../screens/shared_album_screen.dart';
import '../screens/shared_album_list_screen.dart';
import '../screens/edit_album_list_screen.dart';
import '../screens/friend_manage_screen.dart';

class CustomBottomNavBar extends StatelessWidget {
  /// 과거 코드와 호환을 위해 남겨두지만, 실제로는 '현재 화면 추론'이 우선 적용됨.
  final int? selectedIndex;

  const CustomBottomNavBar({super.key, this.selectedIndex});

  // 🔹 현재 화면 타입을 보고 index 자동 추론
  int _inferIndexFromContext(BuildContext context) {
    if (context.findAncestorWidgetOfExactType<SharedAlbumScreen>() != null) return 0;
    if (context.findAncestorWidgetOfExactType<SharedAlbumListScreen>() != null) return 1;
    if (context.findAncestorWidgetOfExactType<EditAlbumListScreen>() != null) return 2;
    if (context.findAncestorWidgetOfExactType<FriendManageScreen>() != null) return 3;
    return selectedIndex ?? 0; // 혹시 못 찾으면 전달값/기본값
  }

  @override
  Widget build(BuildContext context) {
    final int current = _inferIndexFromContext(context);

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

    return SafeArea(
      // ✅ 모든 화면 통일 여백: 좌우 20, 하단 20
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        height: 70, // ✅ 바 높이 통일
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
                if (index == current) return; // 이미 현재 탭이면 무시

                // 🔹 화면 전환
                late final Widget next;
                if (index == 0) {
                  next = const SharedAlbumScreen();
                } else if (index == 1) {
                  next = const SharedAlbumListScreen();
                } else if (index == 2) {
                  next = const EditAlbumListScreen();
                } else {
                  next = const FriendManageScreen();
                }

                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => next),
                );
              },
              child: Image.asset(
                current == index ? iconPathsOn[index] : iconPathsOff[index],
                width: index == 2 ? 38 : 36,
                height: index == 2 ? 38 : 36,
                fit: BoxFit.contain,
              ),
            );
          }),
        ),
      ),
    );
  }
}
