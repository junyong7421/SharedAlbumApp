// lib/screens/edit_view_screen.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  final String albumName;
  final String? albumId;
  final String? imagePath;
  final String? editedId;
  final String? originalPhotoId;
  final String? photoId;

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
  int _selectedTool = 1; // 0=자르기,1=얼굴보정,2=밝기,3=회전/반전
  Rect? _cropRectStage;
  Size? _lastStageSize;
  double _brightness = 0.0;
  bool _brightnessApplying = false;

  // [유지] 메인 툴바 아이콘 4개
  final List<IconData> _toolbarIcons = const [
    Icons.crop,
    Icons.face_retouching_natural,
    Icons.brightness_6,
    Icons.rotate_90_degrees_ccw,
  ];

  final int _selectedIndex = 2;

  final _svc = SharedAlbumService.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  String get _name => FirebaseAuth.instance.currentUser?.displayName ?? '사용자';

  final GlobalKey _captureKey = GlobalKey();

  // [추가] presence/preview 하트비트(HEAD에서 가져옴)
  bool _isSaving = false;
  bool _isImageReady = false;
  bool _isFaceEditMode = false;

  Timer? _presenceHbTimer;   // presence heartbeat
  Timer? _editHbTimer;       // editing_by_user heartbeat
  Timer? _previewDebounce;
  String? _presenceKey;

  // [추가] develop 쪽 상태
  bool _taskLoadedOk = false; // 모델 task 로드 여부
  Uint8List? _editedBytes;    // 결과 PNG(미리보기)
  Uint8List? _originalBytes;  // 원본 바이트
  bool _modelLoaded = false;
  List<List<Offset>> _faces468 = [];
  int? _selectedFace;
  List<Rect> _faceRects = []; // 0~1 정규화 박스
  bool _showLm = false;
  bool _dimOthers = false;

  BeautyParams _beautyParams = BeautyParams();
  Uint8List? _beautyBasePng;      // 얼굴보정 기준 PNG(pixelRatio=1)
  Uint8List? _brightnessBaseBytes; // 밝기 적용 기준 바이트

  // RepaintBoundary → PNG 바이트 추출
  Future<Uint8List> _exportEditedImageBytes({double pixelRatio = 2.5}) async {
    final boundary =
        _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('캡처 대상을 찾지 못했습니다.');
    }
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('PNG 인코딩에 실패했습니다.');
    }
    return byteData.buffer.asUint8List();
  }

  Future<({String url, String storagePath})> _uploadEditedPngBytes(
      Uint8List png) async {
    if (widget.albumId == null) {
      throw StateError('albumId가 없습니다.');
    }
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

  Future<String> _uploadPreviewPng(Uint8List png) async {
    if (widget.albumId == null || _presenceKey == null) {
      throw StateError('프리뷰 업로드에 필요한 정보가 없습니다.');
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = 'albums/${widget.albumId}/previews/${_presenceKey}/$ts.png';
    final ref = FirebaseStorage.instance.ref(path);
    await ref.putData(
      png,
      SettableMetadata(contentType: 'image/png', cacheControl: 'public,max-age=60'),
    );
    return await ref.getDownloadURL();
  }

  Future<void> _onSave() async {
    if (widget.albumId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장할 수 없습니다 (albumId가 없습니다).')),
        );
      }
      return;
    }

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
      // [변경] 주석만 정리: 화면 캡처 → 업로드 → Firestore 반영
      final png = await _exportEditedImageBytes();
      final uploaded = await _uploadEditedPngBytes(png);

      if ((widget.editedId ?? '').isNotEmpty) {
        await _svc.saveEditedPhotoOverwrite(
          albumId: widget.albumId!,
          editedId: widget.editedId!,
          newUrl: uploaded.url,
          newStoragePath: uploaded.storagePath,
          editorUid: _uid,
          deleteOld: true,
        );
      } else if ((widget.originalPhotoId ?? '').isNotEmpty) {
        await _svc.saveEditedPhotoFromUrl(
          albumId: widget.albumId!,
          editorUid: _uid,
          originalPhotoId: widget.originalPhotoId!,
          editedUrl: uploaded.url,
          storagePath: uploaded.storagePath,
        );
      } else {
        await _svc.saveEditedPhoto(
          albumId: widget.albumId!,
          url: uploaded.url,
          editorUid: _uid,
          storagePath: uploaded.storagePath,
        );
      }

      // 저장 시에만 세션 종료
      try {
        await _svc.endEditing(uid: _uid, albumId: widget.albumId!);
      } catch (_) {}

      await _leavePresenceIfPossible();

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('편집이 저장되었습니다.')));
      Navigator.pop(context, 'saved');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('저장 실패: $e')));
    } finally {
      _isSaving = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _presenceKey = widget.photoId ?? widget.editedId ?? widget.originalPhotoId;

    // presence 진입 + 하트비트 시작
    _enterPresenceIfPossible();

    // editing_by_user 하트비트 시작 (active 유지)
    if (widget.albumId != null) {
      _editHbTimer?.cancel();
      _editHbTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _svc.touchEditing(uid: _uid, albumId: widget.albumId!);
      });
      // 즉시 한 번 갱신
      _svc.touchEditing(uid: _uid, albumId: widget.albumId!);
    }
  }

  @override
  void dispose() {
    _presenceHbTimer?.cancel();
    _editHbTimer?.cancel();
    _previewDebounce?.cancel();
    _leavePresenceIfPossible();
    super.dispose();
  }

  Future<void> _enterPresenceIfPossible() async {
    if (widget.albumId == null || _presenceKey == null) return;
    try {
      await _svc.enterEditingPresence(
        albumId: widget.albumId!,
        photoId: _presenceKey!,
        uid: _uid,
        name: _name,
      );
      _presenceHbTimer?.cancel();
      _presenceHbTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _svc.heartbeatEditingPresence(
          albumId: widget.albumId!,
          photoId: _presenceKey!,
          uid: _uid,
        );
      });
    } catch (_) {}
  }

  Future<void> _leavePresenceIfPossible() async {
    if (widget.albumId == null || _presenceKey == null) return;
    try {
      await _svc.leaveEditingPresence(
        albumId: widget.albumId!,
        photoId: _presenceKey!,
        uid: _uid,
      );
    } catch (_) {}
  }

  void _schedulePreviewUpdate() {
    if (widget.albumId == null || _presenceKey == null) return;
    if (!_isImageReady) return;
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 700), () async {
      try {
        final bytes = await _exportEditedImageBytes(pixelRatio: 0.7);
        final url = await _uploadPreviewPng(bytes);
        await _svc.updateEditingPreviewPresence(
          albumId: widget.albumId!,
          photoId: _presenceKey!,
          uid: _uid,
          previewUrl: url,
        );
      } catch (_) {}
    });
  }

  Future<void> _handleBack() async {
    await _leavePresenceIfPossible(); // presence만 정리
    if (mounted) Navigator.pop(context);
  }

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
    return WillPopScope(
      onWillPop: () async {
        await _handleBack();
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFE6EBFE),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: _handleBack,
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
                        ? _buildFaceEditToolbar()
                        : _buildMainToolbar(),
                  ),
                  const Spacer(),
                  const SizedBox(height: 20),
                ],
              ),
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: CustomBottomNavBar(selectedIndex: _selectedIndex),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // [변경] LayoutBuilder(자르기/얼굴 오버레이) + 다른 사용자 프리뷰(HEAD)를 통합
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

              // [추가] 자르기 오버레이
              if (_selectedTool == 0)
                Positioned.fill(
                  child: CropOverlay(
                    initRect: _cropRectStage,
                    onChanged: (r) => _cropRectStage = r,
                    onStageSize: (s) => _lastStageSize = s,
                  ),
                ),

              // [추가] 얼굴 랜드마크/치크라인 오버레이
              if (_isFaceEditMode && _faces468.isNotEmpty)
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

              // [추가] 다른 사용자의 프리뷰(투명 오버레이)
              if (widget.albumId != null && _presenceKey != null)
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _svc.editingMembersStream(
                    albumId: widget.albumId!,
                    photoId: _presenceKey!,
                  ),
                  builder: (context, snap) {
                    if (!snap.hasData) return const SizedBox.shrink();
                    final docs = snap.data!.docs;
                    String? otherPreview;
                    for (final d in docs) {
                      final data = d.data();
                      final uid = (data['uid'] ?? '') as String;
                      final url = data['previewUrl'] as String?;
                      if (uid != _uid && url != null && url.isNotEmpty) {
                        otherPreview = url;
                        break;
                      }
                    }
                    if (otherPreview == null) return const SizedBox.shrink();
                    return IgnorePointer(
                      ignoring: true,
                      child: Opacity(
                        opacity: 0.35,
                        child: Image.network(
                          otherPreview,
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  },
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

  // 단일 이미지 프리뷰(보정본 우선)
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
                _schedulePreviewUpdate(); // [추가] 최초 로드 시 프리뷰 업로드
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
            _schedulePreviewUpdate(); // [추가]
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

  // [변경] 메인 툴바: 얼굴보정 진입 시 모델 로드/검출 트리거, 밝기 베이스 고정
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
                  if (i == 2) {
                    _brightness = 0.0;
                    _brightnessBaseBytes =
                        await _currentBytes(); // [추가] 밝기 기준 고정
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
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: switch (_selectedTool) {
            0 => _cropPanel(),
            2 => _brightnessPanel(),
            3 => _rotatePanel(),
            _ => const SizedBox.shrink(),
          },
        ),
      ],
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

  // ======= 패널/도구들 =======
  Widget _cropPanel() => Row(
        key: const ValueKey('crop'),
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _pill('초기화', () async {
            await _resetToOriginal(); // [추가]
            _schedulePreviewUpdate(); // [추가]
          }),
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
          _pill('적용', () async {
            await _applyCrop();
            _schedulePreviewUpdate(); // [추가]
          }),
        ],
      );

  Widget _brightnessPanel() => Column(
        key: const ValueKey('brightness'),
        children: [
          Row(
            children: [
              const SizedBox(width: 8),
              const Icon(Icons.brightness_low, size: 18),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                        ),
                        child: Slider(
                          value: _brightness, // -0.5 ~ 0.5
                          min: -0.5,
                          max: 0.5,
                          divisions: 20,
                          label: _brightness.toStringAsFixed(2),
                          onChanged: (v) => setState(() => _brightness = v),
                          onChangeEnd: (_) async {
                            await _applyBrightness();
                            _schedulePreviewUpdate(); // [추가]
                          },
                        ),
                      ),
                      IgnorePointer(
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

  Widget _rotatePanel() => Row(
        key: const ValueKey('rotate'),
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _pill('왼쪽 90°', () async {
            await _applyRotate(-90);
            _schedulePreviewUpdate(); // [추가]
          }),
          _pill('오른쪽 90°', () async {
            await _applyRotate(90);
            _schedulePreviewUpdate(); // [추가]
          }),
          _pill('좌우 반전', () async {
            await _applyFlipH();
            _schedulePreviewUpdate(); // [추가]
          }),
          _pill('상하 반전', () async {
            await _applyFlipV();
            _schedulePreviewUpdate(); // [추가]
          }),
        ],
      );

  Future<Uint8List> _currentBytes() async {
    if (_editedBytes != null) return _editedBytes!;
    if (_originalBytes == null) await _loadOriginalBytes();
    return _editedBytes ?? _originalBytes!;
  }

  Future<void> _applyCrop() async {
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
    if (_brightnessApplying) return;
    _brightnessApplying = true;
    setState(() {});

    try {
      final base = _brightnessBaseBytes ?? await _currentBytes();
      if (_brightness.abs() < 1e-6) {
        setState(() => _editedBytes = base);
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
    await _loadOriginalBytes();
    setState(() {
      _editedBytes = null;
      _cropRectStage = null;
      _brightness = 0.0;
      _brightnessBaseBytes = null;
      _beautyBasePng = null;
    });
  }

  Future<void> _applyRotate(int deg) async {
    final bytes = await _currentBytes();
    setState(() => _editedBytes = ImageOps.rotate(bytes, deg));
  }

  Future<void> _applyFlipH() async {
    final bytes = await _currentBytes();
    setState(() => _editedBytes = ImageOps.flipHorizontal(bytes));
  }

  Future<void> _applyFlipV() async {
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

  // 얼굴보정 전용 툴바
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
        _faceTool(
          icon: _showLm ? Icons.visibility : Icons.visibility_off,
          onTap: () => setState(() => _showLm = !_showLm),
        ),
        _faceTool(icon: Icons.brush, onTap: _openBeautyPanel),
      ],
    );
  }

  Widget _faceTool({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4),
        child: Icon(icon, size: 22, color: Colors.black87),
      ),
    );
  }

  Future<void> _openBeautyPanel() async {
    if (_selectedFace == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('얼굴을 먼저 선택하세요.')));
      return;
    }

    _beautyBasePng ??= await _exportEditedImageBytes(pixelRatio: 1.0);
    final Size stageSize = _captureKey.currentContext!.size!;

    final result =
        await showModalBottomSheet<({Uint8List image, BeautyParams params})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => BeautyPanel(
        srcPng: _beautyBasePng!,
        faces468: _faces468,
        selectedFace: _selectedFace!,
        imageSize: stageSize,
        initialParams: _beautyParams,
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _editedBytes = result.image;
        _beautyParams = result.params;
      });
      _schedulePreviewUpdate(); // [추가]
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
    if (!_modelLoaded) {
      final task = await rootBundle.load(
        'assets/mediapipe/face_landmarker.task',
      );
      await FaceLandmarker.loadModel(task.buffer.asUint8List(), maxFaces: 5);
      _modelLoaded = true;
    }
    if (_originalBytes == null) {
      await _loadOriginalBytes();
    }
    if (_originalBytes == null) return;

    final faces = await FaceLandmarker.detect(_originalBytes!);

    setState(() {
      _faces468 = faces;
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

enum _ActiveHandle { none, move, tl, tr, bl, br, top, right, bottom, left }