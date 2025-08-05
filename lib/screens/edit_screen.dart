import 'package:flutter/material.dart';
import 'edit_view_screen.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../widgets/user_icon_button.dart';

class EditScreen extends StatefulWidget {
  const EditScreen({Key? key}) : super(key: key);

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  int _selectedIndex = 2;
  int _currentIndex = 0;

  final List<String> _imagePaths = [
    'assets/images/sample1.jpg',
    'assets/images/sample2.jpg',
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

  final String albumName = "공경진";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EBFE),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상단 사용자 정보
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
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
                          albumName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFFFFFFF),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
                // ✅ 편집 중인 사진 텍스트 박스
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(left: 24, bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
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
                    child: const Text(
                      '편집 중인 사진',
                      style: TextStyle(
                        color: Color(0xFFF6F9FF),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // 고양이 사진 + 화살표 분리
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_left, size: 32),
                        onPressed: () {
                          setState(() {
                            _currentIndex =
                                (_currentIndex - 1 + _imagePaths.length) %
                                _imagePaths.length;
                          });
                        },
                      ),

                      const SizedBox(width: 8),

                      // ✅ 이미지 클릭 시 편집 페이지로 이동
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => EditViewScreen(
                                imagePath: _imagePaths[_currentIndex],
                              ),
                            ),
                          );
                        },
                        child: Container(
                          width: 140,
                          height: 160,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F9FF),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 5,
                                offset: Offset(2, 2),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              _imagePaths[_currentIndex],
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      IconButton(
                        icon: const Icon(Icons.arrow_right, size: 32),
                        onPressed: () {
                          setState(() {
                            _currentIndex =
                                (_currentIndex + 1) % _imagePaths.length;
                          });
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(left: 24, bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
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
                          child: const Text(
                            '편집된 사진',
                            style: TextStyle(
                              color: Color(0xFFF6F9FF),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // ✅ 중앙 정렬된 흰 박스 + 이미지들a
                      Center(
                        child: Container(
                          width: 300,
                          height: 180,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: Offset(2, 2),
                              ),
                            ],
                          ),
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.all(12),
                            children: [
                              for (var path in _imagePaths)
                                Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.asset(
                                      path,
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 70),
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
    );
  }
}
