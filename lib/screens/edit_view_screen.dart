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
  // 툴: 0=자르기, 1=얼굴보정, 2=밝기, 3=회전/반전
  int _selectedTool = 1;

  Rect? _cropRectStage;
  Size? _lastStageSize;

  // === 밝기 동기화 핵심 상태 ===
  double _brightness = 0.0;
  bool _brightnessApplying = false;

  Uint8List? _brightnessBaseBytes;
  bool _rxBrightnessSession = false;

  // [추가] OPS에서 마지막으로 본 밝기 절대값(슬라이더/이미지 통일 기준)
  double _latestBrightnessValue = 0.0; // [추가]

  final List<IconData> _toolbarIcons = const [
    Icons.crop,
    Icons.face_retouching_natural,
    Icons.brightness_6,
    Icons.rotate_90_degrees_ccw,
  ];

  final int _selectedIndex = 2;

  final _svc = SharedAlbumService.instance;
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  final GlobalKey _captureKey = GlobalKey();

  bool _isSaving = false;
  bool _isImageReady = false;
  bool _isFaceEditMode = false;

  // 실시간 키(원본 우선)
  String? _targetKey;

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
  Uint8List? _beautyBasePng;

  bool _dirty = false;
  bool get _hasUnsavedChanges => _dirty || _cropRectStage != null;

  // 실시간
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _opsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _commitSub;
  final Set<String> _appliedOpIds = {};
  Timestamp? _opsAnchor;

  // ===== 공용 유틸 =====
  Future<Uint8List> _currentBytes() async {
    if (_editedBytes != null) return _editedBytes!;
    if (_originalBytes == null) await _loadOriginalBytes();
    return _editedBytes ?? _originalBytes!;
  }

  // ===== PNG 캡처/업로드 =====
  Future<Uint8List> _exportEditedImageBytes({double pixelRatio = 2.5}) async {
    final boundary =
        _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('캡처 대상을 찾지 못했습니다.');
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw StateError('PNG 인코딩 실패');
    return byteData.buffer.asUint8List();
  }

  Future<({String url, String storagePath})> _uploadEditedPngBytes(
    Uint8List png,
  ) async {
    if (widget.albumId == null) throw StateError('albumId가 없습니다.');
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

  // ===== 저장 =====
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

      // 커밋 신호(OP) 브로드캐스트
      if (_targetKey != null) {
        await _sendOp('commit', {'by': _uid, 'at': DateTime.now().toIso8601String()});
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // 마지막 편집자면 ops 정리
      if (_targetKey != null) {
        await _svc.tryCleanupOpsIfNoEditors(
          albumId: widget.albumId!,
          photoId: _targetKey!,
        );
      }
      _appliedOpIds.clear();
      _opsAnchor = null;

      // 세션 종료
      try {
        await _svc.endEditing(uid: _uid, albumId: widget.albumId!);
      } catch (_) {}

      _dirty = false;
      if (!mounted) return;

      // [변경] 저장 후 편집화면 닫을 때, 부모로 edited 결과를 돌려줄 수도 있음(필요 시)
      Navigator.pop(context, {
        'status': 'saved',
        'editedUrl': uploaded.url,
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('저장 실패: $e')));
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
        photoId: _targetKey!, // 모든 클라 공동 키(원본 ID)
        op: {'type': type, 'data': data, 'by': _uid},
      );
    } catch (_) {}
  }

  // === 수신 OP 적용(밝기 절대값 동기화 반영) ===
  Future<void> _applyIncomingOp(Map<String, dynamic> op) async {
    final type = op['type'] as String? ?? '';
    final data = (op['data'] as Map?)?.cast<String, dynamic>() ?? const {};

    switch (type) {
      case 'commit':
        if (!mounted) return;

        // [변경] 다른 사용자가 저장하면 편집 종료 + 부모로 결과 전달
        _opsSub?.cancel();
        _commitSub?.cancel();
        try {
          if (widget.albumId != null && _uid.isNotEmpty) {
            await _svc.endEditing(uid: _uid, albumId: widget.albumId!);
          }
        } catch (_) {}
        if (mounted) {
          Navigator.pop(context, {
            'status': 'peer_saved', // [추가]
          });
        }
        return;

      case 'brightness': {
        final v = (data['value'] as num?)?.toDouble() ?? 0.0;

        // [변경] 항상 원본을 앵커로 삼고 절대값 v를 반영 → 슬라이더/이미지 통일
        if (_originalBytes == null) {
          await _loadOriginalBytes();
        }
        _brightnessBaseBytes = _originalBytes; // [변경] 수신도 원본 기준
        _latestBrightnessValue = v;            // [추가] 전역 최신값 업데이트

        setState(() => _brightness = v);       // [변경] 슬라이더 위치를 절대값으로
        final out = (_brightnessBaseBytes == null || v.abs() < 1e-6)
            ? _brightnessBaseBytes ?? await _currentBytes()
            : ImageOps.adjustBrightness(_brightnessBaseBytes!, v);
        setState(() => _editedBytes = out);
        break;
      }

      case 'crop': {
        if (_lastStageSize == null) return;
        final l = (data['l'] as num).toDouble();
        final t = (data['t'] as num).toDouble();
        final r = (data['r'] as num).toDouble();
        final b = (data['b'] as num).toDouble();
        final stageRect = Rect.fromLTRB(
          l * _lastStageSize!.width,
          t * _lastStageSize!.height,
          r * _lastStageSize!.width,
          b * _lastStageSize!.height,
        );
        final bytes = await _currentBytes();
        final out = ImageOps.cropFromStageRect(
          srcBytes: bytes,
          stageCropRect: stageRect,
          stageSize: _lastStageSize!,
        );
        setState(() => _editedBytes = out);
        break;
      }

      case 'rotate': {
        final deg = (data['deg'] as num?)?.toInt() ?? 0;
        final bytesR = await _currentBytes();
        setState(() => _editedBytes = ImageOps.rotate(bytesR, deg));
        break;
      }

      case 'flip': {
        final dir = (data['dir'] as String?) ?? 'h'; // 'h' | 'v'
        final bytesF = await _currentBytes();
        setState(() {
          _editedBytes = (dir == 'v')
              ? ImageOps.flipVertical(bytesF)
              : ImageOps.flipHorizontal(bytesF);
        });
        break;
      }
    }
    _dirty = true;
  }

  // ===== 백필 + 실시간 구독 + 커밋 감시 =====
  Future<void> _prepareAndSubscribe() async {
    if (widget.albumId == null || _targetKey == null) return;

    try {
      await Future.delayed(const Duration(milliseconds: 120));
      final opsCol = FirebaseFirestore.instance
          .collection('albums')
          .doc(widget.albumId!)
          .collection('ops');

      // 1) 백필
      final backfill = await opsCol
          .where('photoId', isEqualTo: _targetKey)
          .orderBy('createdAt', descending: false)
          .limit(500)
          .get();

      for (final d in backfill.docs) {
        final data = d.data();
        final op = (data['op'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{
              'type': data['type'],
              'data': data['data'],
              'by': data['by'],
            };
        _appliedOpIds.add(d.id);
        await _applyIncomingOp(op);

        final ts = data['createdAt'];
        if (ts is Timestamp) {
          _opsAnchor =
              (_opsAnchor == null || ts.compareTo(_opsAnchor!) > 0) ? ts : _opsAnchor;
        }
      }

      // 2) 실시간
      Query<Map<String, dynamic>> q = opsCol
          .where('photoId', isEqualTo: _targetKey)
          .orderBy('createdAt', descending: false);
      if (_opsAnchor != null) {
        q = q.startAfter([_opsAnchor]);
      }

      _opsSub?.cancel();
      _opsSub = q.snapshots().listen(_onOpsSnapshot);

      // 3) 커밋 감시 (edited)
      _watchCommit();

      // 4) 프레임 이후 세션 등록
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _registerSessionOnce();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('초기 준비 실패: $e')));
    }
  }

  void _onOpsSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    for (final ch in snap.docChanges) {
      if (ch.type != DocumentChangeType.added) continue;
      final m = ch.doc.data();
      if (m == null) continue;

      final opId = ch.doc.id;
      if (_appliedOpIds.contains(opId)) continue;

      // 내가 보낸 건 적용 생략(기록만)
      if (_uid.isNotEmpty && (m['by'] as String?) == _uid) {
        _appliedOpIds.add(opId);
        continue;
      }

      final op = (m['op'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{
            'type': m['type'],
            'data': m['data'],
            'by': m['by'],
          };

      _appliedOpIds.add(opId);
      _applyIncomingOp(op);

      final ts = m['createdAt'];
      if (ts is Timestamp) {
        _opsAnchor =
            (_opsAnchor == null || ts.compareTo(_opsAnchor!) > 0) ? ts : _opsAnchor;
      }
    }
  }

  // ===== 커밋 감시: edited 컬렉션 기준 =====
  void _watchCommit() {
    if (widget.albumId == null || _targetKey == null) return;

    final q = FirebaseFirestore.instance
        .collection('albums')
        .doc(widget.albumId!)
        .collection('edited')
        .where('originalPhotoId', isEqualTo: _targetKey)
        .orderBy('updatedAt', descending: true)
        .limit(1);

    _commitSub?.cancel();
    _commitSub = q.snapshots().listen((qs) async {
      if (qs.docs.isEmpty) return;
      final doc = qs.docs.first;
      final data = doc.data();
      final by = (data['editorUid'] ?? data['editedBy'] ?? data['by']) as String?;
      if (by != null && by != _uid) {
        // [변경] 누군가 저장하면 내 편집 화면 닫고 부모에 editedId/url 전달
        if (!mounted) return;
        try {
          if (widget.albumId != null && _uid.isNotEmpty) {
            await _svc.endEditing(uid: _uid, albumId: widget.albumId!);
          }
        } catch (_) {}
        if (!mounted) return;
        Navigator.pop(context, {
          'status': 'peer_saved',
          'editedId': doc.id,           // [추가]
          'editedUrl': data['url'],     // [추가]
        });
      }
    });
  }

  Future<void> _registerSessionOnce() async {
    if (widget.albumId == null || _uid.isEmpty) return;
    final photoUrl = widget.imagePath ?? '';
    final photoId = widget.photoId ?? widget.originalPhotoId ?? widget.editedId;
    try {
      await _svc.setEditing(
        uid: _uid,
        albumId: widget.albumId!,
        photoUrl: photoUrl,
        photoId: photoId,
        originalPhotoId: widget.originalPhotoId,
        editedId: widget.editedId,
        userDisplayName: null,
      );
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _targetKey = widget.originalPhotoId ?? widget.photoId ?? widget.editedId;
    _prepareAndSubscribe();
  }

  @override
  void dispose() {
    _opsSub?.cancel();
    _commitSub?.cancel();
    if (widget.albumId != null && _uid.isNotEmpty) {
      _svc.endEditing(uid: _uid, albumId: widget.albumId!).catchError((_) {});
    }
    super.dispose();
  }

  // [추가] 같은 사진 편집 중인 사람이 나뿐인지 확인(마지막 편집자인지)
  Future<bool> _amILastEditor() async { // [추가]
    if (widget.albumId == null || _targetKey == null) return true;
    final qs = await FirebaseFirestore.instance
        .collection('albums')
        .doc(widget.albumId!)
        .collection('editing_by_user')
        .where('status', isEqualTo: 'active')
        .get();

    int count = 0;
    for (final d in qs.docs) {
      final m = d.data();
      final match =
          (m['originalPhotoId'] == _targetKey) ||
          (m['photoId'] == _targetKey) ||
          (m['editedId'] == _targetKey);
      if (match) count++;
    }
    // count == 0(이상), 1(나 혼자) → 마지막 편집자 취급
    return count <= 1;
  }

  Future<void> _confirmExit() async {
    Future<void> _endSession() async {
      if (widget.albumId != null && _uid.isNotEmpty) {
        try {
          await _svc.endEditing(uid: _uid, albumId: widget.albumId!);
        } catch (_) {}
      }
    }

    // [변경] 내가 마지막 편집자인지 먼저 판단
    final last = await _amILastEditor(); // [추가]

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

    // [변경] 마지막 편집자가 아니면 팝업 없이 그냥 종료
    if (!last) { // [추가]
      await _endSession();
      if (mounted) Navigator.pop(context, {'status': 'discard_without_prompt'});
      return;
    }

    // 마지막 편집자면 기존 팝업
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('편집이 저장되지 않았습니다'),
        content: const Text('저장하지 않고 나가시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('저장 안 함'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('저장'),
          ),
        ],
      ),
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
        body: SafeArea(
          child: Stack(
            children: [
              // 내용
              ListView(
                padding: EdgeInsets.zero,
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

                      // 실시간 “편집중” 배지
                      if (widget.albumId != null && _targetKey != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: StreamBuilder<List<_EditorPresence>>(
                              stream: _watchEditorsForTargetRT(),
                              builder: (context, snap) {
                                final editors =
                                    snap.data ?? const <_EditorPresence>[];
                                if (editors.isEmpty) {
                                  return const SizedBox(height: 0);
                                }
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
                fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
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
                colors: [Color(0xFFC6DCFF), Color(0xFFD2D1FF), Color(0xFFF5CFFF)],
              ),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(1, 1)),
              ],
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.imagePath != null) _buildSinglePreview(widget.imagePath!),
              if (_selectedTool == 0)
                Positioned.fill(
                  child: CropOverlay(
                    initRect: _cropRectStage,
                    onChanged: (r) => _cropRectStage = r,
                    onStageSize: (s) => _lastStageSize = s,
                  ),
                ),
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
            ],
          ),
        );
      },
    );
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
              if (mounted && !_isImageReady) setState(() => _isImageReady = true);
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
            child: Text('이미지를 불러오지 못했습니다',
                style: TextStyle(color: Color(0xFF625F8C))),
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
                // 툴 전환 시 밝기 앵커를 정리
                if (_selectedTool == 2 && i != 2) {
                  _brightnessBaseBytes = null;
                  _rxBrightnessSession = false;
                }
                if (i == 1) {
                  setState(() => _isFaceEditMode = true);
                  if (_faces468.isEmpty) {
                    _smokeTestLoadTask();
                    _runFaceDetect();
                  }
                } else {
                  if (i == 2) {
                    // [변경] 밝기 모드 진입 시: 항상 원본을 앵커로, 슬라이더는 최신 절대값으로
                    if (_originalBytes == null) {
                      await _loadOriginalBytes();
                    }
                    _brightnessBaseBytes = _originalBytes; // [변경]
                    _rxBrightnessSession = false;
                    setState(() {
                      _brightness = _latestBrightnessValue; // [추가]
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

  Widget _cropPanel() => Row(
        key: const ValueKey('crop'),
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _pill('초기화', () async {
            await _resetToOriginal();
          }),
          _pill('맞춤', () {
            if (_lastStageSize == null) return;
            final s = _lastStageSize!;
            setState(() => _cropRectStage =
                Rect.fromLTWH(s.width * 0.1, s.height * 0.1, s.width * 0.8, s.height * 0.8));
          }),
          _pill('적용', () async {
            await _applyCrop();
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
    if (_cropRectStage == null || _lastStageSize == null) return;
    final s = _lastStageSize!;
    final r = _cropRectStage!;
    final norm = {'l': r.left / s.width, 't': r.top / s.height,
                  'r': r.right / s.width, 'b': r.bottom / s.height};

    final bytes = await _currentBytes();
    final out = ImageOps.cropFromStageRect(
      srcBytes: bytes, stageCropRect: r, stageSize: s);
    setState(() {
      _editedBytes = out;
      _cropRectStage = null;
      _dirty = true;
    });

    await _sendOp('crop', norm);
  }

  Future<void> _applyBrightness() async {
    if (_brightnessApplying) return;
    _brightnessApplying = true;
    setState(() {});

    try {
      // [변경] 발신자도 항상 원본(anchor) 기준으로 절대값 적용
      if (_originalBytes == null) {
        await _loadOriginalBytes();
      }
      _brightnessBaseBytes = _originalBytes;                 // [변경]
      _latestBrightnessValue = _brightness;                  // [추가] 글로벌 최신값
      final base = _brightnessBaseBytes!;
      final out = (_brightness.abs() < 1e-6)
          ? base
          : ImageOps.adjustBrightness(base, _brightness);
      setState(() => _editedBytes = out);
      _dirty = true;

      await _sendOp('brightness', {'value': _brightness});
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
      _rxBrightnessSession = false;
      _beautyBasePng = null;
      _latestBrightnessValue = 0.0; // [추가]
      _dirty = false;
    });
  }

  Future<void> _applyRotate(int deg) async {
    final bytes = await _currentBytes();
    setState(() {
      _editedBytes = ImageOps.rotate(bytes, deg);
      _dirty = true;
    });
    await _sendOp('rotate', {'deg': deg});
  }

  Future<void> _applyFlipH() async {
    final bytes = await _currentBytes();
    setState(() {
      _editedBytes = ImageOps.flipHorizontal(bytes);
      _dirty = true;
    });
    await _sendOp('flip', {'dir': 'h'});
  }

  Future<void> _applyFlipV() async {
    final bytes = await _currentBytes();
    setState(() {
      _editedBytes = ImageOps.flipVertical(bytes);
      _dirty = true;
    });
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

  // 얼굴보정 툴바(기존 그대로)
  Widget _buildFaceEditToolbar() { /* 기존 구현 유지 */ return Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      _faceTool(icon: Icons.close, onTap: () {
        setState(() {
          _isFaceEditMode = false;
          _faces468.clear();
          _faceRects.clear();
          _selectedFace = null;
        });
      }),
      _faceTool(icon: Icons.center_focus_strong, onTap: () {
        if (_faceRects.isEmpty) return;
        int largest = 0; double best = -1;
        for (int i = 0; i < _faceRects.length; i++) {
          final r = _faceRects[i]; final area = (r.width * r.height);
          if (area > best) { best = area; largest = i; }
        }
        setState(() => _selectedFace = largest);
      }),
      _faceTool(icon: _showLm ? Icons.visibility : Icons.visibility_off,
          onTap: () => setState(() => _showLm = !_showLm)),
      _faceTool(icon: Icons.brush, onTap: _openBeautyPanel),
    ],
  ); }

  Widget _faceTool({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4),
        child: Icon(icon, size: 22, color: Colors.black87),
      ),
    );
  }

  Future<void> _openBeautyPanel() async { /* 기존 구현 유지 */ 
    if (_selectedFace == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('얼굴을 먼저 선택하세요.')));
      return;
    }
    _beautyBasePng ??= await _exportEditedImageBytes(pixelRatio: 1.0);
    final Size stageSize = _captureKey.currentContext!.size!;
    final result = await showModalBottomSheet<({Uint8List image, BeautyParams params})>(
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
        _dirty = true;
      });
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

  // 편집자 리스트 배지용 스트림 (기존 로직 유지)
  Stream<List<_EditorPresence>> _watchEditorsForTargetRT() {
    if (widget.albumId == null || _targetKey == null) {
      return const Stream<List<_EditorPresence>>.empty();
    }
    final col = FirebaseFirestore.instance
        .collection('albums')
        .doc(widget.albumId!)
        .collection('editing_by_user')
        .where('status', isEqualTo: 'active')
        .orderBy('updatedAt', descending: true)
        .limit(200);

    return col.snapshots().map((qs) {
      final key = _targetKey!;
      final list = <_EditorPresence>[];
      for (final d in qs.docs) {
        final m = d.data();
        final match =
            (m['originalPhotoId'] == key) ||
            (m['photoId'] == key) ||
            (m['editedId'] == key);
        if (!match) continue;
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

  // 얼굴 검출(기존 유지)
  Future<void> _smokeTestLoadTask() async { /* 그대로 */ }
  Future<void> _runFaceDetect() async { /* 그대로 */ }
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
          canvas.drawCircle(Offset(dx, dy), isSel ? 2.2 : 1.4, isSel ? selDot : dot);
        }
      }
    }
    for (int i = 0; i < faceRects.length; i++) {
      final r = faceRects[i];
      final rectPx = Rect.fromLTRB(
        r.left * paintSize.width,
        r.top * paintSize.height,
        r.right * paintSize.width,
        r.bottom * paintSize.height,
      );
      final isSel = (i == selectedFace);
      final stroke = Paint()
        ..color = isSel ? const Color(0xFF00CFEA) : Colors.white70
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSel ? 4.0 : 2.5
        ..strokeCap = StrokeCap.round;

      final w = rectPx.width, h = rectPx.height;
      final lStart = Offset(rectPx.left + w * 0.12, rectPx.top + h * 0.22);
      final lCtrl  = Offset(rectPx.left - w * 0.05, rectPx.top + h * 0.62);
      final lEnd   = Offset(rectPx.left + w * 0.18, rectPx.bottom - h * 0.10);
      final pathL = Path()..moveTo(lStart.dx, lStart.dy)
        ..quadraticBezierTo(lCtrl.dx, lCtrl.dy, lEnd.dx, lEnd.dy);
      canvas.drawPath(pathL, stroke);

      final rStart = Offset(rectPx.right - w * 0.12, rectPx.top + h * 0.22);
      final rCtrl  = Offset(rectPx.right + w * 0.05, rectPx.top + h * 0.62);
      final rEnd   = Offset(rectPx.right - w * 0.18, rectPx.bottom - h * 0.10);
      final pathR = Path()..moveTo(rStart.dx, rStart.dy)
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
      old.dimOthers != dimOthers;
}