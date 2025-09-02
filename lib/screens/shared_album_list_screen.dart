import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/shared_album_list_service.dart';

// 팝업 유틸 (앨범 선택 / 접속자 목록)
import 'voice_call_popup.dart';

// 만약 하단 커스텀 네비바를 쓰고 싶으면 주석 해제!
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

      // 하단 네비게이션바 쓰는 경우 주석 해제
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
                  _buildUserAvatar(),
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

                  // 전화 아이콘
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
                                onTap: () => _onAddMembers(
                                  album.id,
                                  album.memberUids,
                                ),
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

      // A) 이미 접속 중인가? -> 그 앨범의 "접속자 팝업" 바로 띄우기
      final activeAlbumId = await _svc.getMyActiveVoiceAlbumId();
      if (activeAlbumId != null) {
        // 앨범 이름 구하기 (내 앨범 목록에서)
        final myAlbums = await _svc.watchMySharedAlbums().first;
        String albumName = '보이스톡';
        for (final a in myAlbums) {
          if (a.id == activeAlbumId) {
            albumName = a.name;
            break;
          }
        }

        final stream = _svc
            .watchVoiceParticipants(activeAlbumId)
            .map((list) => list
                .map((m) => MemberLite(
                      uid: m.uid,
                      name: m.name.isNotEmpty ? m.name : m.email,
                    ))
                .toList());
        final initial = await stream.first;

        await showVoiceNowPopup(
          context,
          albumName: albumName,
          initialParticipants: initial,
          participantsStream: stream,
          onLeave: () async => _svc.leaveVoice(albumId: activeAlbumId),
        );
        return;
      }

      // B) 접속 중이 아니라면: 앨범 선택 → 입장 → 접속자 팝업
      final albums = await _svc.watchMySharedAlbums().first;
      final albumLites =
          albums.map((a) => AlbumLite(id: a.id, name: a.name)).toList();

      final selectedAlbumId = await showAlbumSelectPopup(
        context,
        albums: albumLites,
      );
      if (selectedAlbumId == null) return;

      final selectedAlbum =
          albumLites.firstWhere((e) => e.id == selectedAlbumId);

      await _svc.joinVoice(albumId: selectedAlbumId);

      final stream = _svc
          .watchVoiceParticipants(selectedAlbumId)
          .map((list) => list
              .map((m) => MemberLite(
                    uid: m.uid,
                    name: m.name.isNotEmpty ? m.name : m.email,
                  ))
              .toList());
      final initial = await stream.first;

      await showVoiceNowPopup(
        context,
        albumName: selectedAlbum.name,
        initialParticipants: initial,
        participantsStream: stream,
        onLeave: () async => _svc.leaveVoice(albumId: selectedAlbumId),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('보이스톡 진입 실패: $e')),
      );
    }
  }

  // 아바타
  Widget _buildUserAvatar() {
    final user = FirebaseAuth.instance.currentUser;
    final photo = user?.photoURL;
    return CircleAvatar(
      radius: 24,
      backgroundImage:
          (photo != null && photo.isNotEmpty) ? NetworkImage(photo) : null,
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
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => _FriendPickerSheet(
          friends: friends,
          alreadyMembers: existingMemberUids,
        ),
      );

      if (selected != null && selected.isNotEmpty) {
        await _svc.addMembers(albumId, selected);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('멤버가 추가되었습니다.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('추가 실패: $e')),
      );
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
                          backgroundImage: (m.photoUrl != null &&
                                  m.photoUrl!.isNotEmpty)
                              ? NetworkImage(m.photoUrl!)
                              : null,
                          backgroundColor: const Color(0xFFD9E2FF),
                          child: (m.photoUrl == null || m.photoUrl!.isEmpty)
                              ? const Icon(Icons.person,
                                  color: Color(0xFF625F8C))
                              : null,
                        ),
                        title: Text(
                          m.name.isNotEmpty ? m.name : m.email,
                          style: const TextStyle(color: Color(0xFF625F8C)),
                        ),
                        subtitle: m.name.isNotEmpty
                            ? Text(
                                m.email,
                                style:
                                    const TextStyle(color: Color(0xFF625F8C)),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('불러오기 실패: $e')),
      );
    }
  }
}

/// 친구 선택 바텀시트
class _FriendPickerSheet extends StatefulWidget {
  final List<AlbumMember> friends;
  final List<String> alreadyMembers;

  const _FriendPickerSheet({
    required this.friends,
    required this.alreadyMembers,
  });

  @override
  State<_FriendPickerSheet> createState() => _FriendPickerSheetState();
}

class _FriendPickerSheetState extends State<_FriendPickerSheet> {
  final _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final notMembers = widget.friends
        .where((f) => !widget.alreadyMembers.contains(f.uid))
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 12,
        left: 12,
        right: 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 4,
            width: 42,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '친구 선택',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),

          Flexible(
            child: notMembers.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('추가 가능한 친구가 없습니다.'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: notMembers.length,
                    itemBuilder: (_, i) {
                      final f = notMembers[i];
                      final checked = _selected.contains(f.uid);
                      return CheckboxListTile(
                        value: checked,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selected.add(f.uid);
                            } else {
                              _selected.remove(f.uid);
                            }
                          });
                        },
                        title: Text(f.name.isNotEmpty ? f.name : f.email),
                        subtitle: f.name.isNotEmpty ? Text(f.email) : null,
                        secondary: CircleAvatar(
                          backgroundImage: (f.photoUrl != null &&
                                  f.photoUrl!.isNotEmpty)
                              ? NetworkImage(f.photoUrl!)
                              : null,
                          child: (f.photoUrl == null || f.photoUrl!.isEmpty)
                              ? const Icon(Icons.person)
                              : null,
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _pill('취소', () => Navigator.pop(context, null)),
              _pill(
                '추가',
                _selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, _selected.toList()),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _pill(String label, VoidCallback? onTap) {
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.6 : 1,
      child: IgnorePointer(
        ignoring: disabled,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
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
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
