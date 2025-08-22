import 'package:flutter/material.dart';
import 'add_user_popup.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../widgets/user_icon_button.dart';

class FriendManageScreen extends StatefulWidget {
  const FriendManageScreen({Key? key}) : super(key: key);

  @override
  State<FriendManageScreen> createState() => _FriendManageScreenState();
}

class _FriendManageScreenState extends State<FriendManageScreen> {
  int _selectedIndex = 3;

  final List<String> _iconPathsOn = [
    'assets/icons/image_on.png',
    'assets/icons/list_on.png',
    'assets/icons/edit_on.png',
    'assets/icons/friend_on.png',
  ];

  final List<String> _iconPathsOff = [
    'assets/icons/image_off.png',
    'assets/icons/list_off.png',
    'assets/icons/edit_off.png',
    'assets/icons/friend_off.png',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EBFE),
      body: Stack(
        children: [
          // ✅ 상단 전체를 조금 내려줌
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Column(
              children: [
                // ✅ 상단 유저 정보
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const UserIconButton(),
                      const SizedBox(width: 10),
                      const Text(
                        '친구관리',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF625F8C),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (_) => const AddUserPopup(),
                          );
                        },
                        child: Image.asset(
                          'assets/icons/user_plus.png',
                          width: 36,
                          height: 36,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ✅ 친구 리스트 박스 (크기 줄임)
                SizedBox(
                  height: MediaQuery.of(context).size.height - 320,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F9FF),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: ListView.builder(
                      itemCount: 1,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Image.asset(
                                'assets/icons/user2.png',
                                width: 28,
                                height: 28,
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                '정가을',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFF625F8C),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ✅ 하단바 고정
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: CustomBottomNavBar(selectedIndex: 3),
          ),
        ],
      ),
    );
  }
}