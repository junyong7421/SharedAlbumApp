import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SharedAlbumListService {
  SharedAlbumListService._();
  static final SharedAlbumListService instance = SharedAlbumListService._();

  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  /// 현재 로그인 사용자
  User? get currentUser => _auth.currentUser;

  /// 내가 속한 공유 앨범 목록 (실시간)
  Stream<List<SharedAlbumListItem>> watchMySharedAlbums() {
    final me = _auth.currentUser;
    if (me == null) return const Stream<List<SharedAlbumListItem>>.empty();

    final q = _fs
        .collection('albums')
        .where('memberUids', arrayContains: me.uid)
        .orderBy('updatedAt', descending: true);

    return q.snapshots().map((snap) {
      final list = snap.docs
          .map((d) => SharedAlbumListItem.fromDoc(d.id, d.data()))
          .toList();
      return list;
    });
  }

  /// 앨범의 멤버 프로필들
  Future<List<AlbumMember>> fetchAlbumMembers(String albumId) async {
    final doc = await _fs.collection('albums').doc(albumId).get();
    if (!doc.exists) return [];

    final data = doc.data()!;
    final List<dynamic> memberUidsDyn =
        (data['memberUids'] ?? []) as List<dynamic>;
    final memberUids = memberUidsDyn.map((e) => e.toString()).toList();
    if (memberUids.isEmpty) return [];

    // whereIn 10개 제한 → 10개씩 분할
    final chunks = <List<String>>[];
    for (var i = 0; i < memberUids.length; i += 10) {
      chunks.add(memberUids.skip(i).take(10).toList());
    }

    final members = <AlbumMember>[];
    for (final c in chunks) {
      final qs = await _fs
          .collection('users')
          .where(FieldPath.documentId, whereIn: c)
          .get();
      for (final d in qs.docs) {
        final u = d.data();
        members.add(
          AlbumMember(
            uid: d.id,
            name: (u['name'] ?? '') as String,
            email: (u['email'] ?? '') as String,
            photoUrl: u['photoUrl'] as String?,
          ),
        );
      }
    }

    members.sort(
      (a, b) => memberUids.indexOf(a.uid).compareTo(memberUids.indexOf(b.uid)),
    );
    return members;
  }

  /// 내 친구 목록
  Future<List<AlbumMember>> fetchMyFriends() async {
    final me = _auth.currentUser;
    if (me == null) return [];
    final qs = await _fs
        .collection('users')
        .doc(me.uid)
        .collection('friends')
        .get();

    return qs.docs.map((d) {
      final x = d.data();
      return AlbumMember(
        uid: d.id,
        name: (x['name'] ?? '') as String,
        email: (x['email'] ?? '') as String,
        photoUrl: x['photoUrl'] as String?,
      );
    }).toList();
  }

  /// 앨범에 멤버 추가
  Future<void> addMembers(String albumId, List<String> friendUids) async {
    if (friendUids.isEmpty) return;
    final ref = _fs.collection('albums').doc(albumId);
    await ref.update({
      'memberUids': FieldValue.arrayUnion(friendUids),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // =======================================================
  //                 🔊 Voice Talk 기능
  // =======================================================

  /// (1) 보이스톡 입장
  /// - albums/{albumId}/voice/participants/{uid} 문서를 생성/갱신
  Future<void> joinVoice({
    required String albumId,
    String? uid,
    String? name,
    String? email,
    String? photoUrl,
  }) async {
    final me = _auth.currentUser;
    final myUid = uid ?? me?.uid;
    if (myUid == null) throw StateError('No signed-in user');

    // name/email/photoUrl이 없으면 users/{uid}에서 보완
    String? _name = name;
    String? _email = email;
    String? _photo = photoUrl;

    if (_name == null || _email == null || _photo == null) {
      final uDoc = await _fs.collection('users').doc(myUid).get();
      if (uDoc.exists) {
        final u = uDoc.data()!;
        _name ??= (u['name'] ?? '') as String;
        _email ??= (u['email'] ?? '') as String;
        _photo ??= u['photoUrl'] as String?;
      } else {
        _name ??= me?.displayName ?? '';
        _email ??= me?.email ?? '';
        _photo ??= me?.photoURL;
      }
    }

    final ref = _fs
        .collection('albums')
        .doc(albumId)
        .collection('voice')
        .doc('participants')
        .collection('list')
        .doc(myUid);

    // participants를 하위 컬렉션(list)로 분리한 형태
    await ref.set({
      'name': _name ?? '',
      'email': _email ?? '',
      'photoUrl': _photo,
      'joinedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// (2) 보이스톡 퇴장
  Future<void> leaveVoice({
    required String albumId,
    String? uid,
  }) async {
    final myUid = uid ?? _auth.currentUser?.uid;
    if (myUid == null) return;

    final ref = _fs
        .collection('albums')
        .doc(albumId)
        .collection('voice')
        .doc('participants')
        .collection('list')
        .doc(myUid);

    await ref.delete();
  }

  /// (3) 현재 보이스톡 접속자 실시간 구독
  /// - participants를 joinedAt 오름차순으로 정렬해 반환
  Stream<List<AlbumMember>> watchVoiceParticipants(String albumId) {
    final col = _fs
        .collection('albums')
        .doc(albumId)
        .collection('voice')
        .doc('participants')
        .collection('list')
        .orderBy('joinedAt');

    return col.snapshots().map((snap) {
      return snap.docs.map((d) {
        final x = d.data();
        return AlbumMember(
          uid: d.id,
          name: (x['name'] ?? '') as String,
          email: (x['email'] ?? '') as String,
          photoUrl: x['photoUrl'] as String?,
        );
      }).toList();
    });
  }
}

/// ===== 모델 =====

class SharedAlbumListItem {
  final String id;
  final String name;
  final String ownerUid;
  final List<String> memberUids;
  final int photoCount;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  SharedAlbumListItem({
    required this.id,
    required this.name,
    required this.ownerUid,
    required this.memberUids,
    required this.photoCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SharedAlbumListItem.fromDoc(String id, Map<String, dynamic> d) {
    return SharedAlbumListItem(
      id: id,
      name: (d['name'] ?? d['title'] ?? '') as String,
      ownerUid: (d['ownerUid'] ?? '') as String,
      memberUids: List<String>.from((d['memberUids'] ?? const []) as List),
      photoCount: (d['photoCount'] ?? 0) as int,
      createdAt: d['createdAt'] as Timestamp?,
      updatedAt: d['updatedAt'] as Timestamp?,
    );
  }

  int get memberCount => memberUids.length;
}

class AlbumMember {
  final String uid;
  final String name;
  final String email;
  final String? photoUrl;

  AlbumMember({
    required this.uid,
    required this.name,
    required this.email,
    required this.photoUrl,
  });
}
