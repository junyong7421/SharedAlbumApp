import 'package:flutter/material.dart';

class SharedAlbumScreen extends StatefulWidget {
  const SharedAlbumScreen({Key? key}) : super(key: key);

  @override
  State<SharedAlbumScreen> createState() => _SharedAlbumScreenState();
}

class _SharedAlbumScreenState extends State<SharedAlbumScreen> {
  int _selectedIndex = 0;

  final String albumName = 'Shared Album';

  String? _selectedAlbumTitle;
  String? _selectedImagePath;

  final List<String> _imagePaths = [
    'assets/images/sample3.png',
    'assets/images/sample4.png',
  ];

  final List<String> _iconPathsOn = [
    'assets/icons/image_on.png',
    'assets/icons/list_on.png',
    'assets/icons/edit_on.png',
    'assets/icons/friend_on.png',
  ];

  final List<String> _iconPathsOff = [
    'assets/icons/image_off.png',
    'assets/icons/list_off.png',
    'assets/icons/edit_off.png',
    'assets/icons/friend_off.png',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EBFE),
      body: Stack(
        children: [
          Column(
            children: [
              // ✅ 상단 사용자 정보
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

              // ✅ 가운데 흰 박스 (크기 조정됨)
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

          // ✅ 하단 커스텀 네비게이션 바
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              height: 70,
              decoration: BoxDecoration(
                color: const Color(0xFFF6F9FF),
                borderRadius: BorderRadius.circular(35),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(2, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(4, (index) {
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                    child: Image.asset(
                      _selectedIndex == index
                          ? _iconPathsOn[index]
                          : _iconPathsOff[index],
                      width: index == 2 ? 38 : 36,
                      height: index == 2 ? 38 : 36,
                      fit: BoxFit.contain,
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ 기본 상태 화면
  Widget _buildMainAlbumContents() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Shared Album 버튼
        Container(
          alignment: Alignment.center,
          margin: const EdgeInsets.only(bottom: 30),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
              colors: [Color(0xFFC6DCFF), Color(0xFFD2D1FF), Color(0xFFF5CFFF)],
            ),
          ),
          child: const Text(
            'Shared Album',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF625F8C),
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ),
        _buildAlbumCard('공경진', _imagePaths[0]),
        const SizedBox(height: 16),
        _buildAlbumCard('캡스톤', _imagePaths[1]),
      ],
    );
  }

  // ✅ 앨범 선택 시 보여지는 화면
  Widget _buildExpandedAlbumView() {
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
                  _selectedImagePath = null;
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
            _selectedImagePath!,
            width: double.infinity,
            height: 400,
            fit: BoxFit.cover,
          ),
        ),
      ],
    );
  }

  // ✅ 앨범 카드 위젯
  Widget _buildAlbumCard(String title, String imagePath) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedAlbumTitle = title;
          _selectedImagePath = imagePath;
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
