import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../widgets/user_icon_button.dart';
import '../services/shared_album_service.dart';

class EditViewScreen extends StatefulWidget {
  // albumId(파베) 또는 imagePath(로컬/URL) 중 하나만 있으면 동작
  final String albumName;
  final String? albumId;     // 저장/편집상태 해제에만 사용
  final String? imagePath;   // 단일 이미지 표시

  const EditViewScreen({
    super.key,
    required this.albumName,
    this.albumId,
    this.imagePath,
  }) : assert(
          albumId != null || imagePath != null,
          'albumId 또는 imagePath 중 하나는 반드시 필요합니다.',
        );

  @override
  State<EditViewScreen> createState() => _EditViewScreenState();
}

class _EditViewScreenState extends State<EditViewScreen> {
  final int _selectedIndex = 2;
  int _selectedTool = 0;

  final _svc = SharedAlbumService.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  // ✅ 프리뷰는 항상 단일 이미지로만 렌더링 (스트림 안 씀)
  bool get _useStream => false;

  final List<IconData> _toolbarIcons = const [
    Icons.mouse,
    Icons.grid_on,
    Icons.crop_square,
    Icons.visibility,
    Icons.text_fields,
    Icons.architecture,
    Icons.widgets,
  ];

  // === 저장 처리 ===
  Future<void> _onSave() async {
    // albumId & imagePath 둘 다 있어야 edited/*에 기록 가능
    if (widget.albumId == null || widget.imagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장할 수 없습니다 (필수 정보 부족).')),
      );
      return;
    }
    try {
      // 1) 편집본 저장 (편집된 사진)
      await _svc.saveEditedPhoto(
        albumId: widget.albumId!,
        url: widget.imagePath!,   // 실제 앱에선 편집 결과물의 URL을 넣어야 함
        editorUid: _uid,
      );

      // 2) 편집중 해제
      await _svc.clearEditing(
        uid: _uid,
        albumId: widget.albumId!,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('편집이 저장되었습니다.')),
      );
      Navigator.pop(context); // 이전 화면(편집 목록)으로 복귀
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EBFE),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // 상단 바
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 뒤로가기: 저장 전엔 편집중 유지 (clearEditing 호출 안 함)
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(
                          Icons.arrow_back_ios,
                          color: Color(0xFF625F8C),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 8),
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
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 미리보기 (화면의 55% 높이) - 단일 이미지만
                Container(
                  height: MediaQuery.of(context).size.height * 0.55,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6,
                        offset: Offset(2, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: _buildSinglePreview(widget.imagePath!),
                  ),
                ),

                const SizedBox(height: 20),

                // 툴바 (디자인 유지)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(_toolbarIcons.length, (index) {
                      final isSelected = _selectedTool == index;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedTool = index),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF397CFF) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            _toolbarIcons[index],
                            color: isSelected ? Colors.white : Colors.black87,
                            size: 22,
                          ),
                        ),
                      );
                    }),
                  ),
                ),

                const Spacer(),
                const SizedBox(height: 20),
              ],
            ),

            // 하단 네비게이션 바 + 저장 버튼
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 저장 버튼 (바텀바 위에)
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: _onSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF397CFF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      child: const Text('저장'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  CustomBottomNavBar(selectedIndex: _selectedIndex),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // === 단일 이미지 프리뷰 ===
  Widget _buildSinglePreview(String path) {
    final isUrl = path.startsWith('http');
    if (isUrl) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (c, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF625F8C)),
          );
        },
        errorBuilder: (_, __, ___) => const Center(
          child: Text(
            '이미지를 불러오지 못했습니다',
            style: TextStyle(color: Color(0xFF625F8C)),
          ),
        ),
      );
    } else {
      return Image.asset(
        path,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }
  }
}