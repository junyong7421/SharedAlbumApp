import 'package:flutter/material.dart';
import '../services/shared_album_list_service.dart';
import './voice_call_popup.dart';

/// 앱 전역에서 오버레이를 띄우기 위한 루트 네비게이터 키
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// 전역 컨트롤러 (원하면 provider로 교체 가능)
final VoiceCallOverlayController voiceOverlay = VoiceCallOverlayController();

class VoiceCallOverlayController extends ChangeNotifier {
  OverlayEntry? _entry;
  Offset _offset = const Offset(24, 160); // 최초 위치

  String? _albumId;
  String? _albumName;

  bool get isShown => _entry != null;
  String? get currentAlbumId => _albumId;

  /// 오버레이 보이기 (이미 보이면 무시)
  void show({required String albumId, required String albumName}) {
    _albumId = albumId;
    _albumName = albumName;

    if (_entry != null) return;
    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _entry = OverlayEntry(builder: (context) {
      return _DraggableCallButton(
        offset: _offset,
        onDrag: (delta) {
          _offset = Offset(_offset.dx + delta.dx, _offset.dy + delta.dy);
          _entry?.markNeedsBuild();
        },
        onTap: _handleTap,
      );
    });

    overlay.insert(_entry!);
    notifyListeners();
  }

  /// 오버레이 숨기기
  void hide() {
    _entry?.remove();
    _entry = null;
    _albumId = null;
    _albumName = null;
    notifyListeners();
  }

  /// 아이콘 탭 → 현재 접속자 팝업 (여기서 종료 시 leave + hide)
  Future<void> _handleTap() async {
    final id = _albumId;
    final name = _albumName;
    final ctx = rootNavigatorKey.currentContext;
    if (id == null || name == null || ctx == null) return;

    final svc = SharedAlbumListService.instance;

    final stream = svc.watchVoiceParticipants(id).map(
      (list) => list
          .map((m) => MemberLite(
                uid: m.uid,
                name: m.name.isNotEmpty ? m.name : m.email,
              ))
          .toList(),
    );
    final initial = await stream.first;

    await showVoiceNowPopup(
      ctx,
      albumName: name,
      initialParticipants: initial,
      participantsStream: stream,
      onLeave: () async {
        await svc.leaveVoice(albumId: id);
        hide();
      },
    );
  }
}

class _DraggableCallButton extends StatelessWidget {
  final Offset offset;
  final ValueChanged<Offset> onDrag; // delta 전달
  final VoidCallback onTap;

  const _DraggableCallButton({
    required this.offset,
    required this.onDrag,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const btn = 56.0;

    // 화면 밖으로 못나가게 살짝 여백 두고 클램프
    final left = offset.dx.clamp(8.0, size.width - btn - 8.0);
    final top =
        offset.dy.clamp(kToolbarHeight, size.height - btn - 96.0); // 하단 네비 여유

    return Positioned(
      left: left,
      top: top,
      child: _FloatingButton(onDrag: onDrag, onTap: onTap),
    );
  }
}

class _FloatingButton extends StatefulWidget {
  final ValueChanged<Offset> onDrag;
  final VoidCallback onTap;

  const _FloatingButton({required this.onDrag, required this.onTap});

  @override
  State<_FloatingButton> createState() => _FloatingButtonState();
}

class _FloatingButtonState extends State<_FloatingButton> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (d) => widget.onDrag(d.delta),
      onTap: widget.onTap,
      child: SafeArea(
        child: Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/icons/call_on.png', // ✅ 접속 중 아이콘
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}
