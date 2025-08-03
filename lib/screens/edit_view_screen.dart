import 'package:flutter/material.dart';

class EditViewScreen extends StatefulWidget {
  final String imagePath;

  const EditViewScreen({Key? key, required this.imagePath}) : super(key: key);

  @override
  State<EditViewScreen> createState() => _EditViewScreenState();
}

class _EditViewScreenState extends State<EditViewScreen> {
  int _selectedIndex = 0;
  int _selectedTool = 0;

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

  // ✅ 툴바용 아이콘 리스트 (Flutter 기본 아이콘 예시, 추후 이미지로 교체 가능)
  final List<IconData> _toolbarIcons = [
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
    return Scaffold(
      backgroundColor: const Color(0xFFE6EBFE),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // ✅ 상단 유저 정보 + 앨범명
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/icons/user.png',
                        width: 50,
                        height: 50,
                      ),
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
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ✅ 이미지 미리보기 (크기 줄임)
                Container(
                  height: MediaQuery.of(context).size.height * 0.4, // 원래보다 작게
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
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
                    child: Image.asset(
                      widget.imagePath,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ✅ 툴바 추가 부분
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(_toolbarIcons.length, (index) {
                      final isSelected = _selectedTool == index;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedTool = index;
                          });
                        },
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

            // ✅ 하단 네비게이션 바
            Positioned(
              bottom: 20,
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
      ),
    );
  }
}