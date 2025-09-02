import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../widgets/user_icon_button.dart';
import '../services/shared_album_service.dart';

class EditViewScreen extends StatefulWidget {
  // ✅ albumId(파베) 또는 imagePath(로컬/URL) 중 하나만 있으면 동작
  final String albumName;
  final String? albumId;     // 스트림 모드(공유앨범)
  final String? imagePath;   // 단일 이미지 모드

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

  int _pageIndex = 0;
  PageController? _pageController;

  bool get _useStream => widget.albumId != null;

  @override
  void initState() {
    super.initState();
    if (_useStream) {
      _pageController = PageController();
    }
  }

  @override
  void dispose() {
    // 스트림 모드였다면 편집 상태 해제
    if (_useStream) {
      _svc.clearEditing(uid: _uid, albumId: widget.albumId!).catchError((_) {});
    }
    _pageController?.dispose();
    super.dispose();
  }

  Future<void> _setEditingForIndex(
    int index,
    List<Photo> photos,
  ) async {
    if (!_useStream) return;
    if (index < 0 || index >= photos.length) return;
    final p = photos[index];
    await _svc.setEditing(
      uid: _uid,
      albumId: widget.albumId!,
      photoId: p.id,
      photoUrl: p.url,
    );
  }

  final List<IconData> _toolbarIcons = const [
    Icons.mouse,
    Icons.grid_on,
    Icons.crop_square,
    Icons.visibility,
    Icons.text_fields,
    Icons.architecture,
    Icons.widgets,
  ];

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // 하드웨어/제스처 뒤로가기 시에도 편집 상태 해제
      onWillPop: () async {
        if (_useStream) {
          try {
            await _svc.clearEditing(uid: _uid, albumId: widget.albumId!);
          } catch (_) {}
        }
        return true;
      },
      child: Scaffold(
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
                        GestureDetector(
                          onTap: () async {
                            if (_useStream) {
                              try {
                                await _svc.clearEditing(
                                  uid: _uid,
                                  albumId: widget.albumId!,
                                );
                              } catch (_) {}
                            }
                            if (mounted) Navigator.pop(context);
                          },
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

                  // 미리보기 (화면의 55% 높이)
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
                      child: _useStream
                          ? _buildStreamPreview()
                          : _buildSinglePreview(widget.imagePath!),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 툴바
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 4)
                      ],
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
                              color: isSelected
                                  ? const Color(0xFF397CFF)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _toolbarIcons[index],
                              color:
                                  isSelected ? Colors.white : Colors.black87,
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

              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: CustomBottomNavBar(selectedIndex: 2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // === 미리보기 빌더들 ===

  // 앨범 스트림 모드
  Widget _buildStreamPreview() {
    return StreamBuilder<List<Photo>>(
      stream: _svc.watchPhotos(uid: _uid, albumId: widget.albumId!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF625F8C)),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '사진을 불러오는 중 오류가 발생했습니다.\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF625F8C)),
              ),
            ),
          );
        }
        final photos = snapshot.data ?? [];
        if (photos.isEmpty) {
          return const Center(
            child: Text(
              '이 앨범에는 아직 사진이 없습니다',
              style: TextStyle(color: Color(0xFF625F8C), fontSize: 16),
            ),
          );
        }

        // 첫 렌더링 시 현재 페이지 사진으로 편집 상태 기록
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _setEditingForIndex(_pageIndex, photos);
        });

        return Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: photos.length,
              onPageChanged: (i) async {
                setState(() => _pageIndex = i);
                await _setEditingForIndex(i, photos);
              },
              itemBuilder: (_, i) {
                final p = photos[i];
                return Image.network(
                  p.url,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  loadingBuilder: (c, child, progress) {
                    if (progress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF625F8C),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => const Center(
                    child: Text(
                      '이미지를 불러오지 못했습니다',
                      style: TextStyle(color: Color(0xFF625F8C)),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_pageIndex + 1} / ${photos.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // 단일 이미지 모드(역호환)
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