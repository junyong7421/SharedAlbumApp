import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SharedAlbumListService {
  SharedAlbumListService._();
  static final SharedAlbumListService instance = SharedAlbumListService._();

  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  /// 현재 로그인 사용자
  User? get currentUser => _auth.currentUser;

  /// 내가 속한 공유 앨범 목록 (owner거나 memberUids에 내가 포함)
  Stream<List<SharedAlbumListItem>> watchMySharedAlbums() {
    final me = _auth.currentUser;
    if (me == null) return const Stream<List<SharedAlbumListItem>>.empty();

    final col = _fs.collection('shared_albums');
    // array-contains 필터만으로는 owner 케이스 누락될 수 있어 두 쿼리 머지
    final byMember = col.where('memberUids', arrayContains: me.uid);
    final byOwner = col.where('ownerUid', isEqualTo: me.uid);

    // 두 스트림 합치기
    return byMember.snapshots().asyncMap((mSnap) async {
      // owner 스트림을 한 번 읽어서 merge (중복 제거)
      final oSnap = await byOwner.get();
      final map = <String, SharedAlbumListItem>{};

      for (final d in mSnap.docs) {
        map[d.id] = SharedAlbumListItem.fromDoc(d.id, d.data());
      }
      for (final d in oSnap.docs) {
        map[d.id] = SharedAlbumListItem.fromDoc(d.id, d.data());
      }
      // updatedAt desc 정렬
      final list = map.values.toList()
        ..sort((a, b) {
          final ta = a.updatedAt?.millisecondsSinceEpoch ?? 0;
          final tb = b.updatedAt?.millisecondsSinceEpoch ?? 0;
          return tb.compareTo(ta);
        });
      return list;
    });
  }

  /// 앨범의 멤버 프로필들 (users/{uid} 문서를 한 번에 가져와 보여주기)
  Future<List<AlbumMember>> fetchAlbumMembers(String albumId) async {
    final doc = await _fs.collection('shared_albums').doc(albumId).get();
    if (!doc.exists) return [];

    final data = doc.data()!;
    final List<dynamic> memberUids =
        (data['memberUids'] ?? []) as List<dynamic>;
    if (memberUids.isEmpty) return [];

    // 최대 10개씩 whereIn으로 분할 조회 (파이어스토어 whereIn 10개 제한)
    final chunks = <List<String>>[];
    for (var i = 0; i < memberUids.length; i += 10) {
      chunks.add(memberUids.skip(i).take(10).map((e) => e.toString()).toList());
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
    // 원래 순서 유지할 필요 있으면 memberUids의 순서로 정렬
    members.sort(
      (a, b) => memberUids.indexOf(a.uid).compareTo(memberUids.indexOf(b.uid)),
    );
    return members;
  }

  /// 내 친구 목록 가져오기 (users/{me}/friends)
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

  /// 앨범에 멤버 추가 (친구들 중 선택)
  Future<void> addMembers(String albumId, List<String> friendUids) async {
    if (friendUids.isEmpty) return;
    final ref = _fs.collection('shared_albums').doc(albumId);
    await ref.update({
      'memberUids': FieldValue.arrayUnion(friendUids),
      'updatedAt': FieldValue.serverTimestamp(),
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
      name: (d['name'] ?? '') as String,
      ownerUid: (d['ownerUid'] ?? '') as String,
      memberUids: List<String>.from(
        (d['memberUids'] ?? const []) as List<dynamic>,
      ),
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
