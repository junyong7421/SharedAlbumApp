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
  final int _selectedIndex = 2;
  int _selectedTool = 0;

  final _svc = SharedAlbumService.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  String get _name => FirebaseAuth.instance.currentUser?.displayName ?? '사용자';

  final GlobalKey _captureKey = GlobalKey();

  final List<IconData> _toolbarIcons = const [
    Icons.mouse,
    Icons.grid_on,
    Icons.face_retouching_natural,
    Icons.visibility,
    Icons.text_fields,
    Icons.architecture,
    Icons.widgets,
  ];

  bool _isSaving = false;
  bool _isImageReady = false;
  bool _isFaceEditMode = false;

  Timer? _presenceHbTimer;   // presence heartbeat
  Timer? _editHbTimer;       // editing_by_user heartbeat
  Timer? _previewDebounce;
  String? _presenceKey;

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
      final png = await _exportEditedImageBytes(pixelRatio: 2.5);
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

  Widget _buildEditableStage() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.imagePath != null) _buildSinglePreview(widget.imagePath!),
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
    );
  }

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
                _schedulePreviewUpdate();
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
            _schedulePreviewUpdate();
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

  Widget _buildMainToolbar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(_toolbarIcons.length, (index) {
        final isSelected = _selectedTool == index;
        return GestureDetector(
          onTap: () {
            if (index == 2) {
              setState(() => _isFaceEditMode = true);
            } else {
              setState(() => _selectedTool = index);
            }
            _schedulePreviewUpdate();
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

  Widget _buildFaceEditToolbar() {
    final faceTools = <IconData>[
      Icons.refresh,
      Icons.crop_square,
      Icons.blur_on,
      Icons.remove_red_eye,
      Icons.brush,
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        GestureDetector(
          onTap: () {
            setState(() => _isFaceEditMode = false);
            _schedulePreviewUpdate();
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6.0),
            child: Icon(Icons.close, color: Colors.redAccent, size: 22),
          ),
        ),
        ...faceTools.map(
          (icon) => GestureDetector(
            onTap: _schedulePreviewUpdate,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6.0),
              child: Icon(icon, color: Colors.black87, size: 22),
            ),
          ),
        ),
      ],
    );
  }
}