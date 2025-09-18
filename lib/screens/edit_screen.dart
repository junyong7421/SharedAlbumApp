// lib/screens/edit_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'edit_view_screen.dart';
import 'edit_album_list_screen.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../widgets/user_icon_button.dart';
import '../services/shared_album_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // ✅ 하트용 단일 포토 문서 구독

// ===================== UID → 항상 같은 색 (안정 랜덤) =====================
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
  return HSLColor.fromAHSL(1.0, h.toDouble(), saturation, lightness).toColor();
}

// ===================== SegmentedHeart (분할 채우는 하트) =====================
class SegmentedHeart extends StatelessWidget {
  final int totalSlots;           // m명이면 m
  final List<Color> filledColors; // 길이=m
  final double size;
  final bool isLikedByMe;
  final VoidCallback onTap;

  const SegmentedHeart({
    super.key,
    required this.totalSlots,
    required this.filledColors,
    required this.size,
    required this.isLikedByMe,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        size: Size.square(size),
        painter: _HeartPainter(
          totalSlots: totalSlots,
          filledColors: filledColors,
          outlineColor: isLikedByMe ? const Color(0xFF625F8C) : Colors.grey.shade400,
        ),
      ),
    );
  }
}

class _HeartPainter extends CustomPainter {
  final int totalSlots;
  final List<Color> filledColors;
  final Color outlineColor;

  _HeartPainter({
    required this.totalSlots,
    required this.filledColors,
    required this.outlineColor,
  });

  Path _heartPath(Size s) {
    final w = s.width, h = s.height;
    final p = Path();
    final top = Offset(w * 0.5, h * 0.28);
    final leftCtrl1 = Offset(w * 0.15, h * 0.05);
    final leftCtrl2 = Offset(w * 0.02, h * 0.35);
    final left = Offset(w * 0.25, h * 0.58);
    final rightCtrl1 = Offset(w * 0.98, h * 0.35);
    final rightCtrl2 = Offset(w * 0.85, h * 0.05);
    final right = Offset(w * 0.75, h * 0.58);
    final bottom = Offset(w * 0.5, h * 0.95);

    p.moveTo(top.dx, top.dy);
    p.cubicTo(leftCtrl1.dx, leftCtrl1.dy, leftCtrl2.dx, leftCtrl2.dy, left.dx, left.dy);
    p.cubicTo(w * 0.25, h * 0.80, w * 0.40, h * 0.88, bottom.dx, bottom.dy);
    p.cubicTo(w * 0.60, h * 0.88, w * 0.75, h * 0.80, right.dx, right.dy);
    p.cubicTo(rightCtrl2.dx, rightCtrl2.dy, rightCtrl1.dx, rightCtrl1.dy, top.dx, top.dy);
    p.close();
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _heartPath(size);

    if (filledColors.isNotEmpty && totalSlots > 0) {
      // 조각 수 = 좋아요 수(m). 투명 빈칸 없음.
      final step = 1.0 / totalSlots;
      final stops = <double>[];
      final colors = <Color>[];

      for (int i = 0; i < filledColors.length; i++) {
        final start = (step * i).clamp(0.0, 1.0);
        final end = (step * (i + 1)).clamp(0.0, 1.0);
        colors.add(filledColors[i]);
        colors.add(filledColors[i]);
        stops.add(start);
        stops.add(end);
      }

      final rect = Rect.fromLTWH(0, 0, size.width, size.height);
      final shader = SweepGradient(
        startAngle: -3.14159 / 2,
        endAngle: 3 * 3.14159 / 2,
        colors: colors,
        stops: stops,
      ).createShader(rect);

      final fillPaint = Paint()
        ..shader = shader
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.clipPath(path);
      canvas.drawRect(rect, fillPaint);
      canvas.restore();
    }

    final stroke = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.07
      ..isAntiAlias = true;

    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _HeartPainter old) {
    if (totalSlots != old.totalSlots || outlineColor != old.outlineColor) return true;
    if (filledColors.length != old.filledColors.length) return true;
    for (var i = 0; i < filledColors.length; i++) {
      if (filledColors[i].value != old.filledColors[i].value) return true;
    }
    return false;
  }
}

// ===================== HeartForPhoto (좋아요 하트: photoId 기준) =====================
// albums/{albumId}/photos/{photoId}.likedBy 를 실시간 구독해 렌더/토글
class HeartForPhoto extends StatelessWidget {
  final String albumId;
  final String photoId;
  final double size;
  final SharedAlbumService svc;
  final String myUid;

  const HeartForPhoto({
    super.key,
    required this.albumId,
    required this.photoId,
    required this.size,
    required this.svc,
    required this.myUid,
  });

  @override
  Widget build(BuildContext context) {
    final doc = FirebaseFirestore.instance
        .collection('albums')
        .doc(albumId)
        .collection('photos')
        .doc(photoId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: doc.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return SegmentedHeart(
            totalSlots: 0,
            filledColors: const [],
            size: size,
            isLikedByMe: false,
            onTap: () {},
          );
        }

        final data = snap.data!.data()!;
        final List<dynamic> likedDyn = (data['likedBy'] ?? []) as List<dynamic>;
        final likedUids = likedDyn.map((e) => e.toString()).toList();
        final isLikedByMe = likedUids.contains(myUid);

        final m = likedUids.length;
        final totalSlots = m == 0 ? 0 : (m > 12 ? 12 : m); // 가독성 최대 12조각
        final colors = likedUids.map((u) => colorForUid(u)).toList();

        return SegmentedHeart(
          totalSlots: totalSlots,
          filledColors: colors.take(totalSlots).toList(),
          size: size,
          isLikedByMe: isLikedByMe,
          onTap: () async {
            try {
              await svc.toggleLike(
                uid: myUid,
                albumId: albumId,
                photoId: photoId,
                like: !isLikedByMe,
              );
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('좋아요 실패: $e')),
              );
            }
          },
        );
      },
    );
  }
}

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
                    final String? originalPhotoId = current?.originalPhotoId;

                    // 현재 프리뷰 이미지의 고유 키 (재사용/캐시 충돌 방지)
                    final String imageKey = [
                      'editing',
                      current?.source ?? 'original',
                      current?.editedId ?? '',
                      current?.originalPhotoId ?? '',
                      current?.photoId ?? '',
                      current?.photoUrl ?? '',
                    ].join('_');

                    // ✅ 좋아요 타깃: 원본 우선
                    final String? likeTargetPhotoId = (originalPhotoId != null && originalPhotoId.isNotEmpty)
                        ? originalPhotoId
                        : photoId;

                    // 화살표 + 중앙 사진 (+ 하트 오버레이)
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
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              GestureDetector(
                                onTap: hasImages
                                    ? () async {
                                        // 중복 진입 가드
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

                                        // 편집 화면으로 이동 (세션 생성에 성공했을 때만)
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
                                            key: ValueKey(imageKey), // 고유 키
                                            gaplessPlayback: true,   // 전환 시 깜빡임/뒤바뀜 방지
                                          )
                                        : _emptyPreview(),
                                  ),
                                ),
                              ),
                              // ✅ 하트 오버레이 (원본 photoId 또는 photoId가 있을 때만 표시)
                              if (likeTargetPhotoId != null && likeTargetPhotoId.isNotEmpty)
                                Positioned(
                                  top: -6,
                                  right: -6,
                                  child: HeartForPhoto(
                                    albumId: widget.albumId,
                                    photoId: likeTargetPhotoId,
                                    size: 26,
                                    svc: _svc,
                                    myUid: _uid,
                                  ),
                                ),
                            ],
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

                                      final thumbKey = 'edited_${it.id}_${it.originalPhotoId ?? ''}_${it.url}';

                                      // ✅ 좋아요 타깃: 편집본은 원본 photoId가 있을 때만 표시(원본 문서에 좋아요 저장)
                                      final likePhotoId = (it.originalPhotoId ?? '').isNotEmpty
                                          ? it.originalPhotoId!
                                          : null;

                                      return Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          GestureDetector(
                                            onTap: () => _showEditedActions(context, it),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(12),
                                              child: Image.network(
                                                it.url,
                                                width: 100,
                                                height: 100,
                                                fit: BoxFit.cover,
                                                key: ValueKey(thumbKey), // 고유 키
                                                gaplessPlayback: true,
                                              ),
                                            ),
                                          ),
                                          if (likePhotoId != null)
                                            Positioned(
                                              top: -6,
                                              right: -6,
                                              child: HeartForPhoto(
                                                albumId: widget.albumId,
                                                photoId: likePhotoId,
                                                size: 20,
                                                svc: _svc,
                                                myUid: _uid,
                                              ),
                                            ),
                                        ],
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
}
