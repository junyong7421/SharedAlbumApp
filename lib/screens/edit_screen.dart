import 'package:flutter/material.dart';

class EditScreen extends StatefulWidget {
  const EditScreen({Key? key}) : super(key: key);

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  int _selectedIndex = 2; // 기본 선택 탭 (편집)

  final List<String> _iconPaths = [
    'assets/icons/image_off.png',
    'assets/icons/list_off.png',
    'assets/icons/edit_on.png',
    'assets/icons/friend_off.png',
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
      backgroundColor: const Color(0xFFF0EEFC),
      body: SafeArea(
        child: Stack(
          children: [
            // ✅ 전체 콘텐츠
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ✅ 상단 사용자 이름
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    '홍길동의 앨범',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF333333),
                    ),
                  ),
                ),

                // ✅ 스크롤 가능한 이미지 카드
                SizedBox(
                  height: 140,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    children: List.generate(5, (index) {
                      return Container(
                        margin: const EdgeInsets.only(right: 12),
                        width: 120,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 5,
                              offset: Offset(2, 2),
                            ),
                          ],
                        ),
                        child: Center(child: Text('사진 ${index + 1}')),
                      );
                    }),
                  ),
                ),

                const SizedBox(height: 20),

                // ✅ 편집된 사진 표시
                Expanded(
                  child: Center(
                    child: Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 5,
                            offset: Offset(2, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text('편집된 사진', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 70), // 하단바 공간 확보
              ],
            ),

            // ✅ 커스텀 하단바
            Positioned(
              bottom: 20, // 조금 띄우면 더 자연스러움
              left: 20,
              right: 20,
              child: Container(
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(35), // ✅ 둥글게
                  boxShadow: [
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
      ),
    );
  }
}
