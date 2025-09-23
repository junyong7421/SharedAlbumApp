import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../widgets/user_icon_button.dart';
import 'edit_view_screen.dart';
import 'dart:math';
import 'dart:math' as math; // math.pi, math.min 등
import 'package:vector_math/vector_math_64.dart' as vmath; // Matrix4
import 'package:cloud_firestore/cloud_firestore.dart';
// 서비스 + 모델 (Album, Photo 포함)
import '../services/shared_album_service.dart';
import 'package:http/http.dart' as http;
import 'package:photo_manager/photo_manager.dart';
import 'dart:typed_data'; // [추가] saveImage에 필요

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

  // 중복 네비게이션 가드
  bool _isNavigating = false;

  @override
  void dispose() {
    _albumNameController.dispose();
    super.dispose();
  }

  // ====================== 색 유틸 (UID → 항상 동일한 색) ======================
  int _stableHash(String s) {
    int h = 5381;
    for (int i = 0; i < s.length; i++) {
      h = ((h << 5) + h) ^ s.codeUnitAt(i);
    }
    return h & 0x7fffffff;
  }

  Color colorForUid(
    String uid, {
    double saturation = 0.75,
    double lightness = 0.55,
  }) {
    final h = _stableHash(uid) % 360;
    return HSLColor.fromAHSL(
      1.0,
      h.toDouble(),
      saturation,
      lightness,
    ).toColor();
  }

  // ====================== SegmentedHeart 위젯 (분할 하트) ======================
  Widget segmentedHeart({
    required int totalSlots,
    required List<Color> filledColors,
    required double size,
    required bool isLikedByMe,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        size: Size.square(size),
        painter: _HeartPainter(
          totalSlots: totalSlots,
          filledColors: filledColors,
          outlineColor: isLikedByMe
              ? const Color(0xFF625F8C)
              : Colors.grey.shade400,
        ),
      ),
    );
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
    }
  }

  Future<void> _downloadOriginalPhoto(String url) async {
    try {
      // 1) 사진 권한 요청
      final PermissionState ps = await PhotoManager.requestPermissionExtend();
      if (!ps.hasAccess) {
        if (!mounted) return;
        final go = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('권한이 필요합니다'),
            content: const Text('갤러리에 저장하려면 사진 권한이 필요해요. 설정에서 허용해 주세요.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('설정 열기'),
              ),
            ],
          ),
        );
        if (go == true) {
          await PhotoManager.openSetting();
        }
        return;
      }

      // 2) 다운로드
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) {
        throw '다운로드 실패(${res.statusCode})';
      }

      // 3) 갤러리 저장
      final bytes = res.bodyBytes;
      final filename =
          'SharedAlbum_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final asset = await PhotoManager.editor.saveImage(
        Uint8List.fromList(bytes),
        filename: filename,
      );
      final ok = asset != null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? '갤러리에 저장했어요.' : '저장에 실패했습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('다운로드 오류: $e')));
      }
    }
  }

  // ---------------------- 편집 화면 진입 공용 함수 ----------------------
  Future<void> _openEditor({
    required Photo photo,
    required String albumId,
    required String albumTitle,
  }) async {
    if (_isNavigating) return;
    _isNavigating = true;

    // await 전에 NavigatorState 확보
    final nav = Navigator.of(context);

    try {
      await _svc.setEditing(
        uid: _uid,
        albumId: albumId,
        photoUrl: photo.url,
        source: 'original',
        photoId: photo.id,
        originalPhotoId: photo.id,
      );

      if (!mounted) return;
      await nav.push(
        MaterialPageRoute(
          builder: (_) => EditViewScreen(
            albumName: albumTitle,
            albumId: albumId,
            imagePath: photo.url,
            originalPhotoId: photo.id,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('편집 화면 진입 실패: $e')));
      }
    } finally {
      _isNavigating = false;
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
                children: [
                  // [변경] UserIconButton에 photoUrl 전달 (로그아웃 다이얼로그 기능 그대로)
                  UserIconButton(
                    photoUrl:
                        FirebaseAuth.instance.currentUser?.photoURL, // [추가]
                    radius: 24, // [유지/선택]
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    '공유앨범',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF625F8C),
                    ),
                  ),
                  const Spacer(),
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
      stream: _svc.watchAlbums(_uid),
      builder: (context, snap) {
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

  // 좋아요한 사람 팝업: likedBy(uid 리스트) → 이름 조회해서 표시
  Future<void> _showLikedByPopup(List<String> likedUids) async {
    if (!mounted) return;

    if (likedUids.isEmpty) {
      await showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: const Color(0xFFF6F9FF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFF625F8C), width: 3),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    '좋아요한 사람',
                    style: TextStyle(
                      color: Color(0xFF625F8C),
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    '아직 아무도 하트를 누르지 않았어요.',
                    style: TextStyle(color: Color(0xFF625F8C)),
                  ),
                  SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      );
      return;
    }

    // Firestore users 컬렉션에서 이름 조회 (whereIn 10개 제한 → 청크로)
    final fs = FirebaseFirestore.instance;
    final List<String> names = [];
    try {
      for (int i = 0; i < likedUids.length; i += 10) {
        final chunk = likedUids.skip(i).take(10).toList();
        final qs = await fs
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        final got = qs.docs.map((d) {
          final m = d.data();
          final display = (m['displayName'] ?? m['name'] ?? '')
              .toString()
              .trim();
          if (display.isNotEmpty) return display;
          final short = d.id.length > 4
              ? d.id.substring(d.id.length - 4)
              : d.id;
          return '사용자-$short';
        }).toList();
        names.addAll(got);
      }
    } catch (_) {
      // 조회 실패 시 uid 뒷 4자리로 대체
      for (final u in likedUids) {
        final short = u.length > 4 ? u.substring(u.length - 4) : u;
        names.add('사용자-$short');
      }
    }

    await showDialog(
      context: context,
      builder: (_) {
        return Dialog(
          backgroundColor: const Color(0xFFF6F9FF),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFF625F8C), width: 3),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '좋아요한 사람',
                    style: TextStyle(
                      color: Color(0xFF625F8C),
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 16),

                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemBuilder: (context, i) =>
                          _GradientPillButton(text: names[i]),
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemCount: names.length,
                    ),
                  ),
                  const SizedBox(height: 8),

                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const _GradientPillButton(text: '닫기'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildExpandedAlbumView() {
    final albumId = _selectedAlbumId!;
    final title = _selectedAlbumTitle ?? '앨범';

    final albumDocRef = FirebaseFirestore.instance
        .collection('albums')
        .doc(albumId);

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Color(0xFF625F8C)),
              onPressed: () {
                if (_selectedImageIndex != null) {
                  setState(() {
                    _selectedImageIndex = null;
                  });
                } else {
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
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: albumDocRef.snapshots(),
            builder: (context, albumSnap) {
              if (albumSnap.hasError) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '앨범 정보를 불러올 수 없습니다',
                      style: TextStyle(color: Color(0xFF625F8C)),
                    ),
                  ),
                );
              }
              if (!albumSnap.hasData || !albumSnap.data!.exists) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF625F8C)),
                );
              }
              final albumData = albumSnap.data!.data()!;
              final List<String> albumMembers =
                  ((albumData['memberUids'] ?? []) as List)
                      .map((e) => e.toString())
                      .toList();

              final totalSlots = max(1, min(albumMembers.length, 12));

              return StreamBuilder<List<Photo>>(
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
                      child: CircularProgressIndicator(
                        color: Color(0xFF625F8C),
                      ),
                    );
                  }

                  final photos = snap.data ?? [];
                  if (photos.isEmpty) {
                    return const Center(
                      child: Text(
                        '사진이 없습니다',
                        style: TextStyle(
                          color: Color(0xFF625F8C),
                          fontSize: 16,
                        ),
                      ),
                    );
                  }

                  if (_selectedImageIndex == null) {
                    // ===================== 그리드(썸네일) =====================
                    return GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: photos.length,
                      itemBuilder: (context, i) {
                        final p = photos[i];
                        final likedUids = p.likedBy;
                        final isLikedByMe = likedUids.contains(_uid);
                        final likedColors = likedUids
                            .map((u) => colorForUid(u))
                            .toList();

                        final m = likedUids.length;
                        final totalSlotsForRender = m == 0
                            ? 0
                            : (m > 12 ? 12 : m);

                        return GestureDetector(
                          onTap: () => setState(() => _selectedImageIndex = i),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(
                                  p.url,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                              ),
                              Positioned(
                                right: 6,
                                bottom: 6,
                                child: _LikeBadge(
                                  likedUids: p.likedBy,
                                  myUid: _uid,
                                  albumId: albumId,
                                  photoId: p.id,
                                  svc: _svc,
                                  colorForUid:
                                      colorForUid, // 이미 파일 상단에 있는 함수 그대로 전달
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  } else {
                    // ===================== 큰 사진 (PageView) =====================
                    final controller = PageController(
                      initialPage: _selectedImageIndex!,
                    );
                    return PageView.builder(
                      controller: controller,
                      itemCount: photos.length,
                      onPageChanged: (i) =>
                          setState(() => _selectedImageIndex = i),
                      itemBuilder: (context, i) {
                        final p = photos[i];
                        final likedUids = p.likedBy;
                        final isLikedByMe = likedUids.contains(_uid);
                        final likedColors = likedUids
                            .map((u) => colorForUid(u))
                            .toList();

                        final m = likedUids.length;
                        final totalSlotsForRender = m == 0
                            ? 0
                            : (m > 12 ? 12 : m);

                        return Column(
                          children: [
                            Align(
                              alignment: Alignment.topRight,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  bottom: 10,
                                  right: 4,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment
                                      .end, // **[추가] 오른쪽 정렬 유지**
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 버튼 1줄 (폭이 부족하면 자동 줄바꿈)
                                    Wrap(
                                      // **[변경] Row → Wrap**
                                      alignment: WrapAlignment.end, // **[추가]**
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center, // **[추가]**
                                      spacing: 8, // **[추가] 버튼 간 간격**
                                      runSpacing: 8, // **[추가] 줄바꿈 시 세로 간격**
                                      children: [
                                        GestureDetector(
                                          onTap: () => _openEditor(
                                            photo: p,
                                            albumId: albumId,
                                            albumTitle: title,
                                          ),
                                          child: _pill("편집하기"),
                                        ),
                                        GestureDetector(
                                          onTap: () async {
                                            await _downloadOriginalPhoto(p.url);
                                          },
                                          child: _pill("다운로드"),
                                        ),
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
                                                SnackBar(
                                                  content: Text('삭제 실패: $e'),
                                                ),
                                              );
                                            }
                                          },
                                          child: _pill("삭제"),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(
                                      height: 8,
                                    ), // **[추가] 버튼줄과 하트줄 간격**
                                    // 하트 배지: 아래 줄에 분리
                                    _LikeBadge(
                                      // **[추가]**
                                      likedUids: p.likedBy,
                                      myUid: _uid,
                                      albumId: albumId,
                                      photoId: p.id,
                                      svc: _svc,
                                      colorForUid: colorForUid,
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
              );
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

// CallGroupPopup 느낌의 그라데이션 알약 버튼 (radius=150)
class _GradientPillButton extends StatelessWidget {
  final String text;
  const _GradientPillButton({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(150),
        gradient: const LinearGradient(
          colors: [Color(0xFFC6DCFF), Color(0xFFD2D1FF), Color(0xFFF5CFFF)],
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }
}

/// 하트+숫자 캡슐 배지 (스샷 스타일)
class _LikeBadge extends StatelessWidget {
  final List<String> likedUids;
  final String myUid;
  final String albumId;
  final String photoId;
  final SharedAlbumService svc;
  final Color Function(String uid) colorForUid;
  final int maxSlices; // 12 고정 사용

  const _LikeBadge({
    required this.likedUids,
    required this.myUid,
    required this.albumId,
    required this.photoId,
    required this.svc,
    required this.colorForUid,
    this.maxSlices = 12,
  });

  @override
  Widget build(BuildContext context) {
    final isLikedByMe = likedUids.contains(myUid);
    final m = likedUids.length;
    final total = m == 0 ? 0 : (m > maxSlices ? maxSlices : m);
    final colors = likedUids.map(colorForUid).take(total).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 하트 (탭 = 토글)
          GestureDetector(
            onTap: () async {
              try {
                await svc.toggleLike(
                  uid: myUid,
                  albumId: albumId,
                  photoId: photoId,
                  like: !isLikedByMe,
                );
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('좋아요 실패: $e')));
              }
            },
            child: CustomPaint(
              size: const Size.square(22),
              painter: _HeartPainter(
                totalSlots: total,
                filledColors: colors,
                outlineColor: isLikedByMe
                    ? const Color(0xFF625F8C)
                    : Colors.grey.shade400,
              ),
            ),
          ),

          const SizedBox(width: 6),

          // 숫자 동그라미 (탭 = 팝업)
          GestureDetector(
            onTap: () async {
              // 부모 State의 메서드를 그대로 쓴다면: context.findAncestorStateOfType 등으로 호출해도 되지만
              // SharedAlbumScreen의 private 메서드를 그대로 쓰고 있으므로 간단히 showDialog를 이 안에서 구현
              final liked = likedUids; // 캡처
              if (liked.isEmpty) {
                await showDialog(
                  context: context,
                  builder: (_) => Dialog(
                    backgroundColor: const Color(0xFFF6F9FF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: const BorderSide(
                        color: Color(0xFF625F8C),
                        width: 3,
                      ),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(20, 24, 20, 24),
                      child: Text(
                        '아직 아무도 하트를 누르지 않았어요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF625F8C)),
                      ),
                    ),
                  ),
                );
                return;
              }

              // 이름 조회 → 팝업
              final fs = FirebaseFirestore.instance;
              final names = <String>[];
              try {
                for (int i = 0; i < liked.length; i += 10) {
                  final chunk = liked.skip(i).take(10).toList();
                  final qs = await fs
                      .collection('users')
                      .where(FieldPath.documentId, whereIn: chunk)
                      .get();
                  names.addAll(
                    qs.docs.map((d) {
                      final m = d.data();
                      final n = (m['displayName'] ?? m['name'] ?? '')
                          .toString()
                          .trim();
                      if (n.isNotEmpty) return n;
                      final short = d.id.length > 4
                          ? d.id.substring(d.id.length - 4)
                          : d.id;
                      return '사용자-$short';
                    }),
                  );
                }
              } catch (_) {
                for (final u in liked) {
                  final short = u.length > 4 ? u.substring(u.length - 4) : u;
                  names.add('사용자-$short');
                }
              }

              await showDialog(
                context: context,
                builder: (_) => Dialog(
                  backgroundColor: const Color(0xFFF6F9FF),
                  insetPadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: const BorderSide(color: Color(0xFF625F8C), width: 3),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 420,
                      maxHeight: 520,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '좋아요한 사람',
                            style: TextStyle(
                              color: Color(0xFF625F8C),
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: names.length,
                              itemBuilder: (c, i) => Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(150),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFC6DCFF),
                                      Color(0xFFD2D1FF),
                                      Color(0xFFF5CFFF),
                                    ],
                                  ),
                                ),
                                child: Text(
                                  names[i],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                            ),
                          ),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(150),
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFC6DCFF),
                                    Color(0xFFD2D1FF),
                                    Color(0xFFF5CFFF),
                                  ],
                                ),
                              ),
                              child: const Text(
                                '닫기',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFE6E6EB),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                '${likedUids.length}',
                style: const TextStyle(
                  color: Color(0xFF4C4A64),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ====================== 하트 페인터 ======================
class _HeartPainter extends CustomPainter {
  final int totalSlots; // m명이면 m
  final List<Color> filledColors; // 길이=m
  final Color outlineColor;

  _HeartPainter({
    required this.totalSlots,
    required this.filledColors,
    required this.outlineColor,
  });

  // Material favorite(24x24)과 유사한 하트 Path
  // *정확히 동일 좌표가 아니더라도 아이콘스러운 '진짜 하트' 실루엣입니다.
  Path _materialLikeHeart24() {
    final p = Path();
    // 위 중앙에서 시작해 좌측 볼 → 바닥 포인트 → 우측 볼 → 위 중앙 폐합
    p.moveTo(12.0, 6.0);
    p.cubicTo(9.5, 3.5, 5.2, 4.0, 4.0, 7.6);
    p.cubicTo(3.2, 10.0, 4.5, 12.7, 7.0, 14.9);
    p.cubicTo(8.8, 16.5, 10.7, 18.0, 12.0, 19.1);
    p.cubicTo(13.3, 18.0, 15.2, 16.5, 17.0, 14.9);
    p.cubicTo(19.5, 12.7, 20.8, 10.0, 20.0, 7.6);
    p.cubicTo(18.8, 4.0, 14.5, 3.5, 12.0, 6.0);
    p.close();
    return p;
  }

  // 화면 size에 맞게 24x24 벡터를 스케일 & 센터링
  Path _heartPath(Size s) {
    final base = _materialLikeHeart24();
    const vbW = 24.0, vbH = 24.0;
    final scale = math.min(s.width / vbW, s.height / vbH);
    final dx = (s.width - vbW * scale) / 2.0;
    final dy = (s.height - vbH * scale) / 2.0;

    final m = vmath.Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scale, scale);
    return base.transform(m.storage);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final heart = _heartPath(size);

    // 1) 하트 내부만 그리도록 clip
    canvas.save();
    canvas.clipPath(heart);

    // 2) 채우기 (한 명이면 단색, m명이면 m등분)
    final m = totalSlots.clamp(0, filledColors.length);
    if (m > 0) {
      if (m == 1) {
        final paint = Paint()
          ..color = filledColors.first
          ..style = PaintingStyle.fill;
        canvas.drawRect(Offset.zero & size, paint);
      } else {
        // m등분: 2명이면 좌/우 반반이 보이도록 9시 방향(-π)부터 시작
        final sweep = 2 * math.pi / m;
        final start0 = -math.pi;
        final b = heart.getBounds();
        final center = b.center;
        final r = b.longestSide * 0.85; // 하트를 충분히 덮도록 반지름 여유
        final rect = Rect.fromCircle(center: center, radius: r);

        for (int i = 0; i < m; i++) {
          final paint = Paint()
            ..color = filledColors[i]
            ..style = PaintingStyle.fill;
          canvas.drawArc(rect, start0 + i * sweep, sweep, true, paint);
        }
      }
    }
    canvas.restore();

    // 3) 외곽선
    final border = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.shortestSide * 0.10).clamp(1.2, 3.0)
      ..isAntiAlias = true;

    canvas.drawPath(heart, border);
  }

  @override
  bool shouldRepaint(covariant _HeartPainter old) {
    if (totalSlots != old.totalSlots || outlineColor != old.outlineColor)
      return true;
    if (filledColors.length != old.filledColors.length) return true;
    for (var i = 0; i < filledColors.length; i++) {
      if (filledColors[i].value != old.filledColors[i].value) return true;
    }
    return false;
  }
}
