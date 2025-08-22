import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../widgets/user_icon_button.dart';
import 'edit_view_screen.dart';

class SharedAlbumScreen extends StatefulWidget {
  const SharedAlbumScreen({Key? key}) : super(key: key);

  @override
  State<SharedAlbumScreen> createState() => _SharedAlbumScreenState();
}

class _SharedAlbumScreenState extends State<SharedAlbumScreen> {
  String? _selectedAlbumTitle;
  int? _selectedImageIndex;
  final TextEditingController _albumNameController = TextEditingController();

  final List<String> _sampleImages = [
    'assets/images/sample1.jpg',
    'assets/images/sample2.jpg',
    'assets/images/sample3.png',
    'assets/images/sample4.png',
  ];

  final List<Map<String, dynamic>> _albums = [];

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _saveAlbums() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_albums);
    await prefs.setString('albums', encoded);
  }

  Future<void> _loadAlbums() async {
    final prefs = await SharedPreferences.getInstance();
    final storedData = prefs.getString('albums');
    if (storedData != null) {
      setState(() {
        _albums.clear();
        _albums.addAll(List<Map<String, dynamic>>.from(jsonDecode(storedData)));
      });
    }
  }

  void _showAddAlbumDialog() {
    _albumNameController.clear();
    List<String> selectedImages = [];

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              backgroundColor: const Color(0xFFF6F9FF),
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: Color(0xFF625F8C), width: 2),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 30,
                  horizontal: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Text(
                        "새 앨범 만들기",
                        style: TextStyle(
                          fontSize: 20,
                          color: Color(0xFF625F8C),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _albumNameController,
                      cursorColor: Color(0xFF625F8C),
                      style: const TextStyle(color: Color(0xFF625F8C)),
                      decoration: InputDecoration(
                        hintText: "앨범 이름을 입력하세요.",
                        hintStyle: const TextStyle(color: Color(0xFF625F8C)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(
                            color: Color(0xFF625F8C),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(
                            color: Color(0xFF625F8C),
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "사진 선택 (선택사항)",
                      style: TextStyle(fontSize: 14, color: Color(0xFF625F8C)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _sampleImages.map((imgPath) {
                        final isSelected = selectedImages.contains(imgPath);
                        return GestureDetector(
                          onTap: () {
                            setStateDialog(() {
                              if (isSelected) {
                                selectedImages.remove(imgPath);
                              } else {
                                selectedImages.add(imgPath);
                              }
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: isSelected
                                    ? Color(0xFF625F8C)
                                    : Colors.transparent,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Image.asset(
                              imgPath,
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 30),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildGradientActionButton("취소", () {
                          Navigator.pop(context);
                        }),
                        _buildGradientActionButton("확인", () {
                          final albumName = _albumNameController.text.trim();
                          if (albumName.isNotEmpty) {
                            setState(() {
                              _albums.add({
                                'title': albumName,
                                'images': selectedImages,
                              });
                            });
                            _saveAlbums();
                          }
                          Navigator.pop(context);
                        }),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildGradientActionButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFFC6DCFF), Color(0xFFD2D1FF), Color(0xFFF5CFFF)],
          ),
        ),
        alignment: Alignment.center,
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

  void _showAddPhotoDialog(int albumIndex) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("사진 추가"),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _sampleImages.map((imgPath) {
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _albums[albumIndex]['images'].add(imgPath);
                  });
                  _saveAlbums();
                  Navigator.pop(context);
                },
                child: Image.asset(
                  imgPath,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _deleteAlbum(int index) {
    setState(() {
      _albums.removeAt(index);
      _selectedAlbumTitle = null;
    });
    _saveAlbums();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6EBFE),
      bottomNavigationBar: const Padding(
        padding: EdgeInsets.only(bottom: 40, left: 20, right: 20),
        child: CustomBottomNavBar(selectedIndex: 0),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: const [
                  UserIconButton(),
                  SizedBox(width: 10),
                  Text(
                    '공유앨범',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF625F8C),
                    ),
                  ),
                  Spacer(),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(40, 0, 40, 60),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F9FF),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Column(
                  children: [
                    if (_selectedAlbumTitle == null) ...[
                      _buildSharedAlbumHeader(),
                      const SizedBox(height: 12),
                    ],
                    Expanded(
                      child: _selectedAlbumTitle == null
                          ? _buildMainAlbumList()
                          : _buildExpandedAlbumView(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSharedAlbumHeader() {
    return Container(
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
            onTap: _showAddAlbumDialog,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Color(0xFF625F8C),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainAlbumList() {
    if (_albums.isEmpty) {
      return const Center(
        child: Text(
          '아직 생성된 앨범이 없습니다',
          style: TextStyle(color: Color(0xFF625F8C), fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      itemCount: _albums.length,
      itemBuilder: (context, index) {
        final album = _albums[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedAlbumTitle = album['title'];
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
                  Row(
                    children: [
                      Text(
                        album['title'],
                        style: const TextStyle(
                          color: Color(0xFF625F8C),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          color: Color(0xFF625F8C),
                        ),
                        onPressed: () => _deleteAlbum(index),
                      ),
                    ],
                  ),
                  if (album['images'].isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        album['images'][0],
                        width: double.infinity,
                        height: 180,
                        fit: BoxFit.cover,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildExpandedAlbumView() {
    final album = _albums.firstWhere((e) => e['title'] == _selectedAlbumTitle);

    if (_selectedImageIndex == null) {
      return Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF625F8C)),
                onPressed: () {
                  setState(() {
                    _selectedAlbumTitle = null;
                  });
                },
              ),
              const Spacer(),
            ],
          ),
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: List.generate(album['images'].length, (i) {
                final imgPath = album['images'][i];
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedImageIndex = i;
                    });
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(imgPath, fit: BoxFit.cover),
                  ),
                );
              }),
            ),
          ),
        ],
      );
    } else {
      final PageController _pageController = PageController(
        initialPage: _selectedImageIndex!,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF625F8C)),
                onPressed: () {
                  setState(() {
                    _selectedImageIndex = null;
                  });
                },
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: album['images'].length,
              onPageChanged: (index) {
                setState(() {
                  _selectedImageIndex = index;
                });
              },
              itemBuilder: (context, i) {
                final imgPath = album['images'][i];
                return Column(
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10, right: 4),
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => EditViewScreen(
                                  imagePath: imgPath,
                                  albumName: _selectedAlbumTitle!,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
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
                              "편집하기",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          imgPath,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      );
    }
  }
}
