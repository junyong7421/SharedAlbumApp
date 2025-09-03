import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class RtcSignaling {
  final _fs = FirebaseFirestore.instance;
  RTCPeerConnection? pc;
  MediaStream? localStream;
  MediaStream? remoteStream;

  Future<void> init() async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };
    pc = await createPeerConnection(config);
    remoteStream = await createLocalMediaStream('remote');

    pc!.onTrack = (event) {
      if (event.track.kind == 'audio') {
        remoteStream?.addTrack(event.track);
      }
    };
  }

  Future<void> getMic() async {
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    for (var track in localStream!.getTracks()) {
      pc?.addTrack(track, localStream!);
    }
  }

  Future<void> caller(String roomId) async {
    final roomRef = _fs.collection('voiceRooms').doc(roomId);
    final offerCandidates = roomRef.collection('callerCandidates');
    final answerCandidates = roomRef.collection('answerCandidates');

    pc!.onIceCandidate = (c) {
      if (c.candidate != null) {
        offerCandidates.add({
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      }
    };

    final offer = await pc!.createOffer();
    await pc!.setLocalDescription(offer);

    await roomRef.set({
      'offer': {'type': offer.type, 'sdp': offer.sdp},
    }, SetOptions(merge: true));

    // answer 수신
    roomRef.snapshots().listen((snap) async {
      final data = snap.data();
      if (data == null) return;
      if (pc!.remoteDescription != null) return;
      final answer = data['answer'];
      if (answer != null) {
        final desc = RTCSessionDescription(answer['sdp'], answer['type']);
        await pc!.setRemoteDescription(desc);
      }
    });

    // 상대방 ICE 수신
    answerCandidates.snapshots().listen((qs) {
      for (final d in qs.docChanges) {
        if (d.type == DocumentChangeType.added) {
          final c = d.doc.data()!;
          pc!.addCandidate(RTCIceCandidate(
            c['candidate'],
            c['sdpMid'],
            c['sdpMLineIndex'],
          ));
        }
      }
    });
  }

  Future<void> callee(String roomId) async {
    final roomRef = _fs.collection('voiceRooms').doc(roomId);
    final offerCandidates = roomRef.collection('callerCandidates');
    final answerCandidates = roomRef.collection('answerCandidates');

    pc!.onIceCandidate = (c) {
      if (c.candidate != null) {
        answerCandidates.add({
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      }
    };

    final roomSnap = await roomRef.get();
    final data = roomSnap.data();
    if (data == null || data['offer'] == null) {
      throw '아직 방에 offer가 없습니다(발신자가 먼저 들어와야 함).';
    }

    final offer = data['offer'];
    await pc!.setRemoteDescription(
      RTCSessionDescription(offer['sdp'], offer['type']),
    );

    final answer = await pc!.createAnswer();
    await pc!.setLocalDescription(answer);

    await roomRef.set({
      'answer': {'type': answer.type, 'sdp': answer.sdp},
    }, SetOptions(merge: true));

    // 발신자 ICE 수신
    offerCandidates.snapshots().listen((qs) {
      for (final d in qs.docChanges) {
        if (d.type == DocumentChangeType.added) {
          final c = d.doc.data()!;
          pc!.addCandidate(RTCIceCandidate(
            c['candidate'],
            c['sdpMid'],
            c['sdpMLineIndex'],
          ));
        }
      }
    });
  }

  Future<void> dispose() async {
    await localStream?.dispose();
    await remoteStream?.dispose();
    await pc?.close();
  }
}
