import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../widgets/user_icon_button.dart';

class SharedAlbumListScreen extends StatefulWidget {
  const SharedAlbumListScreen({super.key});

  @override
  State<SharedAlbumListScreen> createState() => _SharedAlbumListScreenState();
}

class _SharedAlbumListScreenState extends State<SharedAlbumListScreen> {
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
      setState(() {
        _albums = List<Map<String, dynamic>>.from(jsonDecode(storedData));
      });
    }
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
                  child: _albums.isEmpty
                      ? const Center(
                          child: Text(
                            '생성된 공유 앨범이 없습니다.',
                            style: TextStyle(fontSize: 16, color: Color(0xFF625F8C)),
                          ),
                        )
                      : SingleChildScrollView(
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
                                    offset: const Offset(18, 0),
                                    child: Row(
                                      children: [
                                        Image.asset(
                                          'assets/icons/shared_album_list.png',
                                          width: 50,
                                          height: 50,
                                        ),
                                        const SizedBox(width: 20),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                album['title'],
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF625F8C),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '사진 ${album['images'].length}장',
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
              child: CustomBottomNavBar(selectedIndex: 1),
            ),
          ],
        ),
      ),
    );
  }
}