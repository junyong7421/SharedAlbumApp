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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFC6DCFF), Color(0xFFD2D1FF), Color(0xFFF5CFFF)],
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
                        MaterialPageRoute(builder: (context) => const EditAlbumListScreen()),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.only(left: 24, bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFC6DCFF), Color(0xFFD2D1FF), Color(0xFFF5CFFF)],
                        ),
                      ),
                      child: const Text(
                        '편집 목록',
                        style: TextStyle(color: Color(0xFFF6F9FF), fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),

                // 편집 중인 사진 라벨
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(left: 24, bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [Color(0xFFC6DCFF), Color(0xFFD2D1FF), Color(0xFFF5CFFF)],
                      ),
                    ),
                    child: const Text(
                      '편집 중인 사진',
                      style: TextStyle(color: Color(0xFFF6F9FF), fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 앨범 전체 편집중 목록 실시간 구독
                StreamBuilder<List<EditingInfo>>(
                  stream: _svc.watchEditingForAlbum(widget.albumId),
                  builder: (context, snap) {
                    final list = snap.data ?? const <EditingInfo>[];
                    final hasImages = list.isNotEmpty;

                    if (hasImages) {
                      _currentIndex = _currentIndex % list.length;
                      if (_currentIndex < 0) _currentIndex = 0;
                    } else {
                      _currentIndex = 0;
                    }

                    final EditingInfo? current = hasImages ? list[_currentIndex] : null;
                    final String? url = current?.photoUrl;
                    final String? photoId = current?.photoId;

                    // === 화살표 + 중앙 사진 ===
                    final preview = Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_left, size: 32),
                            onPressed: hasImages
                                ? () => setState(() {
                                      _currentIndex = (_currentIndex - 1 + list.length) % list.length;
                                    })
                                : null,
                            color: hasImages ? null : Colors.black26,
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: hasImages
                                ? () async {
                                    // ✅ [변경] 진입 전에 내 편집 세션 생성(공동 편집 가시성/락)
                                    try {
                                      await _svc.setEditing(
                                        uid: _uid,
                                        albumId: widget.albumId,
                                        photoUrl: url!, // 현재 보여주는 이미지
                                        source: (current?.editedId ?? '').isNotEmpty
                                            ? 'edited'
                                            : 'original', // ✅ [변경] null-safe
                                        editedId: current?.editedId, // ✅ [변경] null-safe
                                        originalPhotoId: current?.originalPhotoId ?? current?.photoId, // ✅ [변경]
                                      );
                                    } catch (_) {}

                                    // ✅ [변경] photoId도 함께 전달(있으면)
                                    if (!mounted) return;
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => EditViewScreen(
                                          albumName: widget.albumName,
                                          albumId: widget.albumId,
                                          imagePath: url!,
                                          editedId: current?.editedId, // ✅ [변경] null-safe
                                          originalPhotoId: current?.originalPhotoId, // ✅ [변경] null-safe
                                          photoId: photoId, // ✅ [변경]
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
                                  BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(2, 2)),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: hasImages
                                    ? Image.network(
                                        url!,
                                        fit: BoxFit.cover,
                                        key: ValueKey('${photoId ?? url}'), // ✅ [변경] 캐시 꼬임 방지
                                      )
                                    : _emptyPreview(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.arrow_right, size: 32),
                            onPressed: hasImages
                                ? () => setState(() {
                                      _currentIndex = (_currentIndex + 1) % list.length;
                                    })
                                : null,
                            color: hasImages ? null : Colors.black26,
                          ),
                        ],
                      ),
                    );

                    return Expanded(
                      child: Column(
                        children: [
                          preview,
                          const SizedBox(height: 30),

                          // ====== 편집된 사진 (edited/*) ======
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(left: 24, bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFC6DCFF), Color(0xFFD2D1FF), Color(0xFFF5CFFF)],
                                ),
                              ),
                              child: const Text(
                                '편집된 사진',
                                style: TextStyle(color: Color(0xFFF6F9FF), fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 저장된 편집본 목록
                          Center(
                            child: Container(
                              width: 300,
                              height: 180,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(2, 2)),
                                ],
                              ),
                              child: StreamBuilder<List<EditedPhoto>>(
                                stream: _svc.watchEditedPhotos(widget.albumId),
                                builder: (context, snap2) {
                                  if (snap2.connectionState == ConnectionState.waiting) {
                                    return const Center(
                                      child: CircularProgressIndicator(color: Color(0xFF625F8C)),
                                    );
                                  }
                                  if (snap2.hasError) {
                                    return Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Text(
                                          '편집된 사진을 불러오는 중 오류가 발생했습니다.\n${snap2.error}',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: Color(0xFF625F8C)),
                                        ),
                                      ),
                                    );
                                  }

                                  final edited = snap2.data ?? const <EditedPhoto>[];
                                  if (edited.isEmpty) {
                                    return const Center(
                                      child: Text(
                                        '편집된 사진이 없습니다',
                                        style: TextStyle(color: Color(0xFF625F8C), fontWeight: FontWeight.w500),
                                      ),
                                    );
                                  }

                                  return ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.all(12),
                                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                                    itemCount: edited.length,
                                    itemBuilder: (_, i) {
                                      final it = edited[i];
                                      return GestureDetector(
                                        onTap: () => _showEditedActions(context, it),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Image.network(
                                            it.url,
                                            width: 100,
                                            height: 100,
                                            fit: BoxFit.cover,
                                            key: ValueKey(it.id), // ✅ [변경]
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 110), // 바텀바 침범 방지
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

  Widget _emptyPreview() {
    return Container(
      color: const Color(0xFFF0F3FF),
      child: const Center(
        child: Text(
          '편집 중인 사진 없음',
          style: TextStyle(color: Color(0xFF625F8C), fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // === 하단 액션: 편집된 사진 탭 시 ===
  void _showEditedActions(BuildContext context, EditedPhoto item) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('편집하기'),
                onTap: () async {
                  Navigator.pop(context);

                  // ✅ [변경] 편집 세션 등록 (편집본에서 재편집 시작)
                  try {
                    await _svc.setEditing(
                      uid: _uid,
                      albumId: widget.albumId,
                      photoUrl: item.url,
                      source: 'edited',
                      editedId: item.id,
                      originalPhotoId: ((item.originalPhotoId ?? '').isNotEmpty)
                          ? item.originalPhotoId
                          : null,
                    );
                  } catch (_) {}

                  // 편집 화면으로 이동 (덮어쓰기 모드)
                  if (!mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditViewScreen(
                        albumName: widget.albumName,
                        albumId: widget.albumId,
                        imagePath: item.url,
                        editedId: item.id,
                        // photoId는 EditedPhoto 모델에 없으므로 생략
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('삭제'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    await _svc.deleteEditedPhoto(
                      albumId: widget.albumId,
                      editedId: item.id,
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('편집된 사진을 삭제했습니다.')));
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
