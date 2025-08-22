import 'package:flutter/material.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../widgets/user_icon_button.dart';
import '../services/friend_manage_service.dart';
import 'add_user_popup.dart';

class FriendManageScreen extends StatefulWidget {
  const FriendManageScreen({super.key});

  @override
  State<FriendManageScreen> createState() => _FriendManageScreenState();
}

class _FriendManageScreenState extends State<FriendManageScreen> {
  final int _selectedIndex = 3;
  final _svc = FriendManageService.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EBFE),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Column(
              children: [
                // 상단 바
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const UserIconButton(),
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
                        onTap: () async {
                          final email = await showDialog<String?>(
                            context: context,
                            builder: (_) => const AddUserPopup(),
                          );
                          if (email != null && email.trim().isNotEmpty) {
                            final res = await _svc.addFriendByEmail(email);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(res.message),
                                backgroundColor: res.success
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            );
                          }
                        },
                        child: Image.asset(
                          'assets/icons/user_plus.png',
                          width: 36,
                          height: 36,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 친구 리스트 박스
                SizedBox(
                  height: MediaQuery.of(context).size.height - 320,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F9FF),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: StreamBuilder<List<FriendUser>>(
                      stream: _svc.watchFriends(),
                      builder: (context, snapshot) {
                        final friends = snapshot.data ?? [];
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
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
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final f = friends[index];
                            return Row(
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
                                      (f.photoUrl == null ||
                                          f.photoUrl!.isEmpty)
                                      ? const Icon(
                                          Icons.person,
                                          size: 18,
                                          color: Color(0xFF625F8C),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    f.name?.isNotEmpty == true
                                        ? '${f.name} (${f.email ?? ''})'
                                        : (f.email ?? ''),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Color(0xFF625F8C),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Color(0xFF625F8C),
                                  ),
                                  onPressed: () async {
                                    await _svc.removeFriend(f.uid);
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('친구가 삭제되었어요.'),
                                      ),
                                    );
                                  },
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
          ),

          // 하단바
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: CustomBottomNavBar(selectedIndex: _selectedIndex),
          ),
        ],
      ),
    );
  }
}
