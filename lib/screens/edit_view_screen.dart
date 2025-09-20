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
import 'package:flutter/services.dart' show rootBundle, NetworkAssetBundle;
import 'face_landmarker.dart';
import '../beauty/beauty_panel.dart';
import 'package:sharedalbumapp/beauty/beauty_controller.dart';
import 'package:image/image.dart' as img;
import '../edit_tools/image_ops.dart';
import '../edit_tools/crop_overlay.dart';

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
  // ▼ 4개 툴 전환: 0=자르기, 1=얼굴보정, 2=밝기, 3=회전/반전
  int _selectedTool = -1; // 0=자르기,1=얼굴보정,2=밝기,3=회전/반전
  Rect? _cropRectStage;
  Size? _lastStageSize;
  double _brightness = 0.0;
  bool _brightnessApplying = false;

  // 얼굴별 보정 파라미터 저장소
  final Map<int, BeautyParams> _faceParams = {};

  // 얼굴보정 전용 Undo 스택 (적용할 때마다 push)
  final List<({Uint8List image, Map<int, BeautyParams> params})> _faceUndo = [];

  // 얼굴보정 오버레이 캡처 제외용
  bool _faceOverlayOn = true;

  final List<IconData> _toolbarIcons = const [
    Icons.crop,
    Icons.face_retouching_natural,
    Icons.brightness_6,
    Icons.rotate_90_degrees_ccw,
    Icons.color_lens, // 4 채도
    Icons.hdr_strong, // 5 선명도(샤픈)
  ];

  final int _selectedIndex = 2;

  final _svc = SharedAlbumService.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  final GlobalKey _captureKey = GlobalKey();

  // 상태/가드
  bool _isSaving = false; // 저장 연타 방지
  bool _isImageReady = false; // 이미지 로딩 완료 여부
  bool _isFaceEditMode = false; // 얼굴보정 모드 여부

  // ⬇️ 여기 한 줄 추가
  bool _taskLoadedOk = false;

  Uint8List? _editedBytes; // ← 결과 PNG (화면에 보여줄 것)
  Uint8List? _originalBytes; // 이미지 원본 바이트
  bool _modelLoaded = false; // 모델 로드 여부
  List<List<Offset>> _faces468 = []; // 결과 포인트(정규화)

  int? _selectedFace; // 선택된 얼굴 인덱스
  List<Rect> _faceRects = []; // 얼굴별 바운딩 박스(정규화 0~1)

  // state 필드들 아래
  bool _showLm = false; // 선택 얼굴에만 점 표시 토글
  bool _dimOthers = false; // 선택 외 영역 암처리

  BeautyParams _beautyParams = BeautyParams();
  Uint8List? _beautyBasePng; // 보정/저장용 결과

  // 얼굴 파라미터(deep copy)
  Map<int, BeautyParams> _cloneParams(Map<int, BeautyParams> src) {
    final out = <int, BeautyParams>{};
    src.forEach((k, v) {
      out[k] = v.copyWith(); // 새로운 BeautyParams 생성
    });
    return out;
  }

  double _saturation = 0.0;
  bool _saturationApplying = false;

  double _sharp = 0.0; // 0.0 ~ 1.0 (0이 원본)
  bool _sharpenApplying = false;

  // 조정 패널 들어올 때 스냅샷(베이스)
  Uint8List? _adjustBaseBytes;

  // 저장 핵심 로직

  // RepaintBoundary → PNG 바이트 추출
  // 기존 함수 교체
  Future<Uint8List> _exportEditedImageBytes({
    double pixelRatio = 2.5,
    bool hideOverlay = false, // ▶ 추가: 캡처 직전에 오버레이 숨길지
  }) async {
    // 오버레이 임시 숨김 (필요할 때만)
    final prevOverlay = _faceOverlayOn;
    if (hideOverlay && prevOverlay) {
      setState(() => _faceOverlayOn = false);
      // 한 프레임 쉬고 캡처 (오버레이가 화면에서 실제로 사라지도록)
      await Future.delayed(const Duration(milliseconds: 16));
    }

    final boundary =
        _captureKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('캡처 대상을 찾지 못했습니다.');
    }
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('PNG 인코딩에 실패했습니다.');
    }

    // 숨겼다면 원상복구
    if (hideOverlay && prevOverlay && mounted) {
      setState(() => _faceOverlayOn = true);
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
      final png = await _exportEditedImageBytes(hideOverlay: true);
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
              if (_selectedTool == 0)
                Positioned.fill(
                  child: CropOverlay(
                    initRect: _cropRectStage,
                    onChanged: (r) => _cropRectStage = r,
                    onStageSize: (s) => _lastStageSize = s,
                  ),
                ),

              if (_isFaceEditMode && _faces468.isNotEmpty && _faceOverlayOn)
                IgnorePointer(
                  ignoring: true,
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

    // 원본 보여주기
    final isUrl = path.startsWith('http');
    return isUrl
        ? Image.network(
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
          )
        : Image.asset(
            path,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          );
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

  Widget _buildMainToolbar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(_toolbarIcons.length, (i) {
            final sel = _selectedTool == i;
            return GestureDetector(
              onTap: () async {
                if (i == 1) {
                  setState(() => _isFaceEditMode = true);
                  if (_faces468.isEmpty) {
                    _smokeTestLoadTask();
                    _runFaceDetect();
                  }
                } else {
                  // 얼굴보정 이탈 → 스택 비우기 (얼굴 보정 undo만 관리)
                  _faceUndo.clear();

                  // 조정툴 진입 시 베이스 스냅샷
                  if (i == 2 || i == 4 || i == 5) {
                    _adjustBaseBytes = await _currentBytes();
                    if (i == 2) _brightness = 0.0;
                    if (i == 4) _saturation = 0.0;
                    if (i == 5) _sharp = 0.0;
                  }
                  setState(() {
                    _isFaceEditMode = false;
                    _selectedTool = i;
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: sel ? const Color(0xFF397CFF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _toolbarIcons[i],
                  color: sel ? Colors.white : Colors.black87,
                  size: 22,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),

        /// ⬇️ 이 부분이 빠져서 패널이 안 보였던 거예요!
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: switch (_selectedTool) {
            0 => _cropPanel(),
            2 => _brightnessPanel(),
            3 => _rotatePanel(),
            4 => _saturationPanel(),
            5 => _sharpenPanel(),
            _ => const SizedBox.shrink(),
          },
        ),
      ],
    );
  }

  Widget _cropPanel() => Row(
    key: const ValueKey('crop'),
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      _pill(
        '초기화',
        () => setState(() {
          _cropRectStage = null;
          _editedBytes = null; // ← 원본으로 복귀
        }),
      ),
      _pill('맞춤', () {
        if (_lastStageSize == null) return;
        final s = _lastStageSize!;
        setState(
          () => _cropRectStage = Rect.fromLTWH(
            s.width * 0.1,
            s.height * 0.1,
            s.width * 0.8,
            s.height * 0.8,
          ),
        );
      }),
      _pill('적용', _applyCrop),
    ],
  );

  Widget _brightnessPanel() => Column(
    key: const ValueKey('brightness'),
    children: [
      Row(
        children: [
          const SizedBox(width: 8),
          const Icon(Icons.brightness_low, size: 18),

          // ▼ 가운데에 '0' 표시막대가 있는 슬라이더
          Expanded(
            child: SizedBox(
              height: 36,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4, // (선택) 트랙 두께
                    ),
                    child: Slider(
                      value: _brightness, // -0.5 ~ 0.5
                      min: -0.5,
                      max: 0.5,
                      divisions: 20,
                      label: _brightness.toStringAsFixed(2),
                      onChanged: (v) => setState(() => _brightness = v),
                      onChangeEnd: (_) => _applyBrightness(),
                    ),
                  ),

                  // ▼ 중앙(값=0)에만 얇은 세로 라인 표시
                  IgnorePointer(
                    // 슬라이더 제스처 방해하지 않도록
                    child: Container(
                      width: 2,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade500,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Icon(Icons.brightness_high, size: 18),
          const SizedBox(width: 8),
        ],
      ),

      if (_brightnessApplying)
        const SizedBox(height: 2, child: LinearProgressIndicator()),
    ],
  );

  Widget _saturationPanel() => Column(
    key: const ValueKey('saturation'),
    children: [
      Row(
        children: [
          const SizedBox(width: 8),
          const Icon(Icons.colorize, size: 18),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 0 위치 표시 막대
                const _ZeroTick(),
                Slider(
                  value: _saturation,
                  min: -1.0,
                  max: 1.0,
                  divisions: 40,
                  label: _saturation.toStringAsFixed(2),
                  onChanged: (v) => setState(() => _saturation = v),
                  onChangeEnd: (_) => _applySaturation(),
                ),
              ],
            ),
          ),
          const Icon(Icons.palette, size: 18),
          const SizedBox(width: 8),
        ],
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _pill('초기화', () {
            setState(() => _saturation = 0.0);
            _applySaturation();
          }),
        ],
      ),
      if (_saturationApplying)
        const SizedBox(height: 2, child: LinearProgressIndicator()),
    ],
  );

  Widget _sharpenPanel() => Column(
    key: const ValueKey('sharpen'),
    children: [
      Row(
        children: [
          const SizedBox(width: 8),
          const Icon(Icons.blur_on, size: 18),
          Expanded(
            child: Slider(
              value: _sharp,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              label: _sharp.toStringAsFixed(2),
              onChanged: (v) => setState(() => _sharp = v),
              onChangeEnd: (_) => _applySharpen(),
            ),
          ),
          const Icon(Icons.hdr_strong, size: 18),
          const SizedBox(width: 8),
        ],
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _pill('초기화', () {
            setState(() => _sharp = 0.0); // ← 샤픈 값을 리셋
            _applySharpen(); // ← 샤픈 적용 함수 호출
          }),
        ],
      ),
      if (_sharpenApplying)
        const SizedBox(height: 2, child: LinearProgressIndicator()),
    ],
  );

  Future<void> _applySaturation() async {
    _faceUndo.clear();
    if (_saturationApplying) return;
    _saturationApplying = true;
    setState(() {});
    try {
      final base = _adjustBaseBytes ?? await _currentBytes();
      if (_saturation.abs() < 1e-6) {
        setState(() => _editedBytes = base);
      } else {
        final out = ImageOps.adjustSaturation(base, _saturation);
        setState(() => _editedBytes = out);
      }
    } finally {
      _saturationApplying = false;
      setState(() {});
    }
  }

  Future<void> _applySharpen() async {
    _faceUndo.clear();
    if (_sharpenApplying) return;
    _sharpenApplying = true;
    setState(() {});
    try {
      final base = _adjustBaseBytes ?? await _currentBytes();
      if (_sharp.abs() < 1e-6) {
        setState(() => _editedBytes = base);
      } else {
        final out = ImageOps.sharpen(base, _sharp);
        setState(() => _editedBytes = out);
      }
    } finally {
      _sharpenApplying = false;
      setState(() {});
    }
  }

  Widget _rotatePanel() => Row(
    key: const ValueKey('rotate'),
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      _pill('왼쪽 90°', () => _applyRotate(-90)),
      _pill('오른쪽 90°', () => _applyRotate(90)),
      _pill('좌우 반전', _applyFlipH),
      _pill('상하 반전', _applyFlipV),
    ],
  );

  Future<Uint8List> _currentBytes() async {
    if (_editedBytes != null) return _editedBytes!;
    if (_originalBytes == null) await _loadOriginalBytes();
    return _editedBytes ?? _originalBytes!;
  }

  Future<void> _applyCrop() async {
    _faceUndo.clear();
    if (_cropRectStage == null || _lastStageSize == null) return;
    final bytes = await _currentBytes();
    final out = ImageOps.cropFromStageRect(
      srcBytes: bytes,
      stageCropRect: _cropRectStage!,
      stageSize: _lastStageSize!,
    );
    setState(() {
      _editedBytes = out;
      _cropRectStage = null;
    });
  }

  Future<void> _applyBrightness() async {
    _faceUndo.clear();
    if (_brightnessApplying) return;
    _brightnessApplying = true;
    setState(() {});

    try {
      final base = _adjustBaseBytes ?? await _currentBytes(); // 공용 베이스
      if (_brightness.abs() < 1e-6) {
        setState(() => _editedBytes = base); // 0이면 베이스 그대로
      } else {
        final out = ImageOps.adjustBrightness(base, _brightness);
        setState(() => _editedBytes = out);
      }
    } finally {
      _brightnessApplying = false;
      setState(() {});
    }
  }

  Future<void> _resetToOriginal() async {
    _faceUndo.clear();
    await _loadOriginalBytes(); // _originalBytes 보장
    setState(() {
      _editedBytes = null; // 프리뷰가 원본을 그리도록
      _cropRectStage = null; // 오버레이도 초기화
      _brightness = 0.0; // 슬라이더 센터
      _beautyBasePng = null; // (얼굴보정도 필요시 다시 베이스 만들도록)
      _saturation = 0.0;
      _sharp = 0.0;
      _adjustBaseBytes = null; // 다음 조정 진입 시 새 베이스 캡처
    });
  }

  Future<void> _applyRotate(int deg) async {
    _faceUndo.clear();
    final bytes = await _currentBytes();
    setState(() => _editedBytes = ImageOps.rotate(bytes, deg));
  }

  Future<void> _applyFlipH() async {
    _faceUndo.clear();
    final bytes = await _currentBytes();
    setState(() => _editedBytes = ImageOps.flipHorizontal(bytes));
  }

  Future<void> _applyFlipV() async {
    _faceUndo.clear();
    final bytes = await _currentBytes();
    setState(() => _editedBytes = ImageOps.flipVertical(bytes));
  }

  Widget _pill(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFFF2F4FF),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    ),
  );

  // 얼굴보정 전용 툴바 (아이콘들은 임시 플레이스홀더)
  // 교체: _buildFaceEditToolbar()
  Widget _buildFaceEditToolbar() {
    final canUndo = _faceUndo.isNotEmpty;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // ⬅️ 닫기: 기본 툴바로 복귀
        _faceTool(icon: Icons.close, onTap: _exitFaceMode),

        // 가장 큰 얼굴 자동 선택
        _faceTool(
          icon: Icons.center_focus_strong,
          onTap: () {
            if (_faceRects.isEmpty) return;
            int largest = 0;
            double best = -1;
            for (int i = 0; i < _faceRects.length; i++) {
              final r = _faceRects[i];
              final area = r.width * r.height;
              if (area > best) {
                best = area;
                largest = i;
              }
            }
            setState(() => _selectedFace = largest);
          },
        ),

        // 랜드마크 토글
        _faceTool(
          icon: _showLm ? Icons.visibility : Icons.visibility_off,
          onTap: () => setState(() => _showLm = !_showLm),
        ),

        // 이전(Undo)
        _faceToolEx(
          icon: Icons.undo,
          enabled: canUndo,
          onTap: canUndo ? _undoFaceOnce : null,
        ),

        // 보정 패널 열기
        _faceTool(icon: Icons.brush, onTap: _openBeautyPanel),
      ],
    );
  }

  Future<void> _undoFaceOnce() async {
    if (_faceUndo.isEmpty) return;
    final snap = _faceUndo.removeLast();
    setState(() {
      _editedBytes = snap.image;
      // ✅ 재할당 대신, 내용만 교체
      _faceParams
        ..clear()
        ..addAll(_cloneParams(snap.params)); // 아래 2) 참고
    });
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

    // ① 오버레이 숨기고 캡처(겹그림 방지)
    setState(() => _faceOverlayOn = false);
    await Future.delayed(const Duration(milliseconds: 16));
    _beautyBasePng = await _exportEditedImageBytes(pixelRatio: 1.0);
    setState(() => _faceOverlayOn = true);

    final Size stageSize = _captureKey.currentContext!.size!;
    final init = _faceParams[_selectedFace!] ?? BeautyParams();

    // ② 패널 띄우기
    final result =
        await showModalBottomSheet<({Uint8List image, BeautyParams params})>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (_) => BeautyPanel(
            srcPng: _beautyBasePng!, // 스테이지 크기 기준 PNG
            faces468: _faces468,
            selectedFace: _selectedFace!,
            imageSize: stageSize,
            initialParams: init, // 얼굴별로 저장된 값 있으면 적용
          ),
        );

    // ③ 적용 결과 수신 → Undo 스택에 "이전 상태" 저장하고 반영
    if (result != null && mounted) {
      final prev = await _currentBytes();
      final paramsCopy = _cloneParams(_faceParams);

      setState(() {
        _faceUndo.add((
          image: Uint8List.fromList(prev),
          params: paramsCopy,
        )); // 한 번만!
        _editedBytes = result.image;
        _faceParams[_selectedFace!] = result.params;
      });
    }
  }

  void _exitFaceMode() {
    // 기본 툴바로 복귀
    setState(() {
      _isFaceEditMode = false; // ← 이 한 줄이 핵심
      _selectedTool = 1; // 메인툴바에서 '얼굴' 아이콘 선택 상태 유지(원하면 다른 인덱스로)
      _selectedFace = null; // 선택 해제(선택)
      _showLm = false; // 랜드마크 표시 끔(선택)
    });

    // 얼굴보정 전용 undo 스택은 정리(선택)
    _faceUndo.clear();
    // _beautyBasePng = null; // 필요하면 캡처 베이스도 초기화
  }

  // 사용감 좋은 변형
  Widget _faceToolEx({
    required IconData icon,
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: IgnorePointer(
        ignoring: !enabled,
        child: GestureDetector(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4),
            child: Icon(icon, size: 22, color: Colors.black87),
          ),
        ),
      ),
    );
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
    /*if (dimOthers && selectedFace != null && selectedFace! < faceRects.length) {
      final sel = _toPx(faceRects[selectedFace!], paintSize);
      final full = Path()..addRect(Offset.zero & paintSize);
      final hole = Path()
        ..addRRect(
          RRect.fromRectAndRadius(sel.inflate(8), const Radius.circular(12)),
        );
      final diff = Path.combine(PathOperation.difference, full, hole);
      canvas.drawPath(diff, Paint()..color = const Color(0x88000000));
    }
    */

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

class _ZeroTick extends StatelessWidget {
  const _ZeroTick({super.key});
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: Align(
        alignment: Alignment.center,
        child: Container(width: 2, height: 16, color: Colors.black12),
      ),
    );
  }
}

enum _ActiveHandle { none, move, tl, tr, bl, br, top, right, bottom, left }
