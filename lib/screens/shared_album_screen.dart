import 'package:flutter/material.dart';
import '../widgets/custom_bottom_nav_bar.dart';

class SharedAlbumScreen extends StatefulWidget {
  const SharedAlbumScreen({Key? key}) : super(key: key);

  @override
  State<SharedAlbumScreen> createState() => _SharedAlbumScreenState();
}

class _SharedAlbumScreenState extends State<SharedAlbumScreen> {
  String? _selectedAlbumTitle;

  final List<Map<String, String>> _albums = [
    {
      'title': '공경진',
      'image': 'assets/images/sample3.png',
    },
    {
      'title': '캡스톤',
      'image': 'assets/images/sample4.png',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EBFE),
      body: Stack(
        children: [
          Column(
            children: [
              // 상단 사용자 정보
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset('assets/icons/user.png', width: 50, height: 50),
                    const SizedBox(width: 10),
                    const Text(
                      '공유앨범',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF625F8C),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),

              // 가운데 박스
              SizedBox(
                height: MediaQuery.of(context).size.height - 220,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F9FF),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: _selectedAlbumTitle == null
                      ? _buildMainAlbumContents()
                      : _buildExpandedAlbumView(),
                ),
              ),
            ],
          ),

          // 하단바
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: CustomBottomNavBar(selectedIndex: 0),
          ),
        ],
      ),
    );
  }

  // 새 앨범 추가
  void _addNewAlbum() {
    setState(() {
      _albums.add({
        'title': '새 앨범 ${_albums.length + 1}',
        'image': 'assets/images/sample3.png',
      });
    });
  }

  // Shared Album 헤더 (왼쪽 정렬 + 오른쪽 +버튼)
  Widget _buildSharedAlbumHeader() {
    return Container(
      margin: const EdgeInsets.only(bottom: 30),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [Color(0xFFC6DCFF), Color(0xFFD2D1FF), Color(0xFFF5CFFF)],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Shared Album',
            style: TextStyle(
              color: Color(0xFF625F8C),
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          GestureDetector(
            onTap: _addNewAlbum,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Color(0xFF625F8C),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 앨범 리스트 화면
  Widget _buildMainAlbumContents() {
    return ListView.builder(
      itemCount: _albums.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _buildSharedAlbumHeader();

        final album = _albums[index - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildAlbumCard(album['title']!, album['image']!),
        );
      },
    );
  }

  // 앨범 확장 보기
  Widget _buildExpandedAlbumView() {
    final album = _albums.firstWhere((e) => e['title'] == _selectedAlbumTitle);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              _selectedAlbumTitle ?? '',
              style: const TextStyle(
                color: Color(0xFF625F8C),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: () {
                setState(() {
                  _selectedAlbumTitle = null;
                });
              },
              icon: const Icon(Icons.close, color: Color(0xFF625F8C)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            album['image']!,
            width: double.infinity,
            height: 400,
            fit: BoxFit.cover,
          ),
        ),
      ],
    );
  }

  // 앨범 카드
  Widget _buildAlbumCard(String title, String imagePath) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedAlbumTitle = title;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFD9E2FF),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF625F8C),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                imagePath,
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
          ],
        ),
      ),
    );
  }
}