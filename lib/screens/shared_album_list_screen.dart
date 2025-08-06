import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../widgets/user_icon_button.dart';
import 'add_member_popup.dart';

class SharedAlbumListScreen extends StatefulWidget {
  const SharedAlbumListScreen({super.key});

  @override
  State<SharedAlbumListScreen> createState() => _SharedAlbumListScreenState();
}

class _SharedAlbumListScreenState extends State<SharedAlbumListScreen> {
  List<Map<String, dynamic>> _albums = [];
  final String currentUserEmail = 'rhdrudwls@gmail.com';

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    final prefs = await SharedPreferences.getInstance();
    final storedData = prefs.getString('albums');
    if (storedData != null) {
      final decoded = jsonDecode(storedData);
      final loaded = List<Map<String, dynamic>>.from(decoded);

      for (var album in loaded) {
        if (album['members'] != null) {
          album['members'] = List<String>.from(album['members']);
          if (!album['members'].contains(currentUserEmail)) {
            album['members'].add(currentUserEmail);
          }
        } else {
          album['members'] = [currentUserEmail];
        }
      }

      setState(() {
        _albums = loaded;
      });
    }
  }

  Future<void> _saveAlbums() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('albums', jsonEncode(_albums));
  }

  void _inviteFriendToAlbum(int albumIndex) async {
    final currentMembers = List<String>.from(_albums[albumIndex]['members'] ?? []);
    final selectedEmail = await showDialog<String>(
      context: context,
      builder: (_) => AddMemberPopup(alreadyInvited: currentMembers),
    );

    if (selectedEmail != null) {
      final updatedMembers = List<String>.from(_albums[albumIndex]['members'] ?? []);
      if (!updatedMembers.contains(selectedEmail)) {
        updatedMembers.add(selectedEmail);
        _albums[albumIndex]['members'] = updatedMembers;
        setState(() {});
        await _saveAlbums();
      }
    }
  }

  void _showAlbumInfoPopup(Map<String, dynamic> album) {
    final members = List<String>.from(album['members'] ?? []);
    final title = album['title'];
    final imageCount = (album['images'] as List?)?.length ?? 0;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFFF6F9FF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
            side: const BorderSide(color: Color(0xFF625F8C), width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '앨범 정보',
                  style: TextStyle(
                    fontSize: 20,
                    color: Color(0xFF625F8C),
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Text('앨범 이름: $title',
                    style: const TextStyle(color: Color(0xFF625F8C)),
                    textAlign: TextAlign.center),
                Text('구성원 수: ${members.length}명',
                    style: const TextStyle(color: Color(0xFF625F8C)),
                    textAlign: TextAlign.center),
                const SizedBox(height: 10),
                const Text('멤버 목록:',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Color(0xFF625F8C)),
                    textAlign: TextAlign.center),
                const SizedBox(height: 4),
                ...members.map((name) => Text(
                      name,
                      style: const TextStyle(color: Color(0xFF625F8C)),
                      textAlign: TextAlign.center,
                    )),
                const SizedBox(height: 10),
                Text('사진 수: $imageCount장',
                    style: const TextStyle(color: Color(0xFF625F8C)),
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 100,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFC6DCFF),
                          Color(0xFFD2D1FF),
                          Color(0xFFF5CFFF)
                        ],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '닫기',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const UserIconButton(),
                      const SizedBox(width: 10),
                      const Text(
                        '공유앨범 목록 및 멤버관리',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF625F8C)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _albums.isEmpty
                      ? const Center(
                          child: Text(
                            '생성된 공유 앨범이 없습니다.',
                            style: TextStyle(
                                fontSize: 16, color: Color(0xFF625F8C)),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: 90),
                          child: Column(
                            children: List.generate(_albums.length, (index) {
                              final album = _albums[index];
                              final memberCount =
                                  (album['members'] as List?)?.length ?? 1;

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 10),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF6F9FF),
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 24),
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  album['title'],
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF625F8C),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  '$memberCount',
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w400,
                                                    color: Color(0xFF625F8C),
                                                  ),
                                                ),
                                              ],
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
                                      GestureDetector(
                                        onTap: () =>
                                            _inviteFriendToAlbum(index),
                                        child: const Icon(
                                            Icons.person_add_alt_1,
                                            color: Color(0xFF625F8C)),
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () =>
                                            _showAlbumInfoPopup(album),
                                        child: const Icon(Icons.info_outline,
                                            color: Color(0xFF625F8C)),
                                      ),
                                    ],
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
