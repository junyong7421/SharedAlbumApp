// lib/screens/edit_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
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

  // 빠른 연타/중복 진입 가드
  bool _isNavigating = false;

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
                    // 에러/로딩 핸들링
                    if (snap.hasError) {
                      return Expanded(
                        child: Center(
                          child: Text(
                            '편집 세션을 불러오지 못했습니다.\n${snap.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF625F8C)),
                          ),
                        ),
                      );
                    }

                    final raw = snap.data ?? const <EditingInfo>[];

                    // TTL(20s) 클라 필터
                    final now = DateTime.now();
                    final ttl = now.subtract(const Duration(seconds: 20));
                    final ttlFiltered = raw.where((e) => (e.updatedAt?.toDate().isAfter(ttl) ?? false)).toList();

                    // URL 없는 항목 제거 + 같은 사진 중복 제거(프레즌스 키 기준)
                    final filtered = ttlFiltered.where((e) => (e.photoUrl).trim().isNotEmpty).toList();
                    final seen = <String>{};
                    final list = <EditingInfo>[];
                    for (final e in filtered) {
                      final k = (e.photoId ?? e.editedId ?? e.originalPhotoId ?? '');
                      if (k.isEmpty) continue;
                      if (seen.add(k)) list.add(e);
                    }

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

                    // 현재 프리뷰 이미지의 고유 키 (재사용/캐시 충돌 방지)
                    final String imageKey = [
                      'editing',
                      current?.source ?? 'original',
                      current?.editedId ?? '',
                      current?.originalPhotoId ?? '',
                      current?.photoId ?? '',
                      current?.photoUrl ?? '',
                    ].join('_');

                    // 프레즌스 요약 표시용 키
                    final String? presenceKey = current == null
                        ? null
                        : (current.photoId ?? current.editedId ?? current.originalPhotoId);

                    // 화살표 + 중앙 사진
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
                                    if (_isNavigating) return;
                                    _isNavigating = true;

                                    // 현재 항목 로컬 변수로 캡처
                                    final String? _editedId = current?.editedId;
                                    final String? _originalPhotoId = current?.originalPhotoId;
                                    final String? _photoId = photoId;
                                    final String? _url = url;

                                    if (_url == null || _url.isEmpty) {
                                      _isNavigating = false;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('이미지 URL이 유효하지 않습니다.')),
                                      );
                                      return;
                                    }

                                    try {
                                      await _svc.setEditing(
                                        uid: _uid,
                                        albumId: widget.albumId,
                                        photoId: _photoId, // 안정 키
                                        photoUrl: _url,
                                        source: (_editedId ?? '').isNotEmpty ? 'edited' : 'original',
                                        editedId: _editedId,
                                        originalPhotoId: _originalPhotoId ?? _photoId,
                                      );
                                    } catch (e) {
                                      _isNavigating = false;
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('편집 세션 생성 실패: $e')),
                                      );
                                      return;
                                    }

                                    if (!mounted) {
                                      _isNavigating = false;
                                      return;
                                    }

                                    // 편집 화면으로 이동
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => EditViewScreen(
                                          albumName: widget.albumName,
                                          albumId: widget.albumId,
                                          imagePath: _url,
                                          editedId: _editedId,
                                          originalPhotoId: _originalPhotoId,
                                          photoId: _photoId,
                                        ),
                                      ),
                                    );

                                    _isNavigating = false;
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
                                        key: ValueKey(imageKey),
                                        gaplessPlayback: true,
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

                          // 중앙 프리뷰 아래 “편집 중: A 외 N명” 뱃지
                          if (presenceKey != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: _editingBadge(
                                albumId: widget.albumId,
                                photoPresenceKey: presenceKey,
                              ),
                            ),

                          const SizedBox(height: 30),

                          // 편집된 사진 (edited/*)
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

                          // 저장된 편집본 목록(현재 편집 중인 편집본은 숨기기)
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
                                builder: (context, editedSnap) {
                                  if (editedSnap.connectionState == ConnectionState.waiting) {
                                    return const Center(
                                      child: CircularProgressIndicator(color: Color(0xFF625F8C)),
                                    );
                                  }
                                  if (editedSnap.hasError) {
                                    return Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Text(
                                          '편집된 사진을 불러오는 중 오류가 발생했습니다.\n${editedSnap.error}',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: Color(0xFF625F8C)),
                                        ),
                                      ),
                                    );
                                  }

                                  // 편집 세션도 같이 구독해서 active editedId를 필터링
                                  return StreamBuilder<List<EditingInfo>>(
                                    stream: _svc.watchEditingForAlbum(widget.albumId),
                                    builder: (context, editingSnap) {
                                      final edited = editedSnap.data ?? const <EditedPhoto>[];

                                      final activeEditedIds = <String>{};
                                      if (editingSnap.hasData) {
                                        for (final e in editingSnap.data!) {
                                          final id = (e.editedId ?? '').trim();
                                          if (id.isNotEmpty) activeEditedIds.add(id);
                                        }
                                      }

                                      // 현재 편집 중(세션 active)인 편집본은 숨김
                                      final visible = edited
                                          .where((it) => !activeEditedIds.contains(it.id))
                                          .toList();

                                      if (visible.isEmpty) {
                                        return const Center(
                                          child: Text(
                                            '편집된 사진이 없습니다',
                                            style: TextStyle(
                                              color: Color(0xFF625F8C),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        );
                                      }

                                      return ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        padding: const EdgeInsets.all(12),
                                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                                        itemCount: visible.length,
                                        itemBuilder: (_, i) {
                                          final it = visible[i];
                                          final thumbKey =
                                              'edited_${it.id}_${it.originalPhotoId ?? ''}_${it.url}';

                                          return GestureDetector(
                                            onTap: () => _showEditedActions(context, it),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(12),
                                              child: Image.network(
                                                it.url,
                                                width: 100,
                                                height: 100,
                                                fit: BoxFit.cover,
                                                key: ValueKey(thumbKey),
                                                gaplessPlayback: true,
                                              ),
                                            ),
                                          );
                                        },
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

  // 하단 액션: 편집된 사진 탭 시
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

                  // 중복 진입 가드
                  if (_isNavigating) return;
                  _isNavigating = true;

                  // 편집 세션 등록 (편집본에서 재편집 시작)
                  try {
                    await _svc.setEditing(
                      uid: _uid,
                      albumId: widget.albumId,
                      photoId: null, // 편집본은 photoId 없을 수 있음
                      photoUrl: item.url,
                      source: 'edited',
                      editedId: item.id,
                      originalPhotoId: ((item.originalPhotoId ?? '').isNotEmpty)
                          ? item.originalPhotoId
                          : null,
                    );
                  } catch (e) {
                    _isNavigating = false;
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('편집 세션 생성 실패: $e')),
                    );
                    return;
                  }

                  if (!mounted) {
                    _isNavigating = false;
                    return;
                  }

                  // 편집 화면으로 이동 (덮어쓰기 모드)
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditViewScreen(
                        albumName: widget.albumName,
                        albumId: widget.albumId,
                        imagePath: item.url,
                        editedId: item.id,
                      ),
                    ),
                  );

                  _isNavigating = false;
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

  // 중앙 프리뷰 아래 "편집 중: A 외 N명" 배지 위젯
  Widget _editingBadge({
    required String albumId,
    required String photoPresenceKey,
  }) {
    return StreamBuilder<firestore.DocumentSnapshot<Map<String, dynamic>>>(
      stream: _svc.editingSummaryStream(albumId: albumId, photoId: photoPresenceKey),
      builder: (context, snap) {
        if (!snap.hasData || !(snap.data?.exists ?? false)) {
          return const SizedBox(height: 0);
        }
        final data = snap.data!.data()!;
        final isEditing = data['isEditing'] == true;
        final count = (data['editorsCount'] ?? 0) as int;
        final top = (data['topEditorName'] ?? '') as String;

        if (!isEditing || count <= 0) {
          return const SizedBox(height: 0);
        }

        final label = count == 1 ? top : '$top 외 ${count - 1}명';

        return Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3CD),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
          ),
          child: Text(
            '편집 중: $label',
            style: const TextStyle(fontSize: 12, color: Color(0xFF8A6D3B), fontWeight: FontWeight.w600),
          ),
        );
      },
    );
  }
}