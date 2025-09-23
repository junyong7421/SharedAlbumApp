import 'package:flutter/material.dart';
import 'package:sharedalbumapp/services/shared_album_service.dart';

class HeartForEdited extends StatelessWidget {
  final SharedAlbumService svc;
  final String albumId;
  final String editedId;
  final String myUid;
  final double size;

  const HeartForEdited({
    super.key,
    required this.svc,
    required this.albumId,
    required this.editedId,
    required this.myUid,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Set<String>>(
      stream: svc.watchEditedLikedBy(albumId: albumId, editedId: editedId),
      builder: (context, snap) {
        final likedBy = snap.data ?? const <String>{};
        final isLiked = likedBy.contains(myUid);
        final cnt = likedBy.length;

        return GestureDetector(
          onTap: () async {
            try {
              await svc.toggleLikeEdited(
                albumId: albumId,
                editedId: editedId,
                uid: myUid,
                like: !isLiked,
              );
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('좋아요 변경 실패: $e')),
                );
              }
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0,1)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isLiked ? Icons.favorite : Icons.favorite_border,
                  size: size,
                  color: isLiked ? Colors.redAccent : Colors.grey.shade600,
                ),
                if (cnt > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$cnt',
                    style: TextStyle(
                      fontSize: (size * 0.6).clamp(10, 14).toDouble(),
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
