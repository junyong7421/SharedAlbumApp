import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/shared_album_list_service.dart';
import '../widgets/user_icon_button.dart';
// 팝업 / 오버레이
import 'voice_call_popup.dart';
import 'voice_call_overlay.dart';

// 하단 커스텀 네비바
import '../widgets/custom_bottom_nav_bar.dart';

class SharedAlbumListScreen extends StatefulWidget {
  const SharedAlbumListScreen({super.key});

  @override
  State<SharedAlbumListScreen> createState() => _SharedAlbumListScreenState();
}

class _SharedAlbumListScreenState extends State<SharedAlbumListScreen> {
  final _svc = SharedAlbumListService.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EBFE),

      // 하단 네비게이션바
      bottomNavigationBar: const Padding(
        padding: EdgeInsets.only(bottom: 20, left: 20, right: 20),
        child: CustomBottomNavBar(selectedIndex: 1),
      ),

      body: SafeArea(
        child: Column(
          children: [
            // 헤더
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  UserIconButton(
                    photoUrl: FirebaseAuth.instance.currentUser?.photoURL,
                    radius: 24,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    '공유앨범 목록 및 멤버관리',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF625F8C),
                    ),
                  ),
                  const Spacer(),

                  // 전화 아이콘 (접속 중이면 팝업/오버레이, 아니면 앨범 선택 → 입장)
                  GestureDetector(
                    onTap: _onTapCall,
                    child: Image.asset(
                      'assets/icons/call_off.png',
                      width: 50,
                      height: 50,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // 앨범 목록
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F9FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: StreamBuilder<List<SharedAlbumListItem>>(
                  stream: _svc.watchMySharedAlbums(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF625F8C),
                        ),
                      );
                    }

                    final items = snapshot.data ?? [];
                    if (items.isEmpty) {
                      return const Center(
                        child: Text(
                          '참여 중인 공유앨범이 없습니다',
                          style: TextStyle(
                            color: Color(0xFF625F8C),
                            fontSize: 16,
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final album = items[index];
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Image.asset(
                                'assets/icons/shared_album_list.png',
                                width: 50,
                                height: 50,
                              ),
                              const SizedBox(width: 16),

                              // 텍스트 영역
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            album.name,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF625F8C),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _chip('${album.memberCount}명'),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '사진 ${album.photoCount}장',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF625F8C),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(width: 8),

                              // 버튼들
                              _pillButton(
                                label: '멤버추가',
                                onTap: () =>
                                    _onAddMembers(album.id, album.memberUids),
                              ),
                              const SizedBox(width: 6),
                              _pillButton(
                                label: '상세정보',
                                onTap: () => _showMemberDetails(album.id),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------- Actions --------------------

  /// 전화 아이콘 탭
  Future<void> _onTapCall() async {
    try {
      final me = FirebaseAuth.instance.currentUser;
      if (me == null) return;

      // A) 이미 접속 중인가? → 오버레이 보장 + 접속자 팝업
      final activeAlbumId = await _svc.getMyActiveVoiceAlbumId();
      if (activeAlbumId != null) {
        // 앨범 이름 조회
        final myAlbums = await _svc.watchMySharedAlbums().first;
        final albumName = myAlbums
            .firstWhere(
              (a) => a.id == activeAlbumId,
              orElse: () => SharedAlbumListItem(
                id: activeAlbumId,
                name: '보이스톡',
                ownerUid: '',
                memberUids: const [],
                photoCount: 0,
                createdAt: null,
                updatedAt: null,
              ),
            )
            .name;

        // ★ 실제 연결 여부와 무관하게 1회 join 보장 (이미 붙어 있으면 내부에서 스킵)
        await _svc.joinVoice(albumId: activeAlbumId);

        // 오버레이 표시
        voiceOverlay.show(albumId: activeAlbumId, albumName: albumName);

        // 참가자 팝업
        final stream = _svc
            .watchVoiceParticipants(activeAlbumId)
            .map(
              (list) => list
                  .map(
                    (m) => MemberLite(
                      uid: m.uid,
                      name: m.name.isNotEmpty ? m.name : m.email,
                    ),
                  )
                  .toList(),
            );
        final initial = await stream.first;

        await showVoiceNowPopup(
          context,
          albumName: albumName,
          initialParticipants: initial,
          participantsStream: stream,
          onLeave: () async {
            await _svc.leaveVoice(albumId: activeAlbumId);
            voiceOverlay.hide();
          },
        );
        return;
      }

      // B) 접속 중이 아니면: 앨범 선택 → 입장 → 오버레이 → 접속자 팝업
      final albums = await _svc.watchMySharedAlbums().first;
      final albumLites = albums
          .map((a) => AlbumLite(id: a.id, name: a.name))
          .toList();

      final selectedAlbumId = await showAlbumSelectPopup(
        context,
        albums: albumLites,
      );
      if (selectedAlbumId == null) return;

      final selectedAlbum = albumLites.firstWhere(
        (e) => e.id == selectedAlbumId,
      );

      await _svc.joinVoice(albumId: selectedAlbumId);

      // 접속과 동시에 오버레이 표시
      voiceOverlay.show(
        albumId: selectedAlbumId,
        albumName: selectedAlbum.name,
      );

      final stream = _svc
          .watchVoiceParticipants(selectedAlbumId)
          .map(
            (list) => list
                .map(
                  (m) => MemberLite(
                    uid: m.uid,
                    name: m.name.isNotEmpty ? m.name : m.email,
                  ),
                )
                .toList(),
          );
      final initial = await stream.first;

      await showVoiceNowPopup(
        context,
        albumName: selectedAlbum.name,
        initialParticipants: initial,
        participantsStream: stream,
        onLeave: () async {
          await _svc.leaveVoice(albumId: selectedAlbumId);
          voiceOverlay.hide();
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('보이스톡 진입 실패: $e')));
    }
  }

  // 아바타
  Widget _buildUserAvatar() {
    final user = FirebaseAuth.instance.currentUser;
    final photo = user?.photoURL;
    return CircleAvatar(
      radius: 24,
      backgroundImage: (photo != null && photo.isNotEmpty)
          ? NetworkImage(photo)
          : null,
      backgroundColor: const Color(0xFFD9E2FF),
      child: (photo == null || photo.isEmpty)
          ? const Icon(Icons.person, color: Color(0xFF625F8C))
          : null,
    );
  }

  // 작은 칩
  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFD9E2FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: Color(0xFF625F8C)),
      ),
    );
  }

  // 알약 버튼
  Widget _pillButton({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFFC6DCFF), Color(0xFFD2D1FF), Color(0xFFF5CFFF)],
          ),
        ),
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

  /// 멤버 추가: 내 친구 목록을 바텀시트로 띄워 선택 → 앨범에 추가
  Future<void> _onAddMembers(
    String albumId,
    List<String> existingMemberUids,
  ) async {
    try {
      final friends = await _svc.fetchMyFriends();
      if (!mounted) return;

      final selected = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent, // 시트 테두리/배경 커스텀
        builder: (_) => _FriendPickerSheet(
          friends: friends,
          alreadyMembers: existingMemberUids,
        ),
      );

      if (selected != null && selected.isNotEmpty) {
        await _svc.addMembers(albumId, selected);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('멤버가 추가되었습니다.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('추가 실패: $e')));
    }
  }

  /// 상세정보: 앨범 멤버 목록을 다이얼로그로 표시
  Future<void> _showMemberDetails(String albumId) async {
    try {
      final members = await _svc.fetchAlbumMembers(albumId);
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: const Color(0xFFF6F9FF),
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFF625F8C), width: 3),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            constraints: const BoxConstraints(maxHeight: 480, minWidth: 280),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '멤버 목록',
                  style: TextStyle(
                    color: Color(0xFF625F8C),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: members.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final m = members[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage:
                              (m.photoUrl != null && m.photoUrl!.isNotEmpty)
                              ? NetworkImage(m.photoUrl!)
                              : null,
                          backgroundColor: const Color(0xFFD9E2FF),
                          child: (m.photoUrl == null || m.photoUrl!.isEmpty)
                              ? const Icon(
                                  Icons.person,
                                  color: Color(0xFF625F8C),
                                )
                              : null,
                        ),
                        title: Text(
                          m.name.isNotEmpty ? m.name : m.email,
                          style: const TextStyle(color: Color(0xFF625F8C)),
                        ),
                        subtitle: m.name.isNotEmpty
                            ? Text(
                                m.email,
                                style: const TextStyle(
                                  color: Color(0xFF625F8C),
                                ),
                              )
                            : null,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
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
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('불러오기 실패: $e')));
    }
  }
}

/// 친구 선택 바텀시트
class _FriendPickerSheet extends StatefulWidget {
  final List /*<FriendInfo>*/ friends; // uid, name, email 필드가 있다고 가정
  final List<String> alreadyMembers;
  const _FriendPickerSheet({
    required this.friends,
    required this.alreadyMembers,
  });

  @override
  State<_FriendPickerSheet> createState() => _FriendPickerSheetState();
}

class _FriendPickerSheetState extends State<_FriendPickerSheet> {
  final _picked = <String>{};

  @override
  Widget build(BuildContext context) {
    const borderColor = Color(0xFF625F8C);
    const bg = Color(0xFFF6F9FF);
    const textColor = Color(0xFF625F8C);

    return SafeArea(
      child: LayoutBuilder(
        builder: (ctx, cons) {
          final double sheetW = cons.maxWidth > 520 ? 520.0 : cons.maxWidth;

          return Center(
            child: Container(
              width: sheetW,
              constraints: const BoxConstraints(maxHeight: 560),
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: borderColor, width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 타이틀
                  const Text(
                    '친구 선택',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 리스트
                  Expanded(
                    child: widget.friends.isEmpty
                        ? const Center(
                            child: Text(
                              '추가할 친구가 없습니다.',
                              style: TextStyle(color: textColor),
                            ),
                          )
                        : ListView.separated(
                            itemCount: widget.friends.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final f = widget.friends[i];
                              final uid = (f.uid ?? '').toString();
                              final name =
                                  ((f.name ?? f.displayName ?? '').toString())
                                      .trim();
                              final email = (f.email ?? '').toString();

                              final already = widget.alreadyMembers.contains(
                                uid,
                              );
                              final selected = _picked.contains(uid);

                              return Opacity(
                                opacity: already ? 0.45 : 1.0,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: already
                                      ? null
                                      : () {
                                          setState(() {
                                            if (selected) {
                                              _picked.remove(uid);
                                            } else {
                                              _picked.add(uid);
                                            }
                                          });
                                        },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.65),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name.isEmpty ? '이름 없음' : name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: textColor,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                email,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: textColor,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (already)
                                          const Text(
                                            '이미 참여중',
                                            style: TextStyle(
                                              color: textColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          )
                                        else
                                          Checkbox(
                                            value: selected,
                                            onChanged: (_) {
                                              setState(() {
                                                if (selected) {
                                                  _picked.remove(uid);
                                                } else {
                                                  _picked.add(uid);
                                                }
                                              });
                                            },
                                            activeColor: borderColor,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),

                  const SizedBox(height: 12),

                  // 버튼들 (취소/추가 둘 다 그라데이션 알약)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          width: 140,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFC6DCFF),
                                Color(0xFFD2D1FF),
                                Color(0xFFF5CFFF),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Text(
                            '취소',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: () => Navigator.pop(context, _picked.toList()),
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          width: 140,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFC6DCFF),
                                Color(0xFFD2D1FF),
                                Color(0xFFF5CFFF),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Text(
                            '추가',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
