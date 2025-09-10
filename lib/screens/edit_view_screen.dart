// lib/screens/edit_view_screen.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import '../widgets/user_icon_button.dart';
import '../services/shared_album_service.dart';

class EditViewScreen extends StatefulWidget {
  // albumId(파베) 또는 imagePath(로컬/URL) 중 하나만 있으면 동작
  final String albumName;
  final String? albumId;        // 저장/편집상태 해제에 사용
  final String? imagePath;      // 단일 이미지 표시

  // 덮어쓰기/출처 추적 (옵션)
  final String? editedId;        // 편집본 재편집 → 덮어쓰기 대상
  final String? originalPhotoId; // 원본에서 편집 시작 → 원본 추적용

  // 저장 경로 안정화를 위한 photoId (있으면 버전 경로 키로 사용)
  final String? photoId;         // 예: 원본 photoId

  const EditViewScreen({
    super.key,
    required this.albumName,
    this.albumId,
    this.imagePath,
    this.editedId,
    this.originalPhotoId,
    this.photoId,
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

  final GlobalKey _captureKey = GlobalKey();

  final List<IconData> _toolbarIcons = const [
    Icons.mouse,
    Icons.grid_on,
    Icons.crop_square,
    Icons.visibility,
    Icons.text_fields,
    Icons.architecture,
    Icons.widgets,
  ];

  // 상태/가드
  bool _isSaving = false;      // 저장 연타 방지
  bool _isImageReady = false;  // 이미지 로딩 완료 여부

  // 저장 핵심 로직

  // RepaintBoundary → PNG 바이트 추출
  Future<Uint8List> _exportEditedImageBytes() async {
    final boundary = _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('캡처 대상을 찾지 못했습니다.');
    }
    final ui.Image image = await boundary.toImage(pixelRatio: 2.5);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('PNG 인코딩에 실패했습니다.');
    }
    return byteData.buffer.asUint8List();
  }

  // PNG 바이트를 Storage edited/* 경로에 업로드
  Future<({String url, String storagePath})> _uploadEditedPngBytes(Uint8List png) async {
    if (widget.albumId == null) {
      throw StateError('albumId가 없습니다.');
    }
    // 경로 키: photoId > originalPhotoId > editedId > 내 uid
    final photoKey = widget.photoId ?? widget.originalPhotoId ?? widget.editedId ?? _uid;
    final storagePath = _svc.generateEditedStoragePath(
      albumId: widget.albumId!,
      photoId: photoKey,
      ext: 'png',
    );
    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.putData(png, SettableMetadata(contentType: 'image/png'));
    final url = await ref.getDownloadURL();
    return (url: url, storagePath: storagePath);
  }

  // 저장 처리: 항상 캡처→업로드→문서 갱신
  Future<void> _onSave() async {
    if (widget.albumId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장할 수 없습니다 (albumId가 없습니다).')),
        );
      }
      return;
    }

    // 이미지 준비 전/중복 저장 가드
    if (_isSaving) return;
    if (!_isImageReady) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미지 로딩 중입니다. 잠시 후 다시 시도하세요.')),
        );
      }
      return;
    }
    _isSaving = true;

    try {
      // 1) 현재 편집 화면 캡처
      final png = await _exportEditedImageBytes();

      // 2) edited/* 경로로 업로드
      final uploaded = await _uploadEditedPngBytes(png);

      // 3) 저장 분기
      if ((widget.editedId ?? '').isNotEmpty) {
        // 편집본 재편집 → 덮어쓰기 + 이전 파일 정리
        await _svc.saveEditedPhotoOverwrite(
          albumId: widget.albumId!,
          editedId: widget.editedId!,
          newUrl: uploaded.url,
          newStoragePath: uploaded.storagePath,
          editorUid: _uid,
          deleteOld: true,
        );
      } else if ((widget.originalPhotoId ?? '').isNotEmpty) {
        // 원본에서 신규 편집본 생성(원본 추적)
        await _svc.saveEditedPhotoFromUrl(
          albumId: widget.albumId!,
          editorUid: _uid,
          originalPhotoId: widget.originalPhotoId!,
          editedUrl: uploaded.url,
          storagePath: uploaded.storagePath,
        );
      } else {
        // 예외/호환: 원본 id 없으면 최소 저장
        await _svc.saveEditedPhoto(
          albumId: widget.albumId!,
          url: uploaded.url,
          editorUid: _uid,
          storagePath: uploaded.storagePath,
        );
      }

      // 4) 저장 성공 시에만 내 세션 정리
      try {
        await _svc.clearEditing(
          uid: _uid,
          albumId: widget.albumId!,
          editedId: widget.editedId, // 재편집이면 락 해제 포함
        );
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('편집이 저장되었습니다.')),
      );
      Navigator.pop(context, 'saved');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e')),
      );
    } finally {
      _isSaving = false;
    }
  }

  // UI

  // 그라데이션 필 버튼
  Widget _gradientPillButton({
    required String label,
    required VoidCallback onTap,
  }) {
    final disabled = (widget.albumId == null) || !_isImageReady || _isSaving;
    return Opacity(
      opacity: disabled ? 0.6 : 1.0,
      child: IgnorePointer(
        ignoring: disabled,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0xFFC6DCFF), Color(0xFFD2D1FF), Color(0xFFF5CFFF)],
              ),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(1, 1))],
            ),
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // WillPopScope 없이 단순 뒤로가기 → 세션 유지
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
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.arrow_back_ios, color: Color(0xFF625F8C), size: 24),
                      ),
                      const SizedBox(width: 8),
                      const UserIconButton(),
                      const SizedBox(width: 10),
                      const Text(
                        '편집',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF625F8C)),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFC6DCFF), Color(0xFFD2D1FF), Color(0xFFF5CFFF)],
                          ),
                        ),
                        child: Text(
                          widget.albumName,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),

                // 저장 버튼: 상단 바 아래, 오른쪽 정렬
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(children: [const Spacer(), _gradientPillButton(label: '저장', onTap: _onSave)]),
                ),

                const SizedBox(height: 12),

                // 캡처 대상: 편집 스테이지 전체
                Container(
                  height: MediaQuery.of(context).size.height * 0.55,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(2, 2))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: RepaintBoundary(
                      key: _captureKey,
                      child: _buildEditableStage(),
                    ),
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

            // 하단 네비게이션 바
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: CustomBottomNavBar(selectedIndex: _selectedIndex),
            ),
          ],
        ),
      ),
    );
  }

  // 편집 스테이지: 현재는 이미지만, 추후 텍스트/스티커/도형 위젯을 Stack으로 추가하면 저장에 그대로 반영됨
  Widget _buildEditableStage() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.imagePath != null) _buildSinglePreview(widget.imagePath!),
        // TODO: _selectedTool에 따라 텍스트/스티커/도형 등을 이 위에 올리면,
        //       저장 시 RepaintBoundary 캡처에 자동으로 합성됩니다.
      ],
    );
  }

  // 단일 이미지 프리뷰
  Widget _buildSinglePreview(String path) {
    final isUrl = path.startsWith('http');

    if (isUrl) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (c, child, progress) {
          if (progress == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_isImageReady) {
                setState(() => _isImageReady = true);
              }
            });
            return child;
          }
          return const Center(child: CircularProgressIndicator(color: Color(0xFF625F8C)));
        },
        errorBuilder: (_, __, ___) {
          if (mounted && _isImageReady) {
            setState(() => _isImageReady = false); // 에러 시 저장 비활성
          }
          return const Center(
            child: Text('이미지를 불러오지 못했습니다', style: TextStyle(color: Color(0xFF625F8C))),
          );
        },
      );
    } else {
      // 로컬/Asset은 즉시 사용 가능
      if (!_isImageReady) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isImageReady) {
            setState(() => _isImageReady = true);
          }
        });
      }
      return Image.asset(
        path,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }
  }
}