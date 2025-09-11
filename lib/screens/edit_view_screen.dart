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
// 파일 최상단 import들에 추가
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/services.dart' show rootBundle, NetworkAssetBundle;
import 'face_landmarker.dart';
import '../beauty/beauty_panel.dart';
import 'package:sharedalbumapp/beauty/beauty_controller.dart';

class EditViewScreen extends StatefulWidget {
  // albumId(파베) 또는 imagePath(로컬/URL) 중 하나만 있으면 동작
  final String albumName;
  final String? albumId; // 저장/편집상태 해제에 사용
  final String? imagePath; // 단일 이미지 표시

  // 덮어쓰기/출처 추적 (옵션)
  final String? editedId; // 편집본 재편집 → 덮어쓰기 대상
  final String? originalPhotoId; // 원본에서 편집 시작 → 원본 추적용

  // 저장 경로 안정화를 위한 photoId (있으면 버전 경로 키로 사용)
  final String? photoId; // 예: 원본 photoId

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
    Icons.face_retouching_natural, // 👈 새 아이콘 (Material Icons 제공)
    Icons.visibility,
    Icons.text_fields,
    Icons.architecture,
    Icons.widgets,
  ];

  // 상태/가드
  bool _isSaving = false; // 저장 연타 방지
  bool _isImageReady = false; // 이미지 로딩 완료 여부
  bool _isFaceEditMode = false; // 얼굴보정 모드 여부

  // ⬇️ 여기 한 줄 추가
  bool _taskLoadedOk = false;

  Uint8List? _originalBytes; // 이미지 원본 바이트
  bool _modelLoaded = false; // 모델 로드 여부
  List<List<Offset>> _faces468 = []; // 결과 포인트(정규화)

  int? _selectedFace; // 선택된 얼굴 인덱스
  List<Rect> _faceRects = []; // 얼굴별 바운딩 박스(정규화 0~1)

  // state 필드들 아래
  bool _showLm = false; // 선택 얼굴에만 점 표시 토글
  bool _dimOthers = true; // 선택 외 영역 암처리

  Uint8List? _editedBytes; // 보정/저장용 결과

  // 저장 핵심 로직

  // RepaintBoundary → PNG 바이트 추출
  Future<Uint8List> _exportEditedImageBytes() async {
    final boundary =
        _captureKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
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
  Future<({String url, String storagePath})> _uploadEditedPngBytes(
    Uint8List png,
  ) async {
    if (widget.albumId == null) {
      throw StateError('albumId가 없습니다.');
    }
    // 경로 키: photoId > originalPhotoId > editedId > 내 uid
    final photoKey =
        widget.photoId ?? widget.originalPhotoId ?? widget.editedId ?? _uid;
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('편집이 저장되었습니다.')));
      Navigator.pop(context, 'saved');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
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
                colors: [
                  Color(0xFFC6DCFF),
                  Color(0xFFD2D1FF),
                  Color(0xFFF5CFFF),
                ],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(1, 1),
                ),
              ],
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
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

                // 저장 버튼: 상단 바 아래, 오른쪽 정렬
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      const Spacer(),
                      _gradientPillButton(label: '저장', onTap: _onSave),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 캡처 대상: 편집 스테이지 전체
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
                    child: RepaintBoundary(
                      key: _captureKey,
                      child: _buildEditableStage(),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // 툴바 (디자인 유지)
                // ↓ 기존 툴바 Container 전체를 이걸로 교체
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 4),
                    ],
                  ),
                  child: _isFaceEditMode
                      ? _buildFaceEditToolbar() // 얼굴보정 전용 툴바
                      : _buildMainToolbar(), // 기본 툴바
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
    return LayoutBuilder(
      builder: (_, c) {
        final paintSize = Size(c.maxWidth, c.maxHeight);

        return GestureDetector(
          onTapDown: (details) {
            final local = details.localPosition;
            final idx = _hitTestFace(local, paintSize);
            setState(() => _selectedFace = idx);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.imagePath != null)
                _buildSinglePreview(widget.imagePath!),

              if (_isFaceEditMode && _faces468.isNotEmpty)
                IgnorePointer(
                  ignoring: true,
                  // _buildEditableStage() 안의 CustomPaint 부분만 교체
                  child: CustomPaint(
                    painter: _LmOverlayPainter(
                      faces: _faces468,
                      faceRects: _faceRects,
                      selectedFace: _selectedFace,
                      paintSize: paintSize,
                      showLm: _showLm,
                      dimOthers: _dimOthers,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // 터치 위치가 어떤 얼굴 박스에 들어가는지 검사
  int? _hitTestFace(Offset pos, Size size) {
    for (int i = 0; i < _faceRects.length; i++) {
      final r = _faceRects[i];
      final rectPx = Rect.fromLTRB(
        r.left * size.width,
        r.top * size.height,
        r.right * size.width,
        r.bottom * size.height,
      ).inflate(12); // 약간 여유
      if (rectPx.contains(pos)) return i;
    }
    return null;
  }

  // 단일 이미지 프리뷰
  // 단일 이미지 프리뷰 (보정본이 있으면 최우선으로 사용)
  // 단일 이미지 프리뷰
  Widget _buildSinglePreview(String path) {
    if (_editedBytes != null) {
      return Image.memory(
        _editedBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

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
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF625F8C)),
          );
        },
        errorBuilder: (_, __, ___) {
          if (mounted && _isImageReady) {
            setState(() => _isImageReady = false);
          }
          return const Center(
            child: Text(
              '이미지를 불러오지 못했습니다',
              style: TextStyle(color: Color(0xFF625F8C)),
            ),
          );
        },
      );
    } else {
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

  Future<void> _smokeTestLoadTask() async {
    try {
      final data = await rootBundle.load(
        'assets/mediapipe/face_landmarker.task',
      );
      debugPrint('✅ face_landmarker.task loaded: ${data.lengthInBytes} bytes');
      if (mounted) {
        setState(() => _taskLoadedOk = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('모델 로드 OK (${data.lengthInBytes} bytes)')),
        );
      }
    } catch (e) {
      debugPrint('❌ face_landmarker.task load failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('모델 로드 실패: $e')));
      }
    }
  }

  // 기본(메인) 툴바
  Widget _buildMainToolbar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(_toolbarIcons.length, (index) {
        final isSelected = _selectedTool == index;
        return GestureDetector(
          onTap: () {
            // 얼굴보정 아이콘(예: index == 2)을 누르면 모드 전환
            if (index == 2) {
              setState(() => _isFaceEditMode = true);
              // 이미 결과 있으면 재인식 생략
              if (_faces468.isEmpty) {
                _smokeTestLoadTask();
                _runFaceDetect();
              }
            } else {
              setState(() => _selectedTool = index);
            }
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
    );
  }

  // 얼굴보정 전용 툴바 (아이콘들은 임시 플레이스홀더)
  // 교체: _buildFaceEditToolbar()
  Widget _buildFaceEditToolbar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _faceTool(
          icon: Icons.close,
          onTap: () {
            setState(() {
              _isFaceEditMode = false;
              _faces468.clear();
              _faceRects.clear();
              _selectedFace = null;
            });
          },
        ),

        // 가장 큰 얼굴 자동 선택(편의)
        _faceTool(
          icon: Icons.center_focus_strong,
          onTap: () {
            if (_faceRects.isEmpty) return;
            int largest = 0;
            double best = -1;
            for (int i = 0; i < _faceRects.length; i++) {
              final r = _faceRects[i];
              final area = (r.width * r.height);
              if (area > best) {
                best = area;
                largest = i;
              }
            }
            setState(() => _selectedFace = largest);
          },
        ),

        // 랜드마크 점 보이기/숨기기
        _faceTool(
          icon: _showLm ? Icons.visibility : Icons.visibility_off,
          onTap: () => setState(() => _showLm = !_showLm),
        ),

        // 선택된 얼굴 외 암처리 On/Off
        _faceTool(
          icon: _dimOthers ? Icons.brightness_5 : Icons.brightness_5_outlined,
          onTap: () => setState(() => _dimOthers = !_dimOthers),
        ),

        // (자리만 잡아둠) 실제 보정 패널 오픈
        _faceTool(icon: Icons.brush, onTap: _openBeautyPanel),
      ],
    );
  }

  // 작은 공통 위젯
  Widget _faceTool({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4),
        child: Icon(icon, size: 22, color: Colors.black87),
      ),
    );
  }

  // 추후 슬라이더(피부/눈/코/입술) 넣을 자리
  Future<void> _openBeautyPanel() async {
    if (_selectedFace == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('얼굴을 먼저 선택하세요.')));
      return;
    }

    // 현재 스테이지를 PNG로 캡처해서 패널로 전달
    final png = await _exportEditedImageBytes();

    final Size stageSize = _captureKey.currentContext!.size!;
    final out = await showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => BeautyPanel(
        srcPng: png,
        faces468: _faces468,
        selectedFace: _selectedFace!,
        imageSize: stageSize,
      ),
    );

    if (out != null && mounted) {
      setState(() => _editedBytes = out); // 결과 반영 → 프리뷰가 자동으로 보정본을 그림
    }
  }

  Future<void> _loadOriginalBytes() async {
    if (widget.imagePath == null) return;
    final path = widget.imagePath!;
    if (path.startsWith('http')) {
      final bundle = NetworkAssetBundle(Uri.parse(path));
      final data = await bundle.load(path);
      _originalBytes = data.buffer.asUint8List();
    } else {
      final data = await rootBundle.load(path);
      _originalBytes = data.buffer.asUint8List();
    }
  }

  Future<void> _runFaceDetect() async {
    // 1) 모델 로드(1회)
    if (!_modelLoaded) {
      final task = await rootBundle.load(
        'assets/mediapipe/face_landmarker.task',
      );
      await FaceLandmarker.loadModel(task.buffer.asUint8List(), maxFaces: 5);
      _modelLoaded = true;
    }
    // 2) 이미지 바이트 준비
    if (_originalBytes == null) {
      await _loadOriginalBytes();
    }
    if (_originalBytes == null) return;

    final faces = await FaceLandmarker.detect(_originalBytes!);

    setState(() {
      _faces468 = faces;

      // 각 얼굴의 정규화 바운딩 박스 계산
      _faceRects = faces.map((pts) {
        double minX = 1, minY = 1, maxX = 0, maxY = 0;
        for (final p in pts) {
          if (p.dx < minX) minX = p.dx;
          if (p.dy < minY) minY = p.dy;
          if (p.dx > maxX) maxX = p.dx;
          if (p.dy > maxY) maxY = p.dy;
        }
        return Rect.fromLTRB(minX, minY, maxX, maxY); // 0~1
      }).toList();
    });
  }
}

class _LmOverlayPainter extends CustomPainter {
  final List<List<Offset>> faces; // 0~1
  final List<Rect> faceRects; // 0~1
  final int? selectedFace;
  final Size paintSize;
  final bool showLm;
  final bool dimOthers;

  _LmOverlayPainter({
    required this.faces,
    required this.faceRects,
    required this.selectedFace,
    required this.paintSize,
    required this.showLm,
    required this.dimOthers,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 선택된 얼굴 외 영역 암처리
    if (dimOthers && selectedFace != null && selectedFace! < faceRects.length) {
      final sel = _toPx(faceRects[selectedFace!], paintSize);
      final full = Path()..addRect(Offset.zero & paintSize);
      final hole = Path()
        ..addRRect(
          RRect.fromRectAndRadius(sel.inflate(8), const Radius.circular(12)),
        );
      final diff = Path.combine(PathOperation.difference, full, hole);
      canvas.drawPath(diff, Paint()..color = const Color(0x88000000));
    }

    // 랜드마크 점 (옵션)
    if (showLm) {
      final dot = Paint()
        ..color = const Color(0xFF00D1FF)
        ..style = PaintingStyle.fill;
      final selDot = Paint()
        ..color = const Color(0xFF00B3CC)
        ..style = PaintingStyle.fill;
      for (int i = 0; i < faces.length; i++) {
        final pts = faces[i];
        final isSel = (i == selectedFace);
        for (final p in pts) {
          final dx = p.dx * paintSize.width;
          final dy = p.dy * paintSize.height;
          canvas.drawCircle(
            Offset(dx, dy),
            isSel ? 2.2 : 1.4,
            isSel ? selDot : dot,
          );
        }
      }
    }

    // 볼 라인(자연스러운 곡선)
    for (int i = 0; i < faceRects.length; i++) {
      final rectPx = _toPx(faceRects[i], paintSize);
      final isSel = (i == selectedFace);

      final stroke = Paint()
        ..color = isSel ? const Color(0xFF00CFEA) : Colors.white70
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSel ? 4.0 : 2.5
        ..strokeCap = StrokeCap.round;

      // 좌/우 볼 라인용 곡선 (bbox를 이용해 부드러운 S-curve 느낌)
      final w = rectPx.width;
      final h = rectPx.height;

      // Left cheek
      final lStart = Offset(rectPx.left + w * 0.12, rectPx.top + h * 0.22);
      final lCtrl = Offset(rectPx.left - w * 0.05, rectPx.top + h * 0.62);
      final lEnd = Offset(rectPx.left + w * 0.18, rectPx.bottom - h * 0.10);
      final pathL = Path()
        ..moveTo(lStart.dx, lStart.dy)
        ..quadraticBezierTo(lCtrl.dx, lCtrl.dy, lEnd.dx, lEnd.dy);
      canvas.drawPath(pathL, stroke);

      // Right cheek
      final rStart = Offset(rectPx.right - w * 0.12, rectPx.top + h * 0.22);
      final rCtrl = Offset(rectPx.right + w * 0.05, rectPx.top + h * 0.62);
      final rEnd = Offset(rectPx.right - w * 0.18, rectPx.bottom - h * 0.10);
      final pathR = Path()
        ..moveTo(rStart.dx, rStart.dy)
        ..quadraticBezierTo(rCtrl.dx, rCtrl.dy, rEnd.dx, rEnd.dy);
      canvas.drawPath(pathR, stroke);
    }
  }

  Rect _toPx(Rect r, Size s) => Rect.fromLTRB(
    r.left * s.width,
    r.top * s.height,
    r.right * s.width,
    r.bottom * s.height,
  );

  @override
  bool shouldRepaint(covariant _LmOverlayPainter old) =>
      old.faces != faces ||
      old.faceRects != faceRects ||
      old.selectedFace != selectedFace ||
      old.paintSize != paintSize ||
      old.showLm != showLm ||
      old.dimOthers != dimOthers;
}
