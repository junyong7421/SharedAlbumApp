import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'edit_view_screen.dart';
import 'edit_album_list_screen.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../widgets/user_icon_button.dart';
import '../services/shared_album_service.dart';

class EditScreen extends StatefulWidget {
  final String albumName;
  final String albumId;

  const EditScreen({super.key, required this.albumName, required this.albumId});

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  int _currentIndex = 0;

  final _svc = SharedAlbumService.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EBFE),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상단 사용자 정보
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
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFC6DCFF),
                              Color(0xFFD2D1FF),
                              Color(0xFFF5CFFF),
                            ],
                          ),
                        ),
                        child: Text(
                          widget.albumName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFFFFFFF),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // 편집 목록 버튼
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const EditAlbumListScreen(),
                        ),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.only(left: 24, bottom: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFC6DCFF),
                            Color(0xFFD2D1FF),
                            Color(0xFFF5CFFF),
                          ],
                        ),
                      ),
                      child: const Text(
                        '편집 목록',
                        style: TextStyle(
                          color: Color(0xFFF6F9FF),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),

                // 편집 중인 사진 라벨
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(left: 24, bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFC6DCFF),
                          Color(0xFFD2D1FF),
                          Color(0xFFF5CFFF),
                        ],
                      ),
                    ),
                    child: const Text(
                      '편집 중인 사진',
                      style: TextStyle(
                        color: Color(0xFFF6F9FF),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 🔹 앨범 전체 편집중 목록 실시간 구독
                StreamBuilder<List<EditingInfo>>(
                  stream: _svc.watchEditingForAlbum(widget.albumId),
                  builder: (context, snap) {
                    final list = snap.data ?? const <EditingInfo>[];
                    final hasImages = list.isNotEmpty;

                    // 목록 크기 변화에도 안전한 인덱스
                    if (hasImages) {
                      _currentIndex %= list.length;
                      if (_currentIndex < 0) _currentIndex = 0;
                    } else {
                      _currentIndex = 0;
                    }

                    final String? url =
                        hasImages ? list[_currentIndex].photoUrl : null;

                    // === 화살표 + 중앙 사진 ===
                    final preview = Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_left, size: 32),
                            onPressed: hasImages
                                ? () => setState(() {
                                      _currentIndex =
                                          (_currentIndex - 1 + list.length) %
                                              list.length;
                                    })
                                : null,
                            color: hasImages ? null : Colors.black26,
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: hasImages
                                ? () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => EditViewScreen(
                                          imagePath: url!,
                                          albumName: widget.albumName,
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                            child: Container(
                              width: 140,
                              height: 160,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF6F9FF),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 5,
                                    offset: Offset(2, 2),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: hasImages
                                    ? Image.network(url!, fit: BoxFit.cover)
                                    : _emptyPreview(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.arrow_right, size: 32),
                            onPressed: hasImages
                                ? () => setState(() {
                                      _currentIndex =
                                          (_currentIndex + 1) % list.length;
                                    })
                                : null,
                            color: hasImages ? null : Colors.black26,
                          ),
                        ],
                      ),
                    );

                    // === 편집된 사진(썸네일 리스트) ===
                    final editedThumbs = Center(
                      child: Container(
                        width: 300,
                        height: 180,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: Offset(2, 2),
                            ),
                          ],
                        ),
                        child: hasImages
                            ? ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.all(12),
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 8),
                                itemCount: list.length,
                                itemBuilder: (_, i) {
                                  final it = list[i];
                                  return GestureDetector(
                                    onTap: () {
                                      setState(() => _currentIndex = i);
                                    },
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.network(
                                        it.photoUrl,
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  );
                                },
                              )
                            : _emptyThumbs(),
                      ),
                    );

                    return Expanded(
                      child: Column(
                        children: [
                          preview,
                          const SizedBox(height: 30),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              margin:
                                  const EdgeInsets.only(left: 24, bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFC6DCFF),
                                    Color(0xFFD2D1FF),
                                    Color(0xFFF5CFFF),
                                  ],
                                ),
                              ),
                              child: const Text(
                                '편집된 사진',
                                style: TextStyle(
                                  color: Color(0xFFF6F9FF),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          editedThumbs,
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 70),
              ],
            ),

            // 하단 네비게이션 바
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

  // 빈 상태 위젯들
  Widget _emptyPreview() {
    return Container(
      color: const Color(0xFFF0F3FF),
      child: const Center(
        child: Text(
          '편집 중인 사진 없음',
          style: TextStyle(
            color: Color(0xFF625F8C),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _emptyThumbs() {
    return Center(
      child: Text(
        '편집된 사진이 없습니다',
        style: TextStyle(
          color: const Color(0xFF625F8C).withOpacity(0.9),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}