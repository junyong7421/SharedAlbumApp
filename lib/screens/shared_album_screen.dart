import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../widgets/user_icon_button.dart';

class SharedAlbumScreen extends StatefulWidget {
  const SharedAlbumScreen({Key? key}) : super(key: key);

  @override
  State<SharedAlbumScreen> createState() => _SharedAlbumScreenState();
}

class _SharedAlbumScreenState extends State<SharedAlbumScreen> {
  String? _selectedAlbumTitle;
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
    String? selectedImage;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("새 앨범 만들기"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _albumNameController,
                      decoration: const InputDecoration(hintText: "앨범 이름을 입력하세요"),
                    ),
                    const SizedBox(height: 12),
                    const Text("사진 선택 (선택사항)", style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _sampleImages.map((imgPath) {
                        return GestureDetector(
                          onTap: () {
                            setStateDialog(() {
                              selectedImage = imgPath;
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: selectedImage == imgPath ? Colors.blue : Colors.transparent,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Image.asset(imgPath, width: 60, height: 60, fit: BoxFit.cover),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
                TextButton(
                  onPressed: () {
                    final albumName = _albumNameController.text.trim();
                    if (albumName.isNotEmpty) {
                      setState(() {
                        _albums.add({
                          'title': albumName,
                          'images': selectedImage != null ? [selectedImage!] : [],
                        });
                      });
                      _saveAlbums();
                    }
                    Navigator.pop(context);
                  },
                  child: const Text("확인"),
                ),
              ],
            );
          },
        );
      },
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
                child: Image.asset(imgPath, width: 60, height: 60, fit: BoxFit.cover),
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
                        icon: const Icon(Icons.delete, color: Color(0xFF625F8C)),
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
    final index = _albums.indexOf(album);

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
              onPressed: () => _showAddPhotoDialog(index),
              icon: const Icon(Icons.add, color: Color(0xFF625F8C)),
            ),
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
        Expanded(
          child: ListView(
            children: album['images']
                .map<Widget>((imgPath) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          imgPath,
                          width: double.infinity,
                          height: 180,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}