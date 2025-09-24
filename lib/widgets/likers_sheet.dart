import 'package:flutter/material.dart';

class LikersSheet extends StatelessWidget {
  final String title;
  final List<String> uids;

  const LikersSheet({
    super.key,
    required this.title,
    required this.uids,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required Iterable<String> uids,
  }) {
    return showModalBottomSheet(
      context: context,
      useRootNavigator: true, // ← 가장 바깥 네비게이터로 강제
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => LikersSheet(title: title, uids: uids.toList()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xFF625F8C),
      const Color(0xFF397CFF),
      const Color(0xFFF5CFFF),
      const Color(0xFFC6DCFF),
      const Color(0xFFD2D1FF),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 4,
              width: 44,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: Color(0xFF625F8C),
              ),
            ),
            const SizedBox(height: 12),
            if (uids.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  '아직 아무도 좋아요를 누르지 않았어요.',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: uids.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final uid = uids[i];
                    final color = colors[i % colors.length];
                    // 여기서 uid → 닉네임 매핑 원하면 Firestore users 컬렉션 조회로 바꿔도 됨.
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: color.withOpacity(0.15),
                        child: Icon(Icons.favorite, color: color),
                      ),
                      title: Text(uid, maxLines: 1, overflow: TextOverflow.ellipsis),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
