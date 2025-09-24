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
import 'package:flutter/services.dart' show rootBundle, NetworkAssetBundle;
import 'face_landmarker.dart';
import '../beauty/beauty_panel.dart';
import 'package:sharedalbumapp/beauty/beauty_controller.dart';
import '../edit_tools/image_ops.dart';
import '../edit_tools/crop_overlay.dart';
import 'package:image/image.dart' as img;
import 'voice_call_popup.dart';
import 'voice_call_overlay.dart';
import '../services/shared_album_list_service.dart';

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

class _ConfirmExitPopup extends StatelessWidget {
  const _ConfirmExitPopup({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFF6F9FF),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFF625F8C), width: 2),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '편집이 저장되지 않았습니다',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF625F8C),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              '저장하지 않고 나가시겠습니까?',
              style: TextStyle(fontSize: 14, color: Color(0xFF625F8C)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),

            // 버튼 영역
            // 버튼 영역 (Stack 제거 → Column으로)
            SizedBox(
              height: 92, // 전체 버튼 영역 높이 (원하면 84~100 사이로 조절)
              child: Column(
                children: [
                  // 위쪽: 저장 안 함 / 저장 (가운데 정렬)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _GradientButton(
                        label: '저장 안 함',
                        onTap: () => Navigator.pop(context, 'discard'),
                        width: 116,
                        height: 40,
                      ),
                      const SizedBox(width: 45), // 두 버튼 간 간격
                      _GradientButton(
                        label: '저장',
                        onTap: () => Navigator.pop(context, 'save'),
                        width: 96,
                        height: 40,
                      ),
                    ],
                  ),

                  const Spacer(), // 아래로 공간 밀어냄
                  // 아래: 취소 (좌측 하단 고정, 작게)
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: 8,
                        bottom: 4,
                      ), // 가장자리 여백
                      child: _GradientButton(
                        label: '취소',
                        onTap: () => Navigator.pop(context, 'cancel'),
                        width: 60, // 반 사이즈
                        height: 28, // 반 사이즈
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final double width;
  final double height;
  final double fontSize;

  const _GradientButton({
    super.key,
    required this.label,
    required this.onTap,
    this.width = 100,
    this.height = 40,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFFC6DCFF), Color(0xFFD2D1FF), Color(0xFFF5CFFF)],
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(1, 1),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: fontSize,
          ),
        ),
      ),
    );
  }
}

class _EditViewScreenState extends State<EditViewScreen> {
  // **[추가]** 편집중 배지 표시 여부 (기본: 끔) -> 표시할거면 true로
  static const bool _kShowEditorsBadge = false;
  final _listSvc = SharedAlbumListService.instance;
  // ▼ 4개 툴 전환: 0=자르기, 1=얼굴보정, 2=밝기, 3=회전/반전
  int _selectedTool = -1; // 0=자르기,1=얼굴보정,2=밝기,3=회전/반전
  Rect? _cropRectStage;
  Size? _lastStageSize;

  // === 밝기 동기화 핵심 상태 ===
  double _brightness = 0.0;
  bool _brightnessApplying = false;
  Uint8List? _brightnessBaseBytes; // 밝기 적용 앵커(결정적 파이프라인 결과)
  bool _rxBrightnessSession = false;

  // OPS에서 마지막으로 본 밝기 절대값(슬라이더/이미지 통일 기준)
  double _latestBrightnessValue = 0.0;

  // 얼굴별 보정 파라미터 저장소 (동기화의 소스 오브 트루스)
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

  final _svc = SharedAlbumService.instance;
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  final GlobalKey _captureKey = GlobalKey();

  bool _isSaving = false;
  bool _isImageReady = false;
  bool _isFaceEditMode = false;

  // 실시간 키(원본 우선)
  String? _targetKey; // == rootPhotoId

  bool _taskLoadedOk = false;
  Uint8List? _editedBytes;
  Uint8List? _originalBytes;
  bool _modelLoaded = false;
  List<List<Offset>> _faces468 = [];
  int? _selectedFace;
  List<Rect> _faceRects = []; // 0~1
  bool _showLm = false;
  bool _dimOthers = false;

  BeautyParams _beautyParams = BeautyParams();
  Uint8List? _beautyBasePng; // 보정/저장용 결과(결정적 베이스 PNG)

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

  bool _dirty = false;
  bool get _hasUnsavedChanges => _dirty || _cropRectStage != null;

  // ===== 실시간 OPS =====
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _opsSub;

  // 적용/중복 방지 세트 (문서ID + opId 동시 관리)
  final Set<String> _appliedDocIds = {};
  final Set<String> _seenOpIds = {};

  // 커서(백필 이후 이어받기용): createdAt + docId
  Timestamp? _lastOpTs;
  String? _lastOpDocId;

  // === 누적 변환의 "절대 상태" ===
  int _rotDeg = 0; // 0/90/180/270
  bool _flipHState = false; // 좌우 반전
  bool _flipVState = false; // 상하 반전
  Rect? _cropNorm; // 0~1 정규화 크롭(l,t,r,b)

  Future<String> _nameForAlbum(String id) async {
    if ((widget.albumId ?? '') == id) return widget.albumName;
    // 필요하면 SharedAlbumListService에서 이름을 더 찾아와도 됨.
    return '보이스톡';
  }

  // 통화 버튼 onTap
  Future<void> _onTapCall() async {
    try {
      // 1) 내가 이미 붙어있는 보이스룸이 있으면 그쪽으로, 아니면 화면의 albumId로
      final activeAlbumId = await _listSvc.getMyActiveVoiceAlbumId();
      final targetAlbumId = activeAlbumId ?? widget.albumId;

      if (targetAlbumId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('참여 중인 보이스룸이 없고, 이 화면에 앨범도 없어요.')),
        );
        return;
      }

      // 2) 입장 (이미 붙어있으면 내부에서 스킵)
      await _listSvc.joinVoice(albumId: targetAlbumId);

      // 3) 오버레이 + 참가자 팝업
      final albumName = await _nameForAlbum(targetAlbumId);
      voiceOverlay.show(albumId: targetAlbumId, albumName: albumName);

      final stream = _listSvc
          .watchVoiceParticipants(targetAlbumId)
          .map(
            (list) => list
                .map(
                  (m) => MemberLite(
                    uid: m.uid,
                    name: (m.name).isNotEmpty ? m.name : m.email,
                  ),
                )
                .toList(),
          );
      final initial = await stream.first;
      if (!mounted) return;

      await showVoiceNowPopup(
        context,
        albumName: albumName,
        initialParticipants: initial,
        participantsStream: stream,
        onLeave: () async {
          await _listSvc.leaveVoice(albumId: targetAlbumId);
          voiceOverlay.hide();
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('보이스톡 진입 실패: $e')));
    }
  }

  // ===== 공용 유틸 =====
  Future<Uint8List> _currentBytes() async {
    if (_editedBytes != null) return _editedBytes!;
    if (_originalBytes == null) await _loadOriginalBytes();
    return _editedBytes ?? _originalBytes!;
  }

  // 정규화 좌표(0~1)용 회전/반전 매핑
  Offset _applyRotationNorm(Offset p, int deg) {
    final d = ((deg % 360) + 360) % 360;
    switch (d) {
      case 90: // +90° CW
        return Offset(1 - p.dy, p.dx);
      case 180: // +180°
        return Offset(1 - p.dx, 1 - p.dy);
      case 270: // +270° CW == -90°
        return Offset(p.dy, 1 - p.dx);
      default: // 0°
        return p;
    }
  }

  // 추가: 파일 상단 State 안에
  Timer? _lmDebounce;
  void _scheduleRedetect() {
    _lmDebounce?.cancel();
    _lmDebounce = Timer(const Duration(milliseconds: 100), () async {
      await _rerunFaceDetectOnCurrentGeometry();
    });
  }

  Offset _applyFlipNorm(Offset p, {bool h = false, bool v = false}) {
    double x = p.dx, y = p.dy;
    if (h) x = 1 - x;
    if (v) y = 1 - y;
    return Offset(x, y);
  }

  // p: 0~1 정규화 좌표, cropNorm: 0~1 정규화 크롭(Rect.fromLTRB(l,t,r,b))
  Offset _applyCropNorm(Offset p, Rect cropNorm) {
    final w = (cropNorm.width).clamp(1e-9, 1.0);
    final h = (cropNorm.height).clamp(1e-9, 1.0);
    return Offset((p.dx - cropNorm.left) / w, (p.dy - cropNorm.top) / h);
  }

  Offset _clamp01(Offset p) =>
      Offset(p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0));

  void _transformFacesForGeometryChange({
    int rotDeltaDeg = 0,
    bool flipHDelta = false,
    bool flipDeltaV = false, // 오타 아님? => flipVDelta로 쓰세요
    Rect? cropNormDelta, // 새로 적용된 크롭(정규화)
  }) {
    if (_faces468.isEmpty) return;

    List<List<Offset>> newFaces = _faces468.map((face) {
      Iterable<Offset> pts = face;

      // ✅ 1) 회전 델타
      if ((rotDeltaDeg % 360) != 0) {
        pts = pts.map((p) => _applyRotationNorm(p, rotDeltaDeg));
      }
      // ✅ 2) 좌우, 3) 상하
      if (flipHDelta) pts = pts.map((p) => _applyFlipNorm(p, h: true));
      if (flipDeltaV) pts = pts.map((p) => _applyFlipNorm(p, v: true));

      // ✅ 4) 크롭
      if (cropNormDelta != null) {
        pts = pts.map((p) => _applyCropNorm(p, cropNormDelta));
      }
      return pts.map(_clamp01).toList();
    }).toList();

    // 2) rect 재계산
    final rects = newFaces.map((pts) {
      double minX = 1, minY = 1, maxX = 0, maxY = 0;
      for (final p in pts) {
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy > maxY) maxY = p.dy;
      }
      return Rect.fromLTRB(minX, minY, maxX, maxY);
    }).toList();

    setState(() {
      _faces468 = newFaces;
      _faceRects = rects;
    });
  }

  // === 정규화 크롭 유틸 (이미지 좌표계 기준)
  Future<Uint8List> _cropNormalizedBytes(Uint8List src, Rect norm) async {
    final codec = await ui.instantiateImageCodec(src);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final int sx = (norm.left * img.width).clamp(0, img.width - 1).round();
    final int sy = (norm.top * img.height).clamp(0, img.height - 1).round();
    final int ex = (norm.right * img.width).clamp(1, img.width).round();
    final int ey = (norm.bottom * img.height).clamp(1, img.height).round();
    final int cw = (ex - sx).clamp(1, img.width);
    final int ch = (ey - sy).clamp(1, img.height);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final dstRect = Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble());
    final srcRect = Rect.fromLTWH(
      sx.toDouble(),
      sy.toDouble(),
      cw.toDouble(),
      ch.toDouble(),
    );
    final paint = Paint();
    canvas.drawImageRect(img, srcRect, dstRect, paint);
    final picture = recorder.endRecording();
    final cropped = await picture.toImage(cw, ch);
    final byteData = await cropped.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  // === 결정적 앵커 렌더 (원본 → 회전 → 반전 → 정규화 크롭) : 밝기
  Future<Uint8List> _renderBaseForBrightness() async {
    if (_originalBytes == null) await _loadOriginalBytes();
    Uint8List out = _originalBytes!;

    if (_cropNorm != null) out = await _cropNormalizedBytes(out, _cropNorm!);
    if (_rotDeg % 360 != 0) out = ImageOps.rotate(out, _rotDeg);
    if (_flipHState) out = ImageOps.flipHorizontal(out);
    if (_flipVState) out = ImageOps.flipVertical(out);

    return out;
  }

  // === 결정적 앵커 렌더 (원본 → 회전 → 반전 → 정규화 크롭 → PNG) : 얼굴보정
  Future<Uint8List> _renderBaseForBeauty() async {
    final base = await _renderBaseForBrightness();
    // PNG 통일
    final im = img.decodeImage(base);
    if (im == null) throw StateError('이미지를 디코드할 수 없습니다.');
    return Uint8List.fromList(img.encodePng(im));
  }

  // 지오메트리(원본→회전→반전→크롭)만 적용된 PNG
  Future<Uint8List> _renderGeometryBasePng() => _renderBaseForBeauty();

  // 현재 지오메트리에서 랜드마크가 없으면 재검출을 보장
  Future<void> _ensureFacesOnCurrentGeometry() async {
    if (_faces468.isEmpty) {
      await _rerunFaceDetectOnCurrentGeometry();
    }
  }

  // 지오메트리 + (있다면) 얼굴보정까지 반영한 PNG 반환
  Future<Uint8List> _renderBeautyBasePng() async {
    final geoPng = await _renderGeometryBasePng();
    if (_faceParams.isEmpty) return geoPng;

    await _ensureFacesOnCurrentGeometry();
    final imInfo = img.decodeImage(geoPng)!;
    final Size imgSize = Size(
      imInfo.width.toDouble(),
      imInfo.height.toDouble(),
    );

    final ctrl = BeautyController();
    return await ctrl.applyCumulative(
      srcPng: geoPng,
      faces468: _faces468,
      imageSize: imgSize,
      paramsByFace: _faceParams,
    );
  }

  // 글로벌 조정만 합성 (입력은 PNG 권장: beautyBase)
  Uint8List _applyGlobalAdjustments(Uint8List basePng) {
    Uint8List out = basePng;
    if (_latestBrightnessValue.abs() > 1e-6) {
      out = ImageOps.adjustBrightness(out, _latestBrightnessValue);
    }
    if (_saturation.abs() > 1e-6) {
      out = ImageOps.adjustSaturation(out, _saturation);
    }
    if (_sharp.abs() > 1e-6) {
      out = ImageOps.sharpen(out, _sharp);
    }
    return out;
  }

  // 지오메트리 → (얼굴보정) → 글로벌 조정 전체 파이프라인
  Future<Uint8List> _renderFullPipelinePng() async {
    final beautyBase = await _renderBeautyBasePng();
    return _applyGlobalAdjustments(beautyBase);
  }

  // ===== PNG 캡처/업로드 =====
  // 개선된 버전만 유지
  Future<Uint8List> _exportEditedImageBytes({
    double pixelRatio = 2.5,
    bool hideOverlay = false, // 캡처 직전에 오버레이 숨길지
  }) async {
    final prevOverlay = _faceOverlayOn;
    if (hideOverlay && prevOverlay) {
      setState(() => _faceOverlayOn = false);
      await Future.delayed(const Duration(milliseconds: 16));
    }

    final boundary =
        _captureKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('캡처 대상을 찾지 못했습니다.');

    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw StateError('PNG 인코딩 실패');

    if (hideOverlay && prevOverlay && mounted) {
      setState(() => _faceOverlayOn = true);
    }

    return byteData.buffer.asUint8List();
  }

  Future<void> _refreshGeoSizeFromCurrentGeometry() async {
    final basePng = await _renderBaseForBeauty();
    final im = img.decodeImage(basePng);
    if (im != null && mounted) {
      setState(() {
        _geoImgSize = Size(im.width.toDouble(), im.height.toDouble());
      });
    }
  }

  Future<({String url, String storagePath})> _uploadEditedPngBytes(
    Uint8List png,
  ) async {
    if (widget.albumId == null) throw StateError('albumId가 없습니다.');
    // [변경][root] 업로드 폴더 키를 rootPhotoId로 고정
    final photoKey =
        _targetKey ??
        widget.originalPhotoId ??
        widget.photoId ??
        widget.editedId ??
        _uid;

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

  Future<void> _onSave() async {
    if (widget.albumId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장할 수 없습니다 (albumId 없음)')),
        );
      }
      return;
    }
    if (_isSaving || !_isImageReady) return;
    _isSaving = true;

    try {
      // ✅ 현재 결과를 PNG로 변환
      final raw = await _currentBytes();
      Uint8List _asPng(Uint8List b) {
        final im = img.decodeImage(b);
        if (im == null) throw StateError('이미지를 디코드할 수 없습니다.');
        return Uint8List.fromList(img.encodePng(im));
      }

      final png = _asPng(raw);
      final uploaded = await _uploadEditedPngBytes(png);

      // 문서 갱신 로직 (editedId / originalPhotoId / rootPhotoId 분기)
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
        if (_targetKey == null) throw StateError('rootPhotoId를 확인할 수 없습니다.');
        await _svc.saveEditedPhoto(
          albumId: widget.albumId!,
          url: uploaded.url,
          editorUid: _uid,
          originalPhotoId: _targetKey!,
          storagePath: uploaded.storagePath,
        );
      }

      // OP 브로드캐스트 + 정리
      if (_targetKey != null) {
        await _sendOp('commit', {
          'by': _uid,
          'at': DateTime.now().toIso8601String(),
        });
        await Future.delayed(const Duration(milliseconds: 200));
        await _svc.tryCleanupOpsIfNoEditors(
          albumId: widget.albumId!,
          photoId: _targetKey!,
        );
      }

      _appliedDocIds.clear();
      _seenOpIds.clear();
      _lastOpTs = null;
      _lastOpDocId = null;
      await _svc
          .endEditing(uid: _uid, albumId: widget.albumId!)
          .catchError((_) {});

      _dirty = false;
      if (!mounted) return;
      Navigator.pop(context, {'status': 'saved', 'editedUrl': uploaded.url});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      }
    } finally {
      _isSaving = false;
    }
  }

  // ===== OP 송수신 =====
  Future<void> _sendOp(String type, Map<String, dynamic> data) async {
    if (widget.albumId == null || _targetKey == null) return;
    try {
      await _svc.sendEditOp(
        albumId: widget.albumId!,
        // [변경][root] 모든 클라 공동 키(= rootPhotoId)
        photoId: _targetKey!,
        op: {'type': type, 'data': data, 'by': _uid},
      );
    } catch (_) {}
  }

  // === 수신 OP 적용 ===
  Future<void> _applyIncomingOp(Map<String, dynamic> op) async {
    final type = op['type'] as String? ?? '';
    final data = (op['data'] as Map?)?.cast<String, dynamic>() ?? const {};

    switch (type) {
      case 'commit':
        if (!mounted) return;
        _opsSub?.cancel();
        try {
          if (widget.albumId != null && _uid.isNotEmpty) {
            await _svc.endEditing(uid: _uid, albumId: widget.albumId!);
          }
        } catch (_) {}
        if (mounted) {
          Navigator.pop(context, {'status': 'peer_saved'});
        }
        return;

      case 'brightness':
        {
          final v = (data['value'] as num?)?.toDouble() ?? 0.0;
          _latestBrightnessValue = v;
          _brightness = v;

          final base = await _renderBeautyBasePng(); // ★ 변경
          _brightnessBaseBytes = Uint8List.fromList(base);
          _adjustBaseBytes = base; // ★ 앵커 일치
          final composed = _applyGlobalAdjustments(base); // ★ 변경

          setState(() => _editedBytes = composed);
          break;
        }

      case 'crop':
        {
          final l = (data['l'] as num).toDouble();
          final t = (data['t'] as num).toDouble();
          final r = (data['r'] as num).toDouble();
          final b = (data['b'] as num).toDouble();

          // 현재 결과(없으면 원본) 바이트 기준으로 정규화 크롭
          final src = await _currentBytes();
          final normRect = Rect.fromLTRB(l, t, r, b);
          final out = await _cropNormalizedBytes(src, normRect);

          setState(() {
            _editedBytes = out;
            _cropNorm = normRect;
            _dirty = true;
          });

          final im = img.decodeImage(out);
          if (im != null) {
            _geoImgSize = Size(im.width.toDouble(), im.height.toDouble());
          }

          _transformFacesForGeometryChange(cropNormDelta: normRect);
          // 밝기/채도/샤픈 등의 "결정적 앵커"가 있다면 재적용
          await _reapplyAdjustmentsIfActive();
          _scheduleRedetect();
          break;
        }

      case 'rotate':
        {
          final deg = (data['deg'] as num?)?.toInt() ?? 0;
          final bytesR = await _currentBytes();
          setState(() => _editedBytes = ImageOps.rotate(bytesR, deg));

          _rotDeg = ((_rotDeg + deg) % 360 + 360) % 360;
          _transformFacesForGeometryChange(rotDeltaDeg: deg);
          if (_geoImgSize != null && (deg % 180 != 0)) {
            _geoImgSize = Size(_geoImgSize!.height, _geoImgSize!.width); // ✅
          }
          await _reapplyAdjustmentsIfActive();
          await _refreshGeoSizeFromCurrentGeometry();
          _scheduleRedetect();
          break;
        }

      case 'flip':
        {
          final dir = (data['dir'] as String?) ?? 'h';
          final bytesF = await _currentBytes();
          setState(() {
            _editedBytes = (dir == 'v')
                ? ImageOps.flipVertical(bytesF)
                : ImageOps.flipHorizontal(bytesF);
          });

          if (dir == 'v') {
            _flipVState = !_flipVState;
            _transformFacesForGeometryChange(flipDeltaV: true);
          } else {
            _flipHState = !_flipHState;
            _transformFacesForGeometryChange(flipHDelta: true);
          }
          await _reapplyAdjustmentsIfActive();
          _scheduleRedetect();
          break;
        }

      // ===== 얼굴 보정 실시간 수신 =====
      // lib/screens/edit_view_screen.dart 내 _applyIncomingOp(...) 안의
      // case 'beauty': 블록 교체

      case 'beauty':
        {
          // 1) 파라미터 파싱
          final faceIdx = (data['face'] as num?)?.toInt();
          final paramsMap = (data['params'] as Map?)?.cast<String, dynamic>();
          // final prevMap = (data['prev'] as Map?)?.cast<String, dynamic>(); // 누적렌더에는 불필요

          if (faceIdx == null || paramsMap == null) break;

          final newParams = beautyParamsFromMap(paramsMap);

          // 2) 랜드마크 보장
          if (_faces468.isEmpty) {
            await _rerunFaceDetectOnCurrentGeometry(); // ★ 지오메트리 기준
            if (_faces468.isEmpty) break;
          }

          // 3) 베이스 PNG(원본→회전→반전→크롭)
          final basePng = await _renderBaseForBeauty();

          // 4) 이미지 사이즈
          final imInfo = img.decodeImage(basePng);
          if (imInfo == null) break;
          final Size imgSize = Size(
            imInfo.width.toDouble(),
            imInfo.height.toDouble(),
          );

          // 5) 소스 오브 트루스 업데이트
          _faceParams[faceIdx] = newParams;

          // 6) ★ 누적 재렌더
          final ctrl = BeautyController();
          final outBytes = await ctrl.applyCumulative(
            srcPng: basePng,
            faces468: _faces468,
            imageSize: imgSize,
            paramsByFace: _faceParams,
          );

          // 7) 반영
          setState(() {
            _editedBytes = outBytes;
            _dirty = true;
          });
          // 얼굴보정 결과(outBytes)는 "얼굴보정까지 반영된 베이스"로 간주
          _adjustBaseBytes = outBytes;
          _brightnessBaseBytes = Uint8List.fromList(outBytes);

          // 이미 글로벌 조정 값이 있다면 다시 합성해서 화면에 반영
          final composedAfterBeauty = _applyGlobalAdjustments(outBytes);
          setState(() {
            _editedBytes = composedAfterBeauty;
          });
          break;
        }
      case 'sharpen':
        {
          final v = (data['value'] as num?)?.toDouble() ?? 0.0;
          _sharp = v;

          final base = await _renderBeautyBasePng(); // ★ 변경
          _adjustBaseBytes = base;
          final composed = _applyGlobalAdjustments(base); // ★ 변경

          setState(() {
            _editedBytes = composed;
            _dirty = true;
          });
          break;
        }
      case 'saturation':
        {
          final v = (data['value'] as num?)?.toDouble() ?? 0.0;
          _saturation = v;

          final base = await _renderBeautyBasePng(); // ★ 변경
          _adjustBaseBytes = base;
          final composed = _applyGlobalAdjustments(base); // ★ 변경

          setState(() {
            _editedBytes = composed;
            _dirty = true;
          });
          break;
        }
    }
    _dirty = true;
  }

  Future<void> _reapplyAdjustmentsIfActive() async {
    // ❌ 재검출 제거
    final composed = await _renderFullPipelinePng();
    setState(() {
      _editedBytes = composed;
    });
  }

  Size? _geoImgSize; // 상태 추가
  // 지오메트리(회전/반전/크롭) 이후 베이스PNG 기준으로 다시 얼굴 인식
  Future<void> _rerunFaceDetectOnCurrentGeometry() async {
    await _ensureFaceModelLoaded();

    // 0) 현재 지오메트리(회전/반전/크롭)까지 반영된 PNG
    final basePng = await _renderBaseForBeauty();
    final im = img.decodeImage(basePng)!;
    final newSize = Size(im.width.toDouble(), im.height.toDouble());

    // 기존 rects 백업(매핑용)
    final oldRects = List<Rect>.from(_faceRects);

    // ✅ 올바른 되돌리기: [상하] → [좌우] → [회전 취소]
    Uint8List detBytes = basePng;
    if (_flipVState) detBytes = ImageOps.flipVertical(detBytes);
    if (_flipHState) detBytes = ImageOps.flipHorizontal(detBytes);
    if (_rotDeg % 360 != 0) detBytes = ImageOps.rotate(detBytes, -_rotDeg);

    // 2) 탐지
    final facesUpright = await FaceLandmarker.detect(detBytes);

    // ✅ 올바른 재적용: [회전] → [좌우] → [상하]
    List<List<Offset>> facesTransformed = facesUpright.map((pts) {
      var out = pts;
      if ((_rotDeg % 360) != 0) {
        out = out.map((p) => _applyRotationNorm(p, _rotDeg)).toList();
      }
      if (_flipHState) {
        out = out.map((p) => _applyFlipNorm(p, h: true)).toList();
      }
      if (_flipVState) {
        out = out.map((p) => _applyFlipNorm(p, v: true)).toList();
      }
      return out;
    }).toList();

    // 4) rect 재계산(0~1)
    final rects = facesTransformed.map((pts) {
      double minX = 1, minY = 1, maxX = 0, maxY = 0;
      for (final p in pts) {
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy > maxY) maxY = p.dy;
      }
      return Rect.fromLTRB(minX, minY, maxX, maxY);
    }).toList();

    // 5) 인덱스 매핑(중심거리로)
    Map<int, int>? mapping;
    if (_faceParams.isNotEmpty && oldRects.isNotEmpty && rects.isNotEmpty) {
      mapping = _matchFacesByCenter(oldRects, rects, newSize);
      if (mapping.isNotEmpty) {
        final remapped = <int, BeautyParams>{};
        _faceParams.forEach((oldIdx, params) {
          final ni = mapping![oldIdx];
          if (ni != null) remapped[ni] = params;
        });
        _faceParams
          ..clear()
          ..addAll(remapped);
      }
    }

    if (!mounted) return;
    setState(() {
      _faces468 = facesTransformed;
      _faceRects = rects;
      _geoImgSize = newSize; // 오버레이 박스피트 기준 갱신
      if (_selectedFace != null && mapping != null) {
        _selectedFace = mapping[_selectedFace!];
      }
    });
  }

  // ===== 백필 + 실시간 구독 =====
  Future<void> _prepareAndSubscribe() async {
    if (widget.albumId == null || _targetKey == null) return;

    try {
      await Future.delayed(const Duration(milliseconds: 120));
      final opsCol = FirebaseFirestore.instance
          .collection('albums')
          .doc(widget.albumId!)
          .collection('ops');

      // 1) 백필 (createdAt ASC, docId ASC)
      final backfill = await opsCol
          .where('photoId', isEqualTo: _targetKey)
          .orderBy('createdAt', descending: false)
          .orderBy(FieldPath.documentId, descending: false)
          .limit(1000)
          .get();

      for (final d in backfill.docs) {
        final data = d.data();

        // op 추출(서버가 op 필드에 래핑 저장)
        final opMap = (data['op'] as Map?)?.cast<String, dynamic>();
        final op =
            opMap ??
            <String, dynamic>{
              'type': data['type'],
              'data': data['data'],
              'by': data['by'],
            };

        // 중복 체크: 문서ID + opId
        final docId = d.id;
        final opId =
            (op['opId'] as String?) ??
            ((op['editorUid'] != null)
                ? '${op['editorUid']}_${data['createdAt'] ?? ''}_$docId'
                : null);

        if (_appliedDocIds.contains(docId)) continue;
        if (opId != null && _seenOpIds.contains(opId)) continue;

        _appliedDocIds.add(docId);
        if (opId != null) _seenOpIds.add(opId);

        await _applyIncomingOp(op);

        // 커서 갱신
        final ts = data['createdAt'];
        if (ts is Timestamp) {
          if (_lastOpTs == null ||
              ts.millisecondsSinceEpoch > _lastOpTs!.millisecondsSinceEpoch ||
              (ts == _lastOpTs && (docId.compareTo(_lastOpDocId ?? '') > 0))) {
            _lastOpTs = ts;
            _lastOpDocId = docId;
          }
        }
      }

      // 2) 실시간 (커서 이후만, 정렬 동일)
      Query<Map<String, dynamic>> q = opsCol
          .where('photoId', isEqualTo: _targetKey)
          .orderBy('createdAt', descending: false)
          .orderBy(FieldPath.documentId, descending: false);

      if (_lastOpTs != null && _lastOpDocId != null) {
        q = q.startAfter([_lastOpTs, _lastOpDocId]);
      }

      _opsSub?.cancel();
      _opsSub = q
          .snapshots(includeMetadataChanges: true)
          .listen(_onOpsSnapshot);

      // 3) 프레임 이후 세션 등록
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _registerSessionOnce();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('초기 준비 실패: $e')));
    }
  }

  void _onOpsSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    for (final ch in snap.docChanges) {
      if (ch.type != DocumentChangeType.added) continue;
      final m = ch.doc.data();
      if (m == null) continue;

      final docId = ch.doc.id;
      if (_appliedDocIds.contains(docId)) continue;

      // op 래핑 추출
      final opMap = (m['op'] as Map?)?.cast<String, dynamic>();
      final op =
          opMap ??
          <String, dynamic>{
            'type': m['type'],
            'data': m['data'],
            'by': m['by'],
          };

      // 내가 보낸 건 스킵(op.editorUid/by 확인)
      final sender = (op['editorUid'] as String?) ?? (op['by'] as String?);
      if (_uid.isNotEmpty && sender == _uid) {
        _appliedDocIds.add(docId);
        // 커서만 갱신
        final tsMine = m['createdAt'];
        if (tsMine is Timestamp) {
          if (_lastOpTs == null ||
              tsMine.millisecondsSinceEpoch >
                  _lastOpTs!.millisecondsSinceEpoch ||
              (tsMine == _lastOpTs &&
                  (docId.compareTo(_lastOpDocId ?? '') > 0))) {
            _lastOpTs = tsMine;
            _lastOpDocId = docId;
          }
        }
        continue;
      }

      // opId 중복 방지
      final opId =
          (op['opId'] as String?) ??
          ((sender != null)
              ? '${sender}_${m['createdAt'] ?? ''}_$docId'
              : null);
      if (opId != null && _seenOpIds.contains(opId)) {
        _appliedDocIds.add(docId);
        continue;
      }

      _appliedDocIds.add(docId);
      if (opId != null) _seenOpIds.add(opId);

      _applyIncomingOp(op);

      // 커서 갱신
      final ts = m['createdAt'];
      if (ts is Timestamp) {
        if (_lastOpTs == null ||
            ts.millisecondsSinceEpoch > _lastOpTs!.millisecondsSinceEpoch ||
            (ts == _lastOpTs && (docId.compareTo(_lastOpDocId ?? '') > 0))) {
          _lastOpTs = ts;
          _lastOpDocId = docId;
        }
      }
    }
  }

  Rect _contentRectForCover(Size imageSize, Size paintSize) {
    final fitted = applyBoxFit(BoxFit.cover, imageSize, paintSize);
    final renderSize = fitted.destination; // 최종 그려질 크기
    final dx = (paintSize.width - renderSize.width) / 2;
    final dy = (paintSize.height - renderSize.height) / 2;
    return Rect.fromLTWH(dx, dy, renderSize.width, renderSize.height);
  }

  Rect _rectFromNorm(Rect r, Size imgSize) => Rect.fromLTWH(
    r.left * imgSize.width,
    r.top * imgSize.height,
    r.width * imgSize.width,
    r.height * imgSize.height,
  );

  double _centerDistSq(Rect a, Rect b) {
    final ca = a.center, cb = b.center;
    final dx = ca.dx - cb.dx, dy = ca.dy - cb.dy;
    return dx * dx + dy * dy; // sqrt 불필요
  }

  Map<int, int> _matchFacesByCenter(
    List<Rect> oldRects,
    List<Rect> newRects,
    Size imgPxSize,
  ) {
    // 픽셀 좌표로 변환(정규화→픽셀) 후 중심거리로 가장 가까운 것 매칭
    final oldPx = oldRects.map((r) => _rectFromNorm(r, imgPxSize)).toList();
    final newPx = newRects.map((r) => _rectFromNorm(r, imgPxSize)).toList();

    final usedNew = <int>{};
    final mapping = <int, int>{}; // oldIdx -> newIdx

    for (int oi = 0; oi < oldPx.length; oi++) {
      double best = double.infinity;
      int? bestNi;
      for (int ni = 0; ni < newPx.length; ni++) {
        if (usedNew.contains(ni)) continue;
        final d2 = _centerDistSq(oldPx[oi], newPx[ni]); // ✅ 여기!
        if (d2 < best) {
          best = d2;
          bestNi = ni;
        }
      }
      if (bestNi != null) {
        usedNew.add(bestNi);
        mapping[oi] = bestNi;
      }
    }
    return mapping;
  }

  // ======== 루트 키 계산 ========
  // [추가][root] editedId로 들어온 경우 originalPhotoId를 읽어서 rootKey를 만든다.
  Future<String?> _computeRootKey() async {
    // 1) 원본에서 진입
    if ((widget.originalPhotoId ?? '').isNotEmpty) {
      return widget.originalPhotoId;
    }
    // 2) 재편집에서 진입: edited/{editedId} 에서 originalPhotoId를 가져온다.
    if ((widget.editedId ?? '').isNotEmpty &&
        (widget.albumId ?? '').isNotEmpty) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('albums')
            .doc(widget.albumId!)
            .collection('edited')
            .doc(widget.editedId!)
            .get();
        final d = snap.data();
        final opid = d?['originalPhotoId'] as String?;
        if (opid != null && opid.isNotEmpty) return opid; // == rootPhotoId
      } catch (_) {}
    }
    // 3) fallback: photoId(원본)로 진입했을 수 있음
    if ((widget.photoId ?? '').isNotEmpty) return widget.photoId;

    return null;
  }

  Future<void> _registerSessionOnce() async {
    if (widget.albumId == null || _uid.isEmpty) return;
    final photoUrl = widget.imagePath ?? '';
    try {
      await _svc.setEditing(
        uid: _uid,
        albumId: widget.albumId!,
        photoUrl: photoUrl,
        // [변경][root] 가능하면 루트로 넣기(서비스에서 재보정도 함)
        photoId: _targetKey,
        originalPhotoId: _targetKey,
        editedId: widget.editedId,
        userDisplayName: null,
      );
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    // [변경][root] 프레임 이후 비동기로 루트키 계산 → 구독 시작
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final rk = await _computeRootKey();
      setState(() => _targetKey = rk); // 항상 rootPhotoId
      await _prepareAndSubscribe(); // 루트 키 확보 후 실행
    });
  }

  @override
  void dispose() {
    _lmDebounce?.cancel();
    _opsSub?.cancel();
    if (widget.albumId != null && _uid.isNotEmpty) {
      _svc.endEditing(uid: _uid, albumId: widget.albumId!).catchError((_) {});
    }
    super.dispose();
  }

  // 같은 사진 편집 중인 사람이 나뿐인지 확인(마지막 편집자인지)
  Future<bool> _amILastEditor() async {
    if (widget.albumId == null || _targetKey == null) return true;
    // [변경][root] 루트 키 기준으로만 판단
    final qs = await FirebaseFirestore.instance
        .collection('albums')
        .doc(widget.albumId!)
        .collection('editing_by_user')
        .where('status', isEqualTo: 'active')
        .where('photoId', isEqualTo: _targetKey)
        .get();

    // 나 제외하고 0명이면 마지막 편집자
    final others = qs.docs
        .where((d) => ((d.data()['uid'] as String?) ?? d.id) != _uid)
        .length;
    return others == 0;
  }

  Future<void> _confirmExit() async {
    Future<void> _endSession() async {
      if (widget.albumId != null && _uid.isNotEmpty) {
        try {
          await _svc.endEditing(uid: _uid, albumId: widget.albumId!);
        } catch (_) {}
      }
    }

    // 내가 마지막 편집자인지 먼저 판단
    final last = await _amILastEditor();

    if (!_hasUnsavedChanges) {
      await _endSession();
      if (widget.albumId != null && _targetKey != null) {
        await _svc.tryCleanupOpsIfNoEditors(
          albumId: widget.albumId!,
          photoId: _targetKey!,
        );
      }
      if (mounted) Navigator.pop(context);
      return;
    }

    // 마지막 편집자가 아니면 팝업 없이 종료
    if (!last) {
      await _endSession();
      if (mounted) Navigator.pop(context, {'status': 'discard_without_prompt'});
      return;
    }

    // 마지막 편집자면 커스텀 디자인 팝업
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _ConfirmExitPopup(),
    );

    switch (result) {
      case 'save':
        await _onSave();
        break;
      case 'discard':
        await _endSession();
        if (widget.albumId != null && _targetKey != null) {
          await _svc.tryCleanupOpsIfNoEditors(
            albumId: widget.albumId!,
            photoId: _targetKey!,
          );
        }
        if (mounted) Navigator.pop(context, {'status': 'discard'});
        break;
      default:
        break;
    }
  }

  Future<void> _handleBack() async {
    await _confirmExit();
  }

  // ===================== UI =====================
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _handleBack();
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFE6EBFE),
        bottomNavigationBar: const CustomBottomNavBar(selectedIndex: 2), // ✅ 추가
        body: SafeArea(
          child: Stack(
            children: [
              // 내용
              ListView(
                padding: const EdgeInsets.only(bottom: 120), // ✅ 바텀바 높이+여유
                children: [
                  Column(
                    children: [
                      // 헤더
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
                            UserIconButton(
                              photoUrl:
                                  FirebaseAuth.instance.currentUser?.photoURL,
                              radius: 24,
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
                            GestureDetector(
                              onTap: _onTapCall,
                              child: Image.asset(
                                'assets/icons/call_off.png',
                                width: 32,
                                height: 32,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(width: 8), // 아이콘과 앨범 이름 간격
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
                      // [추가] 앨범 이름 아래 통화 아이콘

                      // **[변경]** 배지를 통째로 숨기고, 고정 높이만 유지(레이아웃 흔들림 방지)
                      if (_kShowEditorsBadge &&
                          widget.albumId != null &&
                          _targetKey != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              height: 32, // 배지 자리 고정
                              child: StreamBuilder<List<_EditorPresence>>(
                                stream: _watchEditorsForTargetRT(),
                                builder: (context, snap) {
                                  final editors =
                                      snap.data ?? const <_EditorPresence>[];
                                  if (editors.isEmpty) return const SizedBox();
                                  final first = editors.first;
                                  final others = editors.length - 1;
                                  final label = (others <= 0)
                                      ? '${first.name} 편집중'
                                      : '${first.name} 외 $others명 편집중';
                                  return _editingBadge(label);
                                },
                              ),
                            ),
                          ),
                        )
                      else
                        const SizedBox(height: 12), // **[추가]** 여백만 남겨서 화면 위치 고정
                      // 저장 버튼
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

                      // 편집 Stage
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

                      // 하단 툴바 박스
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
                      const SizedBox(height: 80),
                    ],
                  ),
                ],
              ),

              
            ],
          ),
        ),
      ),
    );
  }

  Widget _editingBadge(String label) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFFC6DCFF), Color(0xFFD2D1FF), Color(0xFFF5CFFF)],
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(1, 1)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.people_alt_rounded, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
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

  // ===== Stage/툴바 구현 =====
  Widget _buildEditableStage() {
    return LayoutBuilder(
      builder: (_, c) {
        final paintSize = Size(c.maxWidth, c.maxHeight);

        return GestureDetector(
          onTapDown: (details) {
            // ← 추가: 얼굴 탭해서 선택
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
              if (_isFaceEditMode &&
                  _faces468.isNotEmpty &&
                  _faceOverlayOn) // ← 수정: 오버레이 표시 가드 복원**
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
                      // ✅ _geoImgSize가 없으면 전체 영역을 쓰도록 fallback
                      imageContentRect: (_geoImgSize == null)
                          ? Rect.fromLTWH(
                              0,
                              0,
                              paintSize.width,
                              paintSize.height,
                            )
                          : _contentRectForCover(_geoImgSize!, paintSize),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  int? _hitTestFace(Offset pos, Size stageSize) {
    if (_faceRects.isEmpty || _geoImgSize == null) return null;

    final content = _contentRectForCover(_geoImgSize!, stageSize);
    for (int i = 0; i < _faceRects.length; i++) {
      final r = _faceRects[i];
      final rectPx = Rect.fromLTRB(
        content.left + r.left * content.width,
        content.top + r.top * content.height,
        content.left + r.right * content.width,
        content.top + r.bottom * content.height,
      ).inflate(12);
      if (rectPx.contains(pos)) return i;
    }
    return null;
  }

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
              if (mounted && !_isImageReady)
                setState(() => _isImageReady = true);
            });
            return child;
          }
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF625F8C)),
          );
        },
        errorBuilder: (_, __, ___) {
          if (mounted && _isImageReady) setState(() => _isImageReady = false);
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
          if (mounted && !_isImageReady) setState(() => _isImageReady = true);
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

  // 메인 툴바
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
                // 툴 전환 시 밝기 앵커 정리
                if (_selectedTool == 2 && i != 2) {
                  _brightnessBaseBytes = null;
                  _rxBrightnessSession = false;
                }
                if (i == 1) {
                  setState(() {
                    _isFaceEditMode = true;
                    _selectedTool = 1; // ← 아이콘 상태도 동기화(선택)
                  });
                  await _ensureFaceModelLoaded();
                  if (_faces468.isEmpty) {
                    _smokeTestLoadTask();
                    await _rerunFaceDetectOnCurrentGeometry();
                  }
                } else {
                  // 얼굴보정 이탈 → 스택 비우기 (얼굴 보정 undo만 관리)
                  _faceUndo.clear();

                  // 조정툴 진입 시 베이스 스냅샷 (지오메트리 + 얼굴보정)
                  if (i == 2 || i == 4 || i == 5) {
                    final baseForAdjust =
                        await _renderBeautyBasePng(); // ★ 얼굴보정 포함 베이스
                    _adjustBaseBytes = baseForAdjust;
                    _brightnessBaseBytes = Uint8List.fromList(
                      baseForAdjust,
                    ); // 밝기용 앵커도 동일
                    final composed = _applyGlobalAdjustments(baseForAdjust);
                    setState(() {
                      _editedBytes = composed;
                      if (i == 2)
                        _brightness = _latestBrightnessValue; // ★ 밝기 슬라이더 값 맞춤
                    });
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

        /// ⬇️ 패널 스위처
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
      _pill('초기화', () async {
        setState(() {
          _cropRectStage = null;
          _editedBytes = null; // 원본으로 복귀
          _cropNorm = null; // ✅ 파이프라인 절대상태도 원복
        });
        // ✅ 초기화 직후 현재 지오메트리 기준 사이즈 재계산
        final basePng = await _renderBaseForBeauty();
        final im = img.decodeImage(basePng);
        if (im != null) {
          setState(() {
            _geoImgSize = Size(im.width.toDouble(), im.height.toDouble());
          });
        }
        await _refreshGeoSizeFromCurrentGeometry();
        await _reapplyAdjustmentsIfActive(); // ✅ 밝기/채도/샤픈 최신 베이스로 재합성

        // (선택) 동기화를 원하면 전체영역 크롭을 브로드캐스트
        await _sendOp('crop', {'l': 0.0, 't': 0.0, 'r': 1.0, 'b': 1.0});
        _scheduleRedetect();
      }),
      _pill('맞춤', () {
        if (_lastStageSize == null) return;
        final s = _lastStageSize!;
        setState(() {
          _cropRectStage = Rect.fromLTWH(
            s.width * 0.1,
            s.height * 0.1,
            s.width * 0.8,
            s.height * 0.8,
          );
        });
      }),
      _pill('적용', _applyCrop),
    ],
  );

  // ===== 툴바 패널 =====
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
                    data: SliderTheme.of(context).copyWith(trackHeight: 4),
                    child: Slider(
                      value: _brightness,
                      min: -0.5,
                      max: 0.5,
                      divisions: 20,
                      label: _brightness.toStringAsFixed(2),
                      onChanged: (v) {
                        setState(() {
                          _brightness = v;
                          _dirty = true;
                        });
                      },
                      onChangeEnd: (_) async {
                        await _applyBrightness();
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
      final base = _adjustBaseBytes ?? await _renderBeautyBasePng(); // ★
      final composed = _applyGlobalAdjustments(base);
      setState(() => _editedBytes = composed);

      await _sendOp('saturation', {'value': _saturation});
      _dirty = true;
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
      final base = _adjustBaseBytes ?? await _renderBeautyBasePng(); // ★
      final composed = _applyGlobalAdjustments(base);
      setState(() => _editedBytes = composed);

      await _sendOp('sharpen', {'value': _sharp});
      _dirty = true;
    } finally {
      _sharpenApplying = false;
      setState(() {});
    }
  }

  Widget _rotatePanel() => Row(
    key: const ValueKey('rotate'),
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      _pill('왼쪽 90°', () async => _applyRotate(-90)),
      _pill('오른쪽 90°', () async => _applyRotate(90)),
      _pill('좌우 반전', () async => _applyFlipH()),
      _pill('상하 반전', () async => _applyFlipV()),
    ],
  );

  Future<void> _applyCrop() async {
    _faceUndo.clear();
    if (_cropRectStage == null || _lastStageSize == null) return;

    final stageSize = _lastStageSize!;
    final rStage = _cropRectStage!;

    // 1) 현재 지오메트리 이미지 픽셀 사이즈 확보
    //    (face detect를 이미 돌리셨으면 _geoImgSize가 채워져 있음)
    if (_geoImgSize == null) {
      // 안전하게 한 번 계산
      final basePng = await _renderBaseForBeauty();
      final im = img.decodeImage(basePng)!;
      _geoImgSize = Size(im.width.toDouble(), im.height.toDouble());
    }

    // 2) BoxFit.cover로 그려진 실제 이미지 영역(rect) 계산
    final content = _contentRectForCover(_geoImgSize!, stageSize);

    // 3) stage-rect -> image-normalized(0~1)로 변환
    Rect _stageToImageNorm(Rect r) {
      final nx1 = ((r.left - content.left) / content.width).clamp(0.0, 1.0);
      final ny1 = ((r.top - content.top) / content.height).clamp(0.0, 1.0);
      final nx2 = ((r.right - content.left) / content.width).clamp(0.0, 1.0);
      final ny2 = ((r.bottom - content.top) / content.height).clamp(0.0, 1.0);
      return Rect.fromLTRB(nx1, ny1, nx2, ny2);
    }

    final normRect = _stageToImageNorm(rStage);

    // 4) 로컬 미리보기 반영(지금처럼 stage 기반 crop 함수 사용 OK)
    final bytes = await _currentBytes();
    final out = ImageOps.cropFromStageRect(
      srcBytes: bytes,
      stageCropRect: rStage,
      stageSize: stageSize,
    );
    setState(() {
      _editedBytes = out;
      _cropRectStage = null;
      _dirty = true;
      _cropNorm = normRect; // ✅ 파이프라인/재렌더용은 image-normalized로 보관
    });

    _transformFacesForGeometryChange(cropNormDelta: normRect);
    await _reapplyAdjustmentsIfActive();
    await _refreshGeoSizeFromCurrentGeometry();
    _scheduleRedetect();
    // 5) 브로드캐스트도 image-normalized 값으로 전송 (상대가 정확히 재현)
    await _sendOp('crop', {
      'l': normRect.left,
      't': normRect.top,
      'r': normRect.right,
      'b': normRect.bottom,
    });
  }

  Future<void> _applyBrightness() async {
    _faceUndo.clear();
    if (_brightnessApplying) return;
    _brightnessApplying = true;
    setState(() {});

    try {
      final base = _adjustBaseBytes ?? await _renderBeautyBasePng();
      _brightnessBaseBytes = Uint8List.fromList(base);

      _latestBrightnessValue = _brightness; // 🔹 상태 먼저 갱신
      final composed = _applyGlobalAdjustments(base);

      setState(() {
        _editedBytes = composed;
        _dirty = true;
      });

      await _sendOp('brightness', {'value': _brightness});
    } finally {
      _brightnessApplying = false;
      setState(() {});
    }
  }

  Future<void> _resetToOriginal() async {
    _faceUndo.clear();
    await _loadOriginalBytes();
    setState(() {
      _editedBytes = null;
      _cropRectStage = null;
      _brightness = 0.0;
      _brightnessBaseBytes = null;
      _rxBrightnessSession = false;
      _beautyBasePng = null;
      _latestBrightnessValue = 0.0;
      _dirty = false;
      _rotDeg = 0;
      _flipHState = false;
      _flipVState = false;
      _cropNorm = null;
      _saturation = 0.0;
      _sharp = 0.0;
      _adjustBaseBytes = null;
      _faceParams.clear();
      _faces468 = [];
      _faceRects = [];
      _selectedFace = null;
      _beautyBasePng = null;
      _geoImgSize = null;
    });
  }

  Future<void> _ensureFaceModelLoaded() async {
    if (_modelLoaded) return;
    final task = await rootBundle.load('assets/mediapipe/face_landmarker.task');
    await FaceLandmarker.loadModel(task.buffer.asUint8List(), maxFaces: 5);
    _modelLoaded = true;
  }

  Future<void> _applyRotate(int deg) async {
    _faceUndo.clear();
    final bytes = await _currentBytes();
    setState(() {
      _editedBytes = ImageOps.rotate(bytes, deg);
      _dirty = true;
    });

    _rotDeg = ((_rotDeg + deg) % 360 + 360) % 360;
    if (_geoImgSize != null && (deg % 180 != 0)) {
      _geoImgSize = Size(_geoImgSize!.height, _geoImgSize!.width); // ✅
    }
    _transformFacesForGeometryChange(rotDeltaDeg: deg);
    await _reapplyAdjustmentsIfActive();
    _scheduleRedetect();
    await _sendOp('rotate', {'deg': deg});
  }

  Future<void> _applyFlipH() async {
    _faceUndo.clear();
    final bytes = await _currentBytes();
    setState(() {
      _editedBytes = ImageOps.flipHorizontal(bytes);
      _dirty = true;
    });

    _flipHState = !_flipHState;
    _transformFacesForGeometryChange(flipHDelta: true);

    // ② 그 다음 재합성(얼굴보정 포함)
    await _reapplyAdjustmentsIfActive();
    _scheduleRedetect();
    await _sendOp('flip', {'dir': 'h'});
  }

  Future<void> _applyFlipV() async {
    _faceUndo.clear();
    final bytes = await _currentBytes();
    setState(() {
      _editedBytes = ImageOps.flipVertical(bytes);
      _dirty = true;
    });

    _flipVState = !_flipVState;
    _transformFacesForGeometryChange(flipDeltaV: true);
    await _reapplyAdjustmentsIfActive();
    _scheduleRedetect();
    await _sendOp('flip', {'dir': 'v'});
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

  // 얼굴 보정 툴바 — 중복된 아이콘 제거
  Widget _buildFaceEditToolbar() {
    final canUndo = _faceUndo.isNotEmpty;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // 닫기
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

        // Undo
        _faceToolEx(
          icon: Icons.undo,
          enabled: canUndo,
          onTap: canUndo ? _undoFaceOnce : null,
        ),

        // 보정 패널
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
        ..addAll(_cloneParams(snap.params));
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

  // 얼굴 보정 패널 오픈 (밝기와 동일한 “결정적 베이스”에서 시작)
  Future<void> _openBeautyPanel() async {
    if (_selectedFace == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('얼굴을 먼저 선택하세요.')));
      return;
    }

    await _rerunFaceDetectOnCurrentGeometry();
    // 1) 결정적 베이스 PNG 확보(원본→회전→반전→크롭)
    _beautyBasePng = await _renderBaseForBeauty();

    // 2) 실제 이미지 픽셀 크기
    final imInfo = img.decodeImage(_beautyBasePng!)!;
    final Size imgSize = Size(
      imInfo.width.toDouble(),
      imInfo.height.toDouble(),
    );

    // 3) 선택 얼굴 초기값
    final init = _faceParams[_selectedFace!] ?? BeautyParams();

    // 4) 패널 오픈
    final result =
        await showModalBottomSheet<({Uint8List image, BeautyParams params})>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (_) => BeautyPanel(
            srcPng: _beautyBasePng!, // 패널 미리보기용
            faces468: _faces468,
            selectedFace: _selectedFace!,
            imageSize: imgSize,
            initialParams: init,
          ),
        );

    if (result != null && mounted) {
      // Undo 스냅샷
      final prev = await _currentBytes();
      final paramsCopy = _cloneParams(_faceParams);

      // 5) 소스 오브 트루스 업데이트 (선택 얼굴 파라미터 저장)
      _faceParams[_selectedFace!] = result.params;

      // 6) ★ 누적 재렌더: basePNG에서 모든 얼굴 파라미터로 다시 생성
      final ctrl = BeautyController();
      final cumulative = await ctrl.applyCumulative(
        srcPng: _beautyBasePng!,
        faces468: _faces468,
        imageSize: imgSize,
        paramsByFace: _faceParams,
      );

      // 7) 반영
      setState(() {
        _editedBytes = cumulative;
        _beautyParams = result.params;
        _dirty = true;
        _faceUndo.add((image: Uint8List.fromList(prev), params: paramsCopy));
      });

      // 얼굴보정 결과(cumulative)를 베이스로 고정
      _adjustBaseBytes = cumulative;
      _brightnessBaseBytes = Uint8List.fromList(cumulative);

      // 글로벌 조정이 0이 아니면 합성 재반영
      final composedAfterBeauty = _applyGlobalAdjustments(cumulative);
      setState(() {
        _editedBytes = composedAfterBeauty;
      });

      // 8) 브로드캐스트(상대 Δ 전달은 그대로 유지 — 수신 쪽도 누적 재렌더로 맞춰줄 것)
      await _sendOp('beauty', {
        'face': _selectedFace,
        'params': result.params.toMap(),
        'prev': init.toMap(),
        'at': DateTime.now().toIso8601String(),
      });
    }
  }

  void _exitFaceMode() {
    setState(() {
      _isFaceEditMode = false;
      _selectedTool = 1;
      _selectedFace = null;
      _showLm = false;
    });
    _faceUndo.clear();
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

  // 편집자 리스트 배지용 스트림
  Stream<List<_EditorPresence>> _watchEditorsForTargetRT() {
    if (widget.albumId == null || _targetKey == null) {
      return const Stream<List<_EditorPresence>>.empty();
    }
    // [변경][root] 루트 키 기준으로만 조회
    final col = FirebaseFirestore.instance
        .collection('albums')
        .doc(widget.albumId!)
        .collection('editing_by_user')
        .where('status', isEqualTo: 'active')
        .where('photoId', isEqualTo: _targetKey!)
        .orderBy('updatedAt', descending: true)
        .limit(200);

    return col.snapshots().map((qs) {
      final list = <_EditorPresence>[];
      for (final d in qs.docs) {
        final m = d.data();
        final uid = (m['uid'] as String?) ?? d.id;
        if (uid == _uid && _uid.isNotEmpty) continue;
        final rawName = (m['userDisplayName'] as String?)?.trim();
        String? name = rawName?.isNotEmpty == true ? rawName : null;
        if (name == null) {
          final short = uid.length > 4 ? uid.substring(uid.length - 4) : uid;
          name = '사용자-$short';
        }
        list.add(_EditorPresence(uid: uid, name: name));
      }
      return list;
    });
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

class _EditorPresence {
  final String uid;
  final String? name;
  _EditorPresence({required this.uid, this.name});
}

class _LmOverlayPainter extends CustomPainter {
  final List<List<Offset>> faces; // 0~1
  final List<Rect> faceRects; // 0~1
  final int? selectedFace;
  final Size paintSize;
  final bool showLm;
  final bool dimOthers;

  // ✅ 추가: BoxFit.cover로 실제 그려진 이미지 영역
  final Rect imageContentRect;

  _LmOverlayPainter({
    required this.faces,
    required this.faceRects,
    required this.selectedFace,
    required this.paintSize,
    required this.showLm,
    required this.dimOthers,
    required this.imageContentRect, // ✅
  });

  @override
  void paint(Canvas canvas, Size size) {
    final content = imageContentRect; // ✅ 공통 기준

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
          final dx = content.left + p.dx * content.width;
          final dy = content.top + p.dy * content.height;
          canvas.drawCircle(
            Offset(dx, dy),
            isSel ? 2.2 : 1.4,
            isSel ? selDot : dot,
          );
        }
      }
    }

    for (int i = 0; i < faceRects.length; i++) {
      final r = faceRects[i];
      final rectPx = Rect.fromLTRB(
        content.left + r.left * content.width,
        content.top + r.top * content.height,
        content.left + r.right * content.width,
        content.top + r.bottom * content.height,
      );
      final isSel = (i == selectedFace);
      final stroke = Paint()
        ..color = isSel ? const Color(0xFF00CFEA) : Colors.white70
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSel ? 4.0 : 2.5
        ..strokeCap = StrokeCap.round;

      final w = rectPx.width, h = rectPx.height;
      final lStart = Offset(rectPx.left + w * 0.12, rectPx.top + h * 0.22);
      final lCtrl = Offset(rectPx.left - w * 0.05, rectPx.top + h * 0.62);
      final lEnd = Offset(rectPx.left + w * 0.18, rectPx.bottom - h * 0.10);
      final pathL = Path()
        ..moveTo(lStart.dx, lStart.dy)
        ..quadraticBezierTo(lCtrl.dx, lCtrl.dy, lEnd.dx, lEnd.dy);
      canvas.drawPath(pathL, stroke);

      final rStart = Offset(rectPx.right - w * 0.12, rectPx.top + h * 0.22);
      final rCtrl = Offset(rectPx.right + w * 0.05, rectPx.top + h * 0.62);
      final rEnd = Offset(rectPx.right - w * 0.18, rectPx.bottom - h * 0.10);
      final pathR = Path()
        ..moveTo(rStart.dx, rStart.dy)
        ..quadraticBezierTo(rCtrl.dx, rCtrl.dy, rEnd.dx, rEnd.dy);
      canvas.drawPath(pathR, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _LmOverlayPainter old) =>
      old.faces != faces ||
      old.faceRects != faceRects ||
      old.selectedFace != selectedFace ||
      old.paintSize != paintSize ||
      old.showLm != showLm ||
      old.dimOthers != dimOthers ||
      old.imageContentRect != imageContentRect; // ✅
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

// ===== 얼굴보정 직렬화 유틸 =====
extension BeautyParamsX on BeautyParams {
  Map<String, dynamic> toMap() => {
    'skinTone': skinTone,
    'eyeTail': eyeTail,
    'lipSatGain': lipSatGain,
    'lipIntensity': lipIntensity,
    'hueShift': hueShift,
    'noseAmount': noseAmount,
  };
}

BeautyParams beautyParamsFromMap(Map<String, dynamic>? m) {
  if (m == null) return BeautyParams();
  return BeautyParams(
    skinTone: (m['skinTone'] as num?)?.toDouble() ?? 0.0,
    eyeTail: (m['eyeTail'] as num?)?.toDouble() ?? 0.0,
    lipSatGain: (m['lipSatGain'] as num?)?.toDouble() ?? 0.25,
    lipIntensity: (m['lipIntensity'] as num?)?.toDouble() ?? 0.6,
    hueShift: (m['hueShift'] as num?)?.toDouble() ?? 0.0,
    noseAmount: (m['noseAmount'] as num?)?.toDouble() ?? 0.0,
  );
}

enum _ActiveHandle { none, move, tl, tr, bl, br, top, right, bottom, left }
