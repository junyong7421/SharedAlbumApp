import 'dart:async';
import 'dart:developer' as dev;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:flutter/foundation.dart' show VoidCallback;

class VoiceLivekitService {
  VoiceLivekitService._();
  static final instance = VoiceLivekitService._();

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;

  // 기본 룸/참가자 이벤트
  VoidCallback? _offReconnecting;
  VoidCallback? _offReconnected;
  VoidCallback? _offDisconnected;
  VoidCallback? _offPartJoined;
  VoidCallback? _offPartLeft;
  VoidCallback? _offActiveSpeakers;

  // ✅ 필수: 퍼블리시/구독만 남김 (버전 독립)
  VoidCallback? _offLocalTrackPublished;
  VoidCallback? _offTrackSubscribed;

  final _participantsCtrl =
      StreamController<List<lk.RemoteParticipant>>.broadcast();
  Stream<List<lk.RemoteParticipant>> get participantsStream =>
      _participantsCtrl.stream;

  String? _currentRoomName;
  bool get connected => _room?.connectionState == lk.ConnectionState.connected;
  String? get currentRoomName => _currentRoomName;

  bool _joining = false;

  void _log(String m) => dev.log(m, name: 'VoiceLK');

  // ───────────────── Token from Firebase Functions ─────────────────
  Future<Map<String, dynamic>> _fetchToken(String room, String name) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Not signed in');
    }
    final idToken = await user.getIdToken(true);

    final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('createLivekitToken');

    try {
      final res = await fn.call({'room': room, 'name': name, 'idToken': idToken});
      final data = Map<String, dynamic>.from(res.data as Map);
      final url = data['url'] as String;
      final token = data['token'] as String;
      _log('token ok: url=$url tokenLen=${token.length}');
      return data;
    } on FirebaseFunctionsException catch (e) {
      _log('createLivekitToken FFE: code=${e.code} msg=${e.message}');
      rethrow;
    } catch (e, st) {
      _log('createLivekitToken error: $e\n$st');
      rethrow;
    }
  }

  // ───────────────── Join / Leave ─────────────────
  Future<void> join({
    required String roomName,
    required String displayName,
  }) async {
    if (_joining) {
      _log('join skipped: already joining...');
      return;
    }
    if (connected) {
      _log('join skipped: already in $currentRoomName');
      return;
    }

    _joining = true;
    final rn = roomName.trim();
    _log('join start: room=$rn name=$displayName');
    _log('try join: room=$rn display=$displayName uid=${FirebaseAuth.instance.currentUser?.uid}');

    try {
      final data = await _fetchToken(rn, displayName);
      final url = data['url'] as String;
      final token = data['token'] as String;

      final room = lk.Room(
        roomOptions: const lk.RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioCaptureOptions: lk.AudioCaptureOptions(
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
          ),
        ),
      );

      _disposeListener();
      final listener = room.createListener();
      _listener = listener;

      _offReconnecting = listener.on<lk.RoomReconnectingEvent>((_) {
        _log('RoomReconnectingEvent');
      });
      _offReconnected = listener.on<lk.RoomReconnectedEvent>((_) {
        _log('RoomReconnectedEvent');
      });
      _offDisconnected = listener.on<lk.RoomDisconnectedEvent>((e) {
        final reason = (e.reason?.toString() ?? 'unknown');
        _log('RoomDisconnectedEvent reason=$reason');
        _participantsCtrl.add(const []);
      });

      _offPartJoined = listener.on<lk.ParticipantConnectedEvent>((e) {
        _log('ParticipantConnected: ${e.participant.identity}');
        _emitParticipants(room);
      });
      _offPartLeft = listener.on<lk.ParticipantDisconnectedEvent>((e) {
        _log('ParticipantDisconnected: ${e.participant.identity}');
        _emitParticipants(room);
      });
      _offActiveSpeakers = listener.on<lk.ActiveSpeakersChangedEvent>((_) {
        _emitParticipants(room);
      });

      // ✅ 퍼블리시 로그
      _offLocalTrackPublished = listener.on<lk.LocalTrackPublishedEvent>((e) {
        final kindStr = e.publication.track?.kind.toString() ?? 'unknown';
        final sid = e.publication.sid ?? 'null';
        _log('LocalTrackPublished kind=$kindStr sid=$sid');
      });

      // ✅ 구독 로그 (오디오 판별은 타입 체크로)
      _offTrackSubscribed = listener.on<lk.TrackSubscribedEvent>((e) async {
        final who = e.participant?.identity ?? 'unknown';
        final track = e.track;
        final isAudio = track is lk.RemoteAudioTrack;
        _log('TrackSubscribed from=$who isAudio=$isAudio runtimeType=${track.runtimeType}');
        if (isAudio) {
          await Helper.setSpeakerphoneOn(true);
        }
      });

      await room.connect(url, token);
      _log('connected → enable microphone');
      final micOk = await room.localParticipant?.setMicrophoneEnabled(true);
      _log('mic enable result: $micOk');
      await Helper.setSpeakerphoneOn(true);

      _room = room;
      _currentRoomName = rn;
      _emitParticipants(room);
      _log('join completed');
    } finally {
      _joining = false;
    }
  }

  Future<void> leave() async {
    _log('leave start');
    _clearEventOffs();
    _disposeListener();

    try {
      await _room?.disconnect();
    } catch (e) {
      _log('disconnect error: $e');
    } finally {
      _room = null;
      _currentRoomName = null;
      _participantsCtrl.add(const []);
      _log('leave done');
    }
  }

  // ───────────────── Controls ─────────────────
  Future<void> setMuted(bool muted) async {
    _log('setMuted: $muted');
    await _room?.localParticipant?.setMicrophoneEnabled(!muted);
  }

  Future<void> setSpeaker(bool on) async {
    _log('setSpeaker: $on');
    await Helper.setSpeakerphoneOn(on);
  }

  // ───────────────── Participants emit ─────────────────
  void _emitParticipants(lk.Room room) {
    final remotes = room.remoteParticipants.values.toList();
    remotes.sort((a, b) => (a.isSpeaking ? 0 : 1).compareTo(b.isSpeaking ? 0 : 1));
    _participantsCtrl.add(remotes);
    _log('participants: ${remotes.map((p) => "${p.identity}${p.isSpeaking ? "*" : ""}").join(", ")}');
  }

  // ───────────────── Internals ─────────────────
  void _clearEventOffs() {
    _offReconnecting?.call();
    _offReconnected?.call();
    _offDisconnected?.call();
    _offPartJoined?.call();
    _offPartLeft?.call();
    _offActiveSpeakers?.call();
    _offLocalTrackPublished?.call();
    _offTrackSubscribed?.call();

    _offReconnecting = _offReconnected = _offDisconnected =
        _offPartJoined = _offPartLeft = _offActiveSpeakers = null;
    _offLocalTrackPublished = null;
    _offTrackSubscribed = null;
  }

  void _disposeListener() {
    try { _listener?.dispose(); } catch (_) {}
    _listener = null;
  }
}
