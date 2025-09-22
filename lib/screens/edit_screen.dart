// lib/screens/edit_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart'; // 하트용 단일 포토 문서 구독(유지)
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math; // math.pi, math.min 등
import 'package:vector_math/vector_math_64.dart' as vmath; // Matrix4

import 'edit_view_screen.dart';
import 'edit_album_list_screen.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../widgets/user_icon_button.dart';
import '../services/shared_album_service.dart';
import '../services/shared_album_list_service.dart'; // ✅ uid→이름 변환용

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
  final int totalSlots; // m명이면 m
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
          outlineColor: isLikedByMe
              ? const Color(0xFF625F8C)
              : Colors.grey.shade400,
        ),
      ),
    );
  }
}

class _HeartPainter extends CustomPainter {
  final int totalSlots;           // m명이면 m
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

  Future<void> _showLikedByPopup(BuildContext context, List<String> likedUids) async {
    // 앨범 멤버 조회로 uid→이름 매핑
    final members =
        await SharedAlbumListService.instance.fetchAlbumMembers(albumId);
    final names = members
        .where((m) => likedUids.contains(m.uid))
        .map((m) => (m.name).trim().isEmpty ? m.email : m.name)
        .toList();

    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (_) => LikedByPopup(memberNames: names),
    );
  }

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
          // 하트만(빈 상태) + 숫자 0
          return _HeartWithCount(
            size: size,
            totalSlots: 0,
            colors: const [],
            isLikedByMe: false,
            count: 0,
            onTapHeart: () {},
            onTapCount: () {},
          );
        }

        final data = snap.data!.data()!;
        final List<dynamic> likedDyn = (data['likedBy'] ?? []) as List<dynamic>;
        final likedUids = likedDyn.map((e) => e.toString()).toList();
        final isLikedByMe = likedUids.contains(myUid);

        final m = likedUids.length;
        final totalSlots = m == 0 ? 0 : (m > 12 ? 12 : m);
        final colors = likedUids.map((u) => colorForUid(u)).toList();

        return _HeartWithCount(
          size: size,
          totalSlots: totalSlots,
          colors: colors.take(totalSlots).toList(),
          isLikedByMe: isLikedByMe,
          count: m,
          onTapHeart: () async {
            try {
              await svc.toggleLike(
                uid: myUid,
                albumId: albumId,
                photoId: photoId,
                like: !isLikedByMe,
              );
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('좋아요 실패: $e')));
            }
          },
          onTapCount: () => _showLikedByPopup(context, likedUids),
        );
      },
    );
  }
}

/// 하트 + 숫자 묶음 (Row)
class _HeartWithCount extends StatelessWidget {
  final double size;
  final int totalSlots;
  final List<Color> colors;
  final bool isLikedByMe;
  final int count;
  final VoidCallback onTapHeart; // 하트 토글
  final VoidCallback onTapCount; // 팝업 열기 (칩 전체)

  const _HeartWithCount({
    required this.size,
    required this.totalSlots,
    required this.colors,
    required this.isLikedByMe,
    required this.count,
    required this.onTapHeart,
    required this.onTapCount,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);

    return Material(
      color: Colors.white.withOpacity(0.90),
      elevation: 0,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTapCount, // ✅ 칩 전체 탭 → 팝업
        child: Container(
          constraints: const BoxConstraints(minHeight: 28, minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 3,
                offset: Offset(1, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 하트만 탭하면 좋아요 토글 (부모 onTap과 충돌 없이 동작)
              SegmentedHeart(
                totalSlots: totalSlots,
                filledColors: colors,
                size: size,
                isLikedByMe: isLikedByMe,
                onTap: onTapHeart,
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: const TextStyle(
                  color: Color(0xFF625F8C),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LikedByPopup extends StatelessWidget {
  final List<String> memberNames;

  const LikedByPopup({super.key, required this.memberNames});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFF6F9FF),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
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
                '하트 누른 사람',
                style: TextStyle(
                  color: Color(0xFF625F8C),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),

              Expanded(
                child: memberNames.isEmpty
                    ? const Center(
                        child: Text(
                          '아직 아무도 하트를 누르지 않았습니다.',
                          style: TextStyle(color: Color(0xFF625F8C)),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: memberNames.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (_, i) => _GradientPillButton(
                          text: memberNames[i],
                          onTap: () => Navigator.pop(context),
                        ),
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
  }
}

class _GradientPillButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  const _GradientPillButton({required this.text, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
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
      ),
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
  String get _meName => FirebaseAuth.instance.currentUser?.displayName ?? '';

  // 빠른 연타/중복 진입 가드
  bool _isNavigating = false;

  // ===================== 표시 이름 캐시 =====================
  final Map<String, String> _nameCache = {};

  // uid → 표시 이름 조회(users/{uid}.displayName → users/{uid}.name → auth.displayName → fallback)
  Future<String> _displayNameFor(String uid, {String? prefer}) async {
    // 1) 스트림에서 넘어온 이름이 있으면 최우선 사용
    final hint = prefer?.trim();
    if (hint != null && hint.isNotEmpty) return _nameCache[uid] = hint;

    // 2) 캐시
    if (_nameCache.containsKey(uid)) return _nameCache[uid]!;

    // 3) 내 계정이면 auth.displayName
    if (uid == _uid) {
      final me = FirebaseAuth.instance.currentUser;
      final dn = (me?.displayName ?? '').trim();
      if (dn.isNotEmpty) return _nameCache[uid] = dn;
    }

    // 4) users/{uid} 조회
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = doc.data();
      final dn = (data?['displayName'] ?? data?['name'] ?? '')
          .toString()
          .trim();
      if (dn.isNotEmpty) return _nameCache[uid] = dn;
    } catch (_) {}

    // 5) fallback: uid 끝 4자리
    final short = uid.length > 4 ? uid.substring(uid.length - 4) : uid;
    return _nameCache[uid] = '사용자-$short';
  }

  // 처음 들어간(lead) 편집자 고르기: startedAt → updatedAt → uid 안정 정렬
  EditingInfo _pickLeadEditor(List<EditingInfo> editors) {
    final sorted = [...editors]
      ..sort((a, b) {
        final sa = a.startedAt ?? a.updatedAt;
        final sb = b.startedAt ?? b.updatedAt;
        if (sa != null && sb != null) {
          final cmp = sa.compareTo(sb); // 오래된(먼저 들어간) 순
          if (cmp != 0) return cmp;
        }
        return (a.uid ?? '').compareTo(b.uid ?? '');
      });
    return sorted.first;
  }

  // "채희석 편집중.." / "채희석 외 N명 편집중.." 라벨
  Widget _editorsLine(List<EditingInfo> editors) {
    if (editors.isEmpty) return const SizedBox.shrink();
    final lead = _pickLeadEditor(editors);
    final others = editors.length - 1;
    final leadUid = (lead.uid ?? '').trim();
    if (leadUid.isEmpty) return const SizedBox.shrink();

    // lead.userDisplayName를 우선 사용
    final prefer = (lead.userDisplayName ?? '').trim();

    return FutureBuilder<String>(
      future: _displayNameFor(
        leadUid,
        prefer: prefer.isNotEmpty ? prefer : null,
      ),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final leadName = snap.data!;
        final text = (others <= 0)
            ? '$leadName 편집중..'
            : '$leadName 외 $others명 편집중..';

        // 화면 톤과 맞춘 칩 UI
        return Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF3CD), Color(0xFFFFE6A7)],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 3,
                  offset: Offset(1, 1),
                ),
              ],
            ),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF8A6D3B),
                fontWeight: FontWeight.w700,
              ),
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
            // 자동 갱신
            ListView(
              padding: EdgeInsets.zero,
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
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 24,
                        right: 24,
                        bottom: 8,
                      ),
                      child: Row(
                        children: [
                          Container(
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
                          const Spacer(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 앨범 전체 편집중 목록: Stream (자동 갱신)
                    StreamBuilder<List<EditingInfo>>(
                      stream: _svc.watchEditingForAlbum(widget.albumId),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting &&
                            !snap.hasData) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: CircularProgressIndicator(
                                color: Color(0xFF625F8C),
                              ),
                            ),
                          );
                        }
                        if (snap.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                '편집 세션을 불러오지 못했습니다.\n${snap.error}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF625F8C),
                                ),
                              ),
                            ),
                          );
                        }

                        final raw = snap.data ?? const <EditingInfo>[];

                        // URL 없는 항목 제거 + 같은 사진 중복 제거 (photoId/editedId/originalPhotoId 기준)
                        final filtered = raw
                            .where((e) => (e.photoUrl).trim().isNotEmpty)
                            .toList();
                        final seen = <String>{};
                        final list = <EditingInfo>[];
                        for (final e in filtered) {
                          final k =
                              (e.photoId ??
                              e.editedId ??
                              e.originalPhotoId ??
                              '');
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

                        final EditingInfo? current = hasImages
                            ? list[_currentIndex]
                            : null;
                        final String? url = current?.photoUrl;
                        final String? photoId = current?.photoId;
                        final String? originalPhotoId =
                            current?.originalPhotoId;

                        // 이미지 키 (캐시 무시용)
                        final String imageKey = [
                          'editing',
                          current?.source ?? 'original',
                          current?.editedId ?? '',
                          current?.originalPhotoId ?? '',
                          current?.photoId ?? '',
                          current?.photoUrl ?? '',
                          (current?.updatedAt?.millisecondsSinceEpoch ?? 0)
                              .toString(),
                        ].join('_');

                        // 좋아요 타깃: 원본 우선
                        final String? likeTargetPhotoId =
                            (originalPhotoId != null &&
                                originalPhotoId.isNotEmpty)
                            ? originalPhotoId
                            : photoId;

                        // 현재 프리뷰와 같은 대상의 편집자들 추출
                        List<EditingInfo> currentEditors = const [];
                        if (current != null) {
                          final keyOrig = (originalPhotoId ?? '').trim();
                          final keyPhoto = (photoId ?? '').trim();
                          final keyEdited = (current.editedId ?? '').trim();

                          currentEditors = raw.where((e) {
                            final eOrig = (e.originalPhotoId ?? '').trim();
                            final ePhoto = (e.photoId ?? '').trim();
                            final eEdited = (e.editedId ?? '').trim();

                            if (keyOrig.isNotEmpty)
                              return eOrig == keyOrig || ePhoto == keyOrig;
                            if (keyPhoto.isNotEmpty)
                              return ePhoto == keyPhoto || eOrig == keyPhoto;
                            if (keyEdited.isNotEmpty)
                              return eEdited == keyEdited;
                            return false;
                          }).toList();
                        }

                        // 프리뷰 & 네비게이션
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
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  GestureDetector(
                                    onTap: hasImages
                                        ? () async {
                                            if (_isNavigating) return;
                                            _isNavigating = true;

                                            final String? _editedId =
                                                current?.editedId;
                                            final String? _originalPhotoId =
                                                current?.originalPhotoId;
                                            final String? _photoId = photoId;
                                            final String? _url = url;

                                            if (_url == null || _url.isEmpty) {
                                              _isNavigating = false;
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    '이미지 URL이 유효하지 않습니다.',
                                                  ),
                                                ),
                                              );
                                              return;
                                            }

                                            try {
                                              await _svc.setEditing(
                                                uid: _uid,
                                                albumId: widget.albumId,
                                                photoId:
                                                    _originalPhotoId ??
                                                    _photoId,
                                                photoUrl: _url,
                                                source:
                                                    (_editedId ?? '').isNotEmpty
                                                    ? 'edited'
                                                    : 'original',
                                                editedId: _editedId,
                                                originalPhotoId:
                                                    _originalPhotoId ??
                                                    _photoId,
                                                // 👇 이름 저장
                                                userDisplayName: _meName,
                                              );
                                            } catch (e) {
                                              _isNavigating = false;
                                              if (!mounted) return;
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    '편집 세션 생성 실패: $e',
                                                  ),
                                                ),
                                              );
                                              return;
                                            }

                                            if (!mounted) {
                                              _isNavigating = false;
                                              return;
                                            }

                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    EditViewScreen(
                                                      albumName:
                                                          widget.albumName,
                                                      albumId: widget.albumId,
                                                      imagePath: _url,
                                                      editedId: _editedId,
                                                      originalPhotoId:
                                                          _originalPhotoId,
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

                                  // 하트 오버레이
                                  if (likeTargetPhotoId != null &&
                                      likeTargetPhotoId.isNotEmpty)
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
                                        _currentIndex =
                                            (_currentIndex + 1) % list.length;
                                      })
                                    : null,
                                color: hasImages ? null : Colors.black26,
                              ),
                            ],
                          ),
                        );

                        // 배지 표시
                        final editorsArea = _editorsLine(currentEditors);

                        return Column(
                          children: [
                            preview,
                            editorsArea,
                            const SizedBox(height: 30),

                            // 편집된 사진 라벨
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(
                                  left: 24,
                                  bottom: 8,
                                ),
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

                            // 편집본 목록(실시간)
                            Center(
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
                                child: StreamBuilder<List<EditedPhoto>>(
                                  stream: _svc.watchEditedPhotos(
                                    widget.albumId,
                                  ),
                                  builder: (context, editedSnap) {
                                    if (editedSnap.connectionState ==
                                            ConnectionState.waiting &&
                                        !editedSnap.hasData) {
                                      return const Center(
                                        child: CircularProgressIndicator(
                                          color: Color(0xFF625F8C),
                                        ),
                                      );
                                    }
                                    if (editedSnap.hasError) {
                                      return Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Text(
                                            '편집된 사진을 불러오는 중 오류가 발생했습니다.\n${editedSnap.error}',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Color(0xFF625F8C),
                                            ),
                                          ),
                                        ),
                                      );
                                    }

                                    final edited =
                                        editedSnap.data ??
                                        const <EditedPhoto>[];

                                    // 편집 중인 editedId를 빼기 위해 세션 스트림과 합성
                                    return StreamBuilder<List<EditingInfo>>(
                                      stream: _svc.watchEditingForAlbum(
                                        widget.albumId,
                                      ),
                                      builder: (context, sessSnap) {
                                        final sessions =
                                            sessSnap.data ??
                                            const <EditingInfo>[];

                                        final activeEditedIds = <String>{};
                                        for (final e in sessions) {
                                          final id = (e.editedId ?? '').trim();
                                          if (id.isNotEmpty)
                                            activeEditedIds.add(id);
                                        }

                                        final visible = edited
                                            .where(
                                              (it) => !activeEditedIds.contains(
                                                it.id,
                                              ),
                                            )
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
                                          separatorBuilder: (_, __) =>
                                              const SizedBox(width: 8),
                                          itemCount: visible.length,
                                          itemBuilder: (_, i) {
                                            final it = visible[i];
                                            final thumbKey =
                                                'edited_${it.id}_${it.originalPhotoId ?? ''}_${it.url}';

                                            // 좋아요 타깃: 편집본은 원본 photoId가 있을 때만 표시
                                            final likePhotoId =
                                                (it.originalPhotoId ?? '')
                                                    .isNotEmpty
                                                ? it.originalPhotoId!
                                                : null;

                                            return Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                GestureDetector(
                                                  onTap: () =>
                                                      _showEditedActions(
                                                        context,
                                                        it,
                                                      ),
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    child: Image.network(
                                                      it.url,
                                                      width: 100,
                                                      height: 100,
                                                      fit: BoxFit.cover,
                                                      key: ValueKey(thumbKey),
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
                                    );
                                  },
                                ),
                              ),
                            ),

                            const SizedBox(height: 40),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 110), // 바텀바 침범 방지
                  ],
                ),
              ],
            ),

            // 하단 네비게이션 바
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: const CustomBottomNavBar(selectedIndex: 2),
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
          style: TextStyle(
            color: Color(0xFF625F8C),
            fontWeight: FontWeight.w600,
          ),
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

                  if (_isNavigating) return;
                  _isNavigating = true;

                  try {
                    await _svc.setEditing(
                      uid: _uid,
                      albumId: widget.albumId,
                      // 편집본 열 때도 photoId를 원본 id로 채움 → 집계 일관성
                      photoId: (item.originalPhotoId ?? '').isNotEmpty
                          ? item.originalPhotoId
                          : null,
                      photoUrl: item.url,
                      source: 'edited',
                      editedId: item.id,
                      originalPhotoId: ((item.originalPhotoId ?? '').isNotEmpty)
                          ? item.originalPhotoId
                          : null,
                      // 👇 이름 저장
                      userDisplayName: _meName,
                    );
                  } catch (e) {
                    _isNavigating = false;
                    if (!mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('편집 세션 생성 실패: $e')));
                    return;
                  }

                  if (!mounted) {
                    _isNavigating = false;
                    return;
                  }

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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('편집된 사진을 삭제했습니다.')),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
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
