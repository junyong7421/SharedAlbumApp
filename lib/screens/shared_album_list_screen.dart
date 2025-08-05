import 'package:flutter/material.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../widgets/user_icon_button.dart';

class SharedAlbumListScreen extends StatefulWidget {
  const SharedAlbumListScreen({super.key});

  @override
  State<SharedAlbumListScreen> createState() => _SharedAlbumListScreenState();
}

class _SharedAlbumListScreenState extends State<SharedAlbumListScreen> {
  final List<Map<String, dynamic>> _albums = [
    {'name': '공경진', 'members': 5, 'photos': 50},
    {'name': '캡스톤', 'members': 4, 'photos': 70},
    {'name': '가족', 'members': 3, 'photos': 20},
    {'name': '동아리', 'members': 6, 'photos': 35},
    /* 스크롤 확인
    {'name': '캡스톤', 'members': 4, 'photos': 70},
    {'name': '가족', 'members': 3, 'photos': 20},
    {'name': '동아리', 'members': 6, 'photos': 35},
    */
  ];

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

  int _selectedIndex = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EBFE),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // ✅ 상단 사용자 정보
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const UserIconButton(),
                      const SizedBox(width: 10),
                      const Text(
                        '공유앨범 목록 및 멤버관리',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF625F8C),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ✅ 공유 앨범 리스트
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 90),
                    child: Column(
                      children: List.generate(_albums.length, (index) {
                        final album = _albums[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF6F9FF),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 24,
                            ),
                            child: Transform.translate(
                              offset: const Offset(18, 0), // 전체 Row 오른쪽 이동
                              child: Row(
                                children: [
                                  Image.asset(
                                    'assets/icons/shared_album_list.png',
                                    width: 50,
                                    height: 50,
                                  ),
                                  const SizedBox(width: 20), // 이미지와 텍스트 사이 간격
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              album['name'],
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF625F8C),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Transform.translate(
                                              offset: const Offset(
                                                0,
                                                1,
                                              ), // 멤버 수 아래로 이동
                                              child: Text(
                                                '${album['members']}',
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  color: Color(0xFF625F8C),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '사진 ${album['photos']}장',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF625F8C),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: CustomBottomNavBar(selectedIndex: 1), // 이 화면은 index 1
            ),
          ],
        ),
      ),
    );
  }
}
