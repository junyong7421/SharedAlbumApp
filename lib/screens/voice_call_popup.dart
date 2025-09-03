import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────
///  경량 모델 (화면에서 쓰는 타입)
/// ─────────────────────────────────────────────────────────
class AlbumLite {
  final String id;
  final String name;
  const AlbumLite({required this.id, required this.name});
}

class MemberLite {
  final String uid;
  final String name; // 없으면 email을 넣어서 넘겨도 됨
  const MemberLite({required this.uid, required this.name});
}

/// ─────────────────────────────────────────────────────────
///  공통 스타일
/// ─────────────────────────────────────────────────────────
const _brand = Color(0xFF625F8C);

BoxDecoration _dialogDecoration() => BoxDecoration(
  color: const Color(0xFFF6F9FF),
  borderRadius: BorderRadius.circular(30),
  border: Border.all(color: _brand, width: 5),
);

LinearGradient _pillGradient() => const LinearGradient(
  colors: [Color(0xFFC6DCFF), Color(0xFFD2D1FF), Color(0xFFF5CFFF)],
);

Widget _title(String text) => Text(
  text,
  style: const TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: _brand,
  ),
);

Widget _bigGradientButton(String label, {VoidCallback? onTap}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: _pillGradient(),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

Widget _smallActionButton(String label, {VoidCallback? onTap}) {
  final disabled = onTap == null;
  return Opacity(
    opacity: disabled ? 0.6 : 1,
    child: IgnorePointer(
      ignoring: disabled,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: _pillGradient(),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      ),
    ),
  );
}

/// ─────────────────────────────────────────────────────────
///  1) 앨범 선택 팝업
///     return: 선택된 albumId (취소 시 null)
/// ─────────────────────────────────────────────────────────
Future<String?> showAlbumSelectPopup(
  BuildContext context, {
  required List<AlbumLite> albums,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true, // 밖을 눌러도 닫힘 (요구사항)
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 22),
        decoration: _dialogDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _title('공유앨범 선택'),
            const SizedBox(height: 16),
            if (albums.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('참여 중인 공유앨범이 없습니다.', style: TextStyle(color: _brand)),
              )
            else
              Column(
                children: [
                  for (int i = 0; i < albums.length; i++) ...[
                    _bigGradientButton(
                      albums[i].name,
                      onTap: () => Navigator.pop(context, albums[i].id),
                    ),
                    if (i != albums.length - 1) const SizedBox(height: 14),
                  ],
                ],
              ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: _smallActionButton('닫기',
                  onTap: () => Navigator.pop(context, null)),
            ),
          ],
        ),
      ),
    ),
  );
}

/// ─────────────────────────────────────────────────────────
///  2) 현재 보이스톡 접속자 팝업 (선택형 아님)
///     - participantsStream 제공 시 실시간 반영
///     - onLeave: '종료' 버튼 눌렀을 때만 호출됨
/// ─────────────────────────────────────────────────────────
Future<void> showVoiceNowPopup(
  BuildContext context, {
  required String albumName,
  required List<MemberLite> initialParticipants,
  Stream<List<MemberLite>>? participantsStream,
  VoidCallback? onLeave,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true, // 밖을 탭해 닫아도 접속 유지
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 22),
        decoration: _dialogDecoration(),
        child: _VoiceNowBody(
          albumName: albumName,
          initialParticipants: initialParticipants,
          participantsStream: participantsStream,
          onLeave: onLeave,
        ),
      ),
    ),
  );
}

class _VoiceNowBody extends StatelessWidget {
  final String albumName;
  final List<MemberLite> initialParticipants;
  final Stream<List<MemberLite>>? participantsStream;
  final VoidCallback? onLeave;

  const _VoiceNowBody({
    required this.albumName,
    required this.initialParticipants,
    this.participantsStream,
    this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    Widget content(List<MemberLite> members) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _title('보이스톡 • $albumName'),
        const SizedBox(height: 16),
        _ParticipantsList(participants: members),
        const SizedBox(height: 22),
        Row(
          children: [
            const Spacer(),
            _smallActionButton('종료', onTap: () async {
              Navigator.pop(context);
              await Future.delayed(const Duration(milliseconds: 10));
              if (onLeave != null) onLeave!();
            }),
          ],
        ),
      ],
    );

    if (participantsStream == null) {
      return content(initialParticipants);
    }

    return StreamBuilder<List<MemberLite>>(
      stream: participantsStream,
      initialData: initialParticipants,
      builder: (context, snap) {
        final members = snap.data ?? initialParticipants;
        return content(members);
      },
    );
  }
}

class _ParticipantsList extends StatelessWidget {
  final List<MemberLite> participants;
  const _ParticipantsList({required this.participants});

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('현재 접속 중인 사용자가 없습니다.', style: TextStyle(color: _brand)),
      );
    }

    return Column(
      children: [
        for (int i = 0; i < participants.length; i++) ...[
          Container(
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: _pillGradient(),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Text(
              participants[i].name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (i != participants.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }
}
