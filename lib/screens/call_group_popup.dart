import 'package:flutter/material.dart';
import '../services/shared_album_list_service.dart';

/// 통화용 그룹 선택 팝업 (보라 테두리, gradient 버튼 radius=150)
class CallGroupPopup extends StatelessWidget {
  final List<SharedAlbumListItem> albums;
  final void Function(SharedAlbumListItem album)? onSelect;

  const CallGroupPopup({super.key, required this.albums, this.onSelect});

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
                '그룹 선택',
                style: TextStyle(
                  color: Color(0xFF625F8C),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),

              Expanded(
                child: albums.isEmpty
                    ? const Center(
                        child: Text(
                          '표시할 그룹이 없습니다.',
                          style: TextStyle(color: Color(0xFF625F8C)),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemBuilder: (context, i) {
                          final album = albums[i];
                          return _GradientPillButton(
                            text: album.name,
                            onTap: () {
                              if (onSelect != null) onSelect!(album);
                              Navigator.pop(context, album);
                            },
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemCount: albums.length,
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

/// radius=150, 그라데이션 알약 버튼
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
          borderRadius: BorderRadius.circular(150), // ← radius 150
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
