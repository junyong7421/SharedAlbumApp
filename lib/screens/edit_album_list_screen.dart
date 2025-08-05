import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import 'edit_screen.dart';
import '../widgets/user_icon_button.dart';

class EditAlbumListScreen extends StatefulWidget {
  const EditAlbumListScreen({super.key});

  @override
  State<EditAlbumListScreen> createState() => _EditAlbumListScreenState();
}

class _EditAlbumListScreenState extends State<EditAlbumListScreen> {
  List<Map<String, dynamic>> _albums = [];

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    final prefs = await SharedPreferences.getInstance();
    final storedData = prefs.getString('albums');
    if (storedData != null) {
      final List decoded = jsonDecode(storedData);
      setState(() {
        _albums = List<Map<String, dynamic>>.from(decoded);
      });
    }
  }

  //현재 sample1, sampe2 사진이 있으면 편집 중이라 표시
  bool _isEditing(List<dynamic> images) {
    return images.any(
      (image) =>
          image.toString().contains('sample1') ||
          image.toString().contains('sample2'),
    );
  }

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
                        '편집',
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

                // ✅ 앨범 리스트
                Expanded(
                  child: _albums.isEmpty
                      ? const Center(
                          child: Text(
                            '편집 가능한 공유 앨범이 없습니다.',
                            style: TextStyle(
                              fontSize: 16,
                              color: Color(0xFF625F8C),
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: 90),
                          child: Column(
                            children: List.generate(_albums.length, (index) {
                              final album = _albums[index];
                              final List<dynamic> images =
                                  album['images'] ?? [];
                              final bool isEditing = _isEditing(images);

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                child: GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => EditScreen(
                                          albumName: album['title'] ?? '제목 없음',
                                        ),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF6F9FF),
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 24,
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment
                                          .center, // ✅ 세로 가운데 정렬
                                      children: [
                                        Image.asset(
                                          'assets/icons/shared_album_list.png',
                                          width: 50,
                                          height: 50,
                                        ),
                                        const SizedBox(width: 20),
                                        Expanded(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment
                                                .center, // ✅ 내부 텍스트들도 중앙 정렬
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment
                                                        .center, // ✅ 편집중도 가운데로
                                                children: [
                                                  Text(
                                                    album['title'] ?? '제목 없음',
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Color(0xFF625F8C),
                                                    ),
                                                  ),
                                                  if (isEditing)
                                                    const Text(
                                                      '편집 중',
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        color: Color(
                                                          0xFF625F8C,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '사진 ${images.length}장',
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

            // ✅ 하단 네비게이션 바
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: CustomBottomNavBar(selectedIndex: 2),
            ),
          ],
        ),
      ),
    );
  }
}
