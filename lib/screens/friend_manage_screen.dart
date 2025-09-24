import 'package:flutter/material.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../widgets/user_icon_button.dart';
import '../services/friend_manage_service.dart';
import 'add_user_popup.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FriendManageScreen extends StatefulWidget {
  const FriendManageScreen({super.key});

  @override
  State<FriendManageScreen> createState() => _FriendManageScreenState();
}

class _FriendManageScreenState extends State<FriendManageScreen> {
  final int _selectedIndex = 3;
  final _svc = FriendManageService.instance;

  bool _adding = false; // 친구 추가 로딩
  String? _busyDeleting; // 삭제 중인 친구 uid (개별 인디케이터 용도)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EBFE),
      bottomNavigationBar: const CustomBottomNavBar(), // ✅ 추가 (selectedIndex 생략 가능: 자동 추론)
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // 상단 바
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ✅ 기존 const 제거 + photoUrl 전달
                  UserIconButton(
                    photoUrl: FirebaseAuth.instance.currentUser?.photoURL,
                    radius: 24, // 크기도 동일하게 맞춤
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    '친구관리',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF625F8C),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _adding ? null : _onTapAddFriend,
                    child: Opacity(
                      opacity: _adding ? 0.6 : 1,
                      child: Image.asset(
                        'assets/icons/user_plus.png',
                        width: 36,
                        height: 36,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 친구 리스트 컨테이너
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(40, 0, 40, 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F9FF),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: StreamBuilder<List<FriendUser>>(
                  stream: _svc.watchFriends(),
                  builder: (context, snapshot) {
                    final friends = snapshot.data ?? [];

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF625F8C),
                        ),
                      );
                    }

                    if (friends.isEmpty) {
                      return const Center(
                        child: Text(
                          '등록된 친구가 없습니다',
                          style: TextStyle(
                            color: Color(0xFF625F8C),
                            fontSize: 16,
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: friends.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final f = friends[index];

                        final name = (f.name ?? '').trim();
                        final email = (f.email ?? '').trim();
                        final subtitle = name.isNotEmpty ? email : null;
                        final title = name.isNotEmpty
                            ? '$name${email.isNotEmpty ? ' ($email)' : ''}'
                            : email;

                        final deleting = _busyDeleting == f.uid;

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundImage:
                                    (f.photoUrl != null &&
                                        f.photoUrl!.isNotEmpty)
                                    ? NetworkImage(f.photoUrl!)
                                    : null,
                                backgroundColor: const Color(0xFFD9E2FF),
                                child:
                                    (f.photoUrl == null || f.photoUrl!.isEmpty)
                                    ? const Icon(
                                        Icons.person,
                                        size: 18,
                                        color: Color(0xFF625F8C),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: Color(0xFF625F8C),
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (subtitle != null && subtitle.isNotEmpty)
                                      Text(
                                        subtitle,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF625F8C),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              deleting
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF625F8C),
                                      ),
                                    )
                                  : IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Color(0xFF625F8C),
                                      ),
                                      tooltip: '친구 삭제',
                                      onPressed: () => _onDeleteFriend(f.uid),
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

  Future<void> _onTapAddFriend() async {
    try {
      setState(() => _adding = true);
      final email = await showDialog<String?>(
        context: context,
        builder: (_) => const AddUserPopup(),
      );
      if (!mounted) return;
      if (email == null || email.trim().isEmpty) {
        setState(() => _adding = false);
        return;
      }

      final res = await _svc.addFriendByEmail(email.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message),
          backgroundColor: res.success ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('추가 실패: $e')));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _onDeleteFriend(String uid) async {
    // 확인 다이얼로그
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제 확인'),
        content: const Text('이 친구를 삭제하시겠어요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      setState(() => _busyDeleting = uid);
      await _svc.removeFriend(uid);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('친구가 삭제되었어요.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
    } finally {
      if (mounted) setState(() => _busyDeleting = null);
    }
  }
}
