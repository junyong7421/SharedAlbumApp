import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../services/shared_album_service.dart';
import 'edit_screen.dart';
import '../widgets/user_icon_button.dart';

class EditAlbumListScreen extends StatefulWidget {
  const EditAlbumListScreen({super.key});

  @override
  State<EditAlbumListScreen> createState() => _EditAlbumListScreenState();
}

class _EditAlbumListScreenState extends State<EditAlbumListScreen> {
  final _svc = SharedAlbumService.instance;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EBFE),
      bottomNavigationBar: const CustomBottomNavBar(selectedIndex: 0),

      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  UserIconButton(
                    photoUrl: FirebaseAuth.instance.currentUser?.photoURL,
                    radius: 24,
                  ),
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
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F9FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: StreamBuilder<List<Album>>(
                  stream: _svc.watchAlbums(_uid),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF625F8C),
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            '에러: ${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF625F8C)),
                          ),
                        ),
                      );
                    }

                    final items = snapshot.data ?? [];
                    if (items.isEmpty) {
                      return const Center(
                        child: Text(
                          '편집 가능한 공유앨범이 없습니다',
                          style: TextStyle(
                            color: Color(0xFF625F8C),
                            fontSize: 16,
                          ),
                        ),
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: () async {
                        if (!mounted) return;
                        setState(() {});
                      },
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final album = items[index];
                          final memberCount = album.memberUids.length;
                          final photoCount = album.photoCount;

                          return GestureDetector(
                            onTap: () => _openEdit(album),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Image.asset(
                                    'assets/icons/shared_album_list.png',
                                    width: 50,
                                    height: 50,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                album.title,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF625F8C),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            _chip('$memberCount명'),
                                            const SizedBox(width: 6),
                                            // 🔽 여기 변경: 세션 수가 아니라 "편집중인 사진 개수(중복 제거, active+paused 포함)"
                                            FutureBuilder<List<String>>(
                                              future: _svc.fetchEditingPhotoIds(
                                                album.id,
                                              ),
                                              builder: (context, s) {
                                                if (s.connectionState ==
                                                    ConnectionState.waiting) {
                                                  return const SizedBox.shrink();
                                                }
                                                if (s.hasError) {
                                                  return const SizedBox.shrink();
                                                }
                                                final ids =
                                                    s.data ?? const <String>[];
                                                if (ids.isEmpty) {
                                                  return const SizedBox.shrink();
                                                }
                                                return _chipEditing(
                                                  '편집중 ${ids.length}',
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '사진 $photoCount장',
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
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserAvatar() {
    final user = FirebaseAuth.instance.currentUser;
    final photo = user?.photoURL;
    return CircleAvatar(
      radius: 24,
      backgroundImage: (photo != null && photo.isNotEmpty)
          ? NetworkImage(photo)
          : null,
      backgroundColor: const Color(0xFFD9E2FF),
      child: (photo == null || photo.isEmpty)
          ? const Icon(Icons.person, color: Color(0xFF625F8C))
          : null,
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFD9E2FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: Color(0xFF625F8C)),
      ),
    );
  }

  Widget _chipEditing(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE9EC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFACB7)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFFB24C5A),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _openEdit(Album album) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditScreen(albumName: album.title, albumId: album.id),
      ),
    );
    if (!mounted) return;
    setState(() {});
  }
}
