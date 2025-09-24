import 'package:flutter/material.dart';
import '../services/shared_album_service.dart';
import 'likers_sheet.dart';

class HeartForEdited extends StatelessWidget {
  final String albumId;
  final String editedId;
  final double size;
  final SharedAlbumService svc;
  final String myUid;

  const HeartForEdited({
    super.key,
    required this.albumId,
    required this.editedId,
    required this.size,
    required this.svc,
    required this.myUid,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Set<String>>(
      stream: svc.watchEditedLikedBy(albumId: albumId, editedId: editedId),
      builder: (context, snap) {
        final likedBy = snap.data ?? const <String>{};
        final isLiked = likedBy.contains(myUid);
        final n = likedBy.length;

        return _Badge(
          size: size,
          isLiked: isLiked,
          count: n,
          onTapHeart: () async {
            await svc.toggleLikeEdited(
              albumId: albumId,
              editedId: editedId,
              uid: myUid,
              like: !isLiked,
            );
          },
          onShowLikers: () => LikersSheet.show(
            context,
            title: '좋아요한 사람',
            uids: likedBy,
          ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  final double size;
  final bool isLiked;
  final int count;
  final VoidCallback onTapHeart;
  final VoidCallback onShowLikers;

  const _Badge({
    required this.size,
    required this.isLiked,
    required this.count,
    required this.onTapHeart,
    required this.onShowLikers,
  });

  @override
  Widget build(BuildContext context) {
    final badgeH = size;
    final heartBox = size;
    final radius = badgeH * 0.5;

    return Material(
      color: Colors.white,
      elevation: 1.5,
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        height: badgeH,
        constraints: BoxConstraints(minWidth: heartBox + 20),
        padding: const EdgeInsets.only(right: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 하트: 탭=토글, 롱프레스=리스트
            SizedBox(
              width: heartBox,
              height: heartBox,
              child: InkWell(
                borderRadius: BorderRadius.circular(radius),
                onTap: onTapHeart,
                onLongPress: onShowLikers,          // ← 길게 누르면 모달
                child: Center(
                  child: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    size: heartBox * 0.58,
                    color: isLiked ? const Color(0xFF625F8C) : Colors.grey.shade400,
                  ),
                ),
              ),
            ),
            // 숫자: 탭=리스트
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onShowLikers,                  // ← 숫자 탭해도 모달
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: heartBox * 0.42,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF625F8C),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
