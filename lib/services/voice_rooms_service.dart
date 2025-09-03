import 'package:cloud_firestore/cloud_firestore.dart';

/// 보이스 방 = 앨범을 그대로 사용
class VoiceRoomInfo {
  final String id;
  final String name;
  final List<String> memberUids;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  VoiceRoomInfo({
    required this.id,
    required this.name,
    required this.memberUids,
    this.createdAt,
    this.updatedAt,
  });

  int get memberCount => memberUids.length;

  factory VoiceRoomInfo.fromAlbumDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return VoiceRoomInfo(
      id: doc.id,
      name: (d['name'] ?? d['title'] ?? '') as String, // title/name 둘 다 대응
      memberUids: List<String>.from((d['memberUids'] ?? const []) as List),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class VoiceRoomsService {
  VoiceRoomsService._();
  static final VoiceRoomsService instance = VoiceRoomsService._();

  final _fs = FirebaseFirestore.instance;

  /// 내가 속한 앨범(=보이스방 후보) 가져오기
  Future<List<VoiceRoomInfo>> fetchMyVoiceRooms(String uid) async {
    // albums 컬렉션에서 조회
    final qs = await _fs
        .collection('albums')
        .where('memberUids', arrayContains: uid)
        .orderBy('updatedAt', descending: true) // 정렬 기준: updatedAt
        .get();

    return qs.docs.map((d) => VoiceRoomInfo.fromAlbumDoc(d)).toList();
  }
}
