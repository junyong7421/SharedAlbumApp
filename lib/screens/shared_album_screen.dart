import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../widgets/user_icon_button.dart';
import 'edit_view_screen.dart';

// 서비스 + 모델 (Album, Photo 포함)
import '../services/shared_album_service.dart';

class SharedAlbumScreen extends StatefulWidget {
  const SharedAlbumScreen({super.key});

  @override
  State<SharedAlbumScreen> createState() => _SharedAlbumScreenState();
}

class _SharedAlbumScreenState extends State<SharedAlbumScreen> {
  final _svc = SharedAlbumService.instance;
  final _albumNameController = TextEditingController();

  String? _selectedAlbumId; // 상세 진입 시 사용
  String? _selectedAlbumTitle; // 상세 상단/리네임 다이얼로그 기본값
  int? _selectedImageIndex;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  @override
  void dispose() {
    _albumNameController.dispose();
    super.dispose();
  }

  // ---------------------- Dialogs ----------------------

  void _showAddAlbumDialog() {
    _albumNameController.clear();
    showDialog(
      context: context,
      builder: (_) {
        return Dialog(
          backgroundColor: const Color(0xFFF6F9FF),
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFF625F8C), width: 2),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Text(
                    "새 앨범 만들기",
                    style: TextStyle(
                      fontSize: 20,
                      color: Color(0xFF625F8C),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _albumNameController,
                  cursorColor: const Color(0xFF625F8C),
                  style: const TextStyle(color: Color(0xFF625F8C)),
                  decoration: InputDecoration(
                    hintText: "앨범 이름을 입력하세요.",
                    hintStyle: const TextStyle(color: Color(0xFF625F8C)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: const BorderSide(color: Color(0xFF625F8C)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: const BorderSide(
                        color: Color(0xFF625F8C),
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  onSubmitted: (_) => _onCreateAlbum(),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _pillButton("취소", () => Navigator.pop(context)),
                    _pillButton("확인", _onCreateAlbum),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _onCreateAlbum() async {
    final name = _albumNameController.text.trim();
    if (name.isEmpty) return;
    try {
      await _svc.createAlbum(uid: _uid, title: name);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('앨범이 생성되었습니다.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('생성 실패: $e')));
    }
  }

  void _showRenameAlbumDialog({
    required String albumId,
    required String currentTitle,
  }) {
    final controller = TextEditingController(text: currentTitle);
    showDialog(
      context: context,
      builder: (_) {
        return Dialog(
          backgroundColor: const Color(0xFFF6F9FF),
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFF625F8C), width: 2),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Text(
                    "앨범 이름 변경",
                    style: TextStyle(
                      fontSize: 20,
                      color: Color(0xFF625F8C),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: controller,
                  cursorColor: const Color(0xFF625F8C),
                  style: const TextStyle(color: Color(0xFF625F8C)),
                  decoration: InputDecoration(
                    hintText: "새 이름을 입력하세요",
                    hintStyle: const TextStyle(color: Color(0xFF625F8C)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: const BorderSide(color: Color(0xFF625F8C)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: const BorderSide(
                        color: Color(0xFF625F8C),
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _pillButton("취소", () => Navigator.pop(context)),
                    _pillButton("변경", () async {
                      final newName = controller.text.trim();
                      if (newName.isEmpty || newName == currentTitle) {
                        Navigator.pop(context);
                        return;
                      }
                      try {
                        await _svc.renameAlbum(
                          uid: _uid,
                          albumId: albumId,
                          newTitle: newName,
                        );
                        if (!mounted) return;
                        setState(() => _selectedAlbumTitle = newName);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('앨범명이 변경되었습니다.')),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('변경 실패: $e')));
                      }
                    }),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------- Actions ----------------------

  Future<void> _addPhotos(String albumId) async {
    try {
      await _svc.addPhotosFromGallery(
        uid: _uid,
        albumId: albumId,
        allowMultiple: true,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('업로드 실패: $e')));
    }
  }

  Future<void> _deleteAlbum(String albumId) async {
    try {
      await _svc.deleteAlbum(uid: _uid, albumId: albumId);
      if (!mounted) return;
      setState(() {
        if (_selectedAlbumId == albumId) {
          _selectedAlbumId = null;
          _selectedAlbumTitle = null;
          _selectedImageIndex = null;
        }
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('앨범이 삭제되었습니다.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
    }
  }

  // ---------------------- Build ----------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EBFE),
      bottomNavigationBar: const Padding(
        padding: EdgeInsets.only(bottom: 40, left: 20, right: 20),
        child: CustomBottomNavBar(selectedIndex: 0),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: const [
                  UserIconButton(),
                  SizedBox(width: 10),
                  Text(
                    '공유앨범',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF625F8C),
                    ),
                  ),
                  Spacer(),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(40, 0, 40, 60),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F9FF),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Column(
                  children: [
                    if (_selectedAlbumId == null) ...[
                      _buildSharedAlbumHeader(),
                      const SizedBox(height: 12),
                    ],
                    Expanded(
                      child: _selectedAlbumId == null
                          ? _buildMainAlbumList()
                          : _buildExpandedAlbumView(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSharedAlbumHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [Color(0xFFC6DCFF), Color(0xFFD2D1FF), Color(0xFFF5CFFF)],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Shared Album',
            style: TextStyle(
              color: Color(0xFF625F8C),
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          GestureDetector(
            onTap: _showAddAlbumDialog,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Color(0xFF625F8C),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------- Album List ----------------------

  Widget _buildMainAlbumList() {
    return StreamBuilder<List<Album>>(
      stream: _svc.watchAlbums(
        _uid,
      ), // memberUids array-contains + updatedAt desc
      builder: (context, snap) {
        // 에러 표시 (인덱스/권한 문제 진단)
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '에러: ${snap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF625F8C)),
              ),
            ),
          );
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF625F8C)),
          );
        }

        final albums = snap.data ?? [];
        if (albums.isEmpty) {
          return const Center(
            child: Text(
              '아직 생성된 앨범이 없습니다',
              style: TextStyle(color: Color(0xFF625F8C), fontSize: 16),
            ),
          );
        }

        return ListView.builder(
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedAlbumId = album.id;
                    _selectedAlbumTitle = album.title;
                    _selectedImageIndex = null;
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFD9E2FF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              album.title,
                              style: const TextStyle(
                                color: Color(0xFF625F8C),
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.add_photo_alternate,
                              color: Color(0xFF625F8C),
                            ),
                            tooltip: '사진 추가',
                            onPressed: () => _addPhotos(album.id),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.edit,
                              color: Color(0xFF625F8C),
                            ),
                            tooltip: '이름 변경',
                            onPressed: () => _showRenameAlbumDialog(
                              albumId: album.id,
                              currentTitle: album.title,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: Color(0xFF625F8C),
                            ),
                            onPressed: () => _deleteAlbum(album.id),
                          ),
                        ],
                      ),
                      if (album.coverPhotoUrl != null &&
                          album.coverPhotoUrl!.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            album.coverPhotoUrl!,
                            width: double.infinity,
                            height: 180,
                            fit: BoxFit.cover,
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            '사진 ${album.photoCount}장',
                            style: const TextStyle(color: Color(0xFF625F8C)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------- Album Detail ----------------------

  Widget _buildExpandedAlbumView() {
    final albumId = _selectedAlbumId!;
    final title = _selectedAlbumTitle ?? '앨범';

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Color(0xFF625F8C)),
              onPressed: () {
                if (_selectedImageIndex != null) {
                  // 단일 사진 보기 중이면 → 그리드로만 복귀
                  setState(() {
                    _selectedImageIndex = null;
                  });
                } else {
                  // 그리드(앨범 상세)면 → 앨범 목록으로 복귀
                  setState(() {
                    _selectedAlbumId = null;
                    _selectedAlbumTitle = null;
                    _selectedImageIndex = null;
                  });
                }
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF625F8C),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: Color(0xFF625F8C)),
              tooltip: '이름 변경',
              onPressed: () =>
                  _showRenameAlbumDialog(albumId: albumId, currentTitle: title),
            ),
            IconButton(
              icon: const Icon(
                Icons.add_photo_alternate,
                color: Color(0xFF625F8C),
              ),
              tooltip: '사진 추가',
              onPressed: () => _addPhotos(albumId),
            ),
          ],
        ),
        const SizedBox(height: 8),

        Expanded(
          child: StreamBuilder<List<Photo>>(
            stream: _svc.watchPhotos(uid: _uid, albumId: albumId),
            builder: (context, snap) {
              if (snap.hasError) {
                final uid = FirebaseAuth.instance.currentUser?.uid;
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '에러: ${snap.error}\nuid: $uid',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF625F8C)),
                    ),
                  ),
                );
              }

              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF625F8C)),
                );
              }

              final photos = snap.data ?? [];
              if (photos.isEmpty) {
                return const Center(
                  child: Text(
                    '사진이 없습니다',
                    style: TextStyle(color: Color(0xFF625F8C), fontSize: 16),
                  ),
                );
              }

              if (_selectedImageIndex == null) {
                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: photos.length,
                  itemBuilder: (context, i) {
                    final p = photos[i];
                    return GestureDetector(
                      onTap: () => setState(() => _selectedImageIndex = i),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(p.url, fit: BoxFit.cover),
                      ),
                    );
                  },
                );
              } else {
                final controller = PageController(
                  initialPage: _selectedImageIndex!,
                );
                return PageView.builder(
                  controller: controller,
                  itemCount: photos.length,
                  onPageChanged: (i) => setState(() => _selectedImageIndex = i),
                  itemBuilder: (context, i) {
                    final p = photos[i];
                    return Column(
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              bottom: 10,
                              right: 4,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () async {
                                    // 1. 편집 상태 Firestore에 저장
                                    await _svc.setEditing(
                                      uid: _uid,
                                      albumId: albumId,
                                      photoId: p.id,
                                      photoUrl: p.url,
                                    );

                                    // 2. 편집 화면으로 이동
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => EditViewScreen(
                                          albumName: title,
                                          imagePath: p.url,
                                          albumId: albumId,
                                        ),
                                      ),
                                    );
                                  },
                                  child: _pill("편집하기"),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () async {
                                    try {
                                      await _svc.deletePhoto(
                                        uid: _uid,
                                        albumId: albumId,
                                        photoId: p.id,
                                      );
                                    } catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text('삭제 실패: $e')),
                                      );
                                    }
                                  },
                                  child: _pill("삭제"),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.network(
                              p.url,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              }
            },
          ),
        ),
      ],
    );
  }

  // ---------------------- Small UI helpers ----------------------

  Widget _pillButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFFC6DCFF), Color(0xFFD2D1FF), Color(0xFFF5CFFF)],
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFFC6DCFF), Color(0xFFD2D1FF), Color(0xFFF5CFFF)],
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
