import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FriendManageService {
  FriendManageService._();
  static final FriendManageService instance = FriendManageService._();

  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  /// 내 친구 목록 실시간 구독 (현재 로그인 사용자 기준)
  Stream<List<FriendUser>> watchFriends() {
    final me = _auth.currentUser;
    if (me == null) {
      // 로그인 전이면 빈 스트림
      return const Stream<List<FriendUser>>.empty();
    }
    final col = _fs
        .collection('users')
        .doc(me.uid)
        .collection('friends')
        .orderBy('createdAt', descending: true);

    return col.snapshots().map((qs) {
      return qs.docs.map((d) => FriendUser.fromDoc(d.id, d.data())).toList();
    });
  }

  /// 이메일로 친구 추가(양방향) - 현재 로그인 사용자 기준
  Future<AddFriendResult> addFriendByEmail(String emailRaw) async {
    final me = _auth.currentUser;
    if (me == null) return AddFriendResult.fail('로그인이 필요합니다.');

    final email = emailRaw.trim().toLowerCase();
    if (email.isEmpty) return AddFriendResult.fail('이메일을 입력해 주세요.');

    // 1) users에서 이메일로 사용자 찾기
    final q = await _fs
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    if (q.docs.isEmpty) {
      return AddFriendResult.fail('해당 이메일의 사용자를 찾을 수 없어요.');
    }

    final friendDoc = q.docs.first;
    final friendUid = friendDoc.id;

    if (friendUid == me.uid) {
      return AddFriendResult.fail('자기 자신은 친구로 추가할 수 없어요.');
    }

    final friendData = friendDoc.data();
    final friendMeta = {
      'uid': friendUid,
      'email': (friendData['email'] ?? '').toString(),
      'name': (friendData['name'] ?? '').toString(),
      'photoUrl': friendData['photoUrl'],
      'createdAt': FieldValue.serverTimestamp(),
    };

    final myMeta = {
      'uid': me.uid,
      'email': (me.email ?? '').toLowerCase(),
      'name': (me.displayName ?? ''),
      'photoUrl': me.photoURL,
      'createdAt': FieldValue.serverTimestamp(),
    };

    final myFriendRef = _fs
        .collection('users')
        .doc(me.uid)
        .collection('friends')
        .doc(friendUid);
    final otherFriendRef = _fs
        .collection('users')
        .doc(friendUid)
        .collection('friends')
        .doc(me.uid);

    // 이미 친구인지 확인
    final already = await myFriendRef.get();
    if (already.exists) {
      return AddFriendResult.ok('이미 친구예요.');
    }

    // 2) 양방향 기록 (트랜잭션)
    await _fs.runTransaction((tx) async {
      tx.set(myFriendRef, friendMeta, SetOptions(merge: true));
      tx.set(otherFriendRef, myMeta, SetOptions(merge: true));
    });

    return AddFriendResult.ok('친구가 추가되었어요.');
  }

  /// 친구 삭제 (양방향 삭제)
  Future<void> removeFriend(String friendUid) async {
    final me = _auth.currentUser;
    if (me == null) return;

    final myRef = _fs
        .collection('users')
        .doc(me.uid)
        .collection('friends')
        .doc(friendUid);
    final otherRef = _fs
        .collection('users')
        .doc(friendUid)
        .collection('friends')
        .doc(me.uid);

    await _fs.runTransaction((tx) async {
      tx.delete(myRef);
      tx.delete(otherRef);
    });
  }
}

// ===== 모델 =====
class FriendUser {
  final String uid;
  final String? email;
  final String? name;
  final String? photoUrl;
  final Timestamp? createdAt;

  FriendUser({
    required this.uid,
    required this.email,
    required this.name,
    required this.photoUrl,
    required this.createdAt,
  });

  factory FriendUser.fromDoc(String id, Map<String, dynamic> d) {
    return FriendUser(
      uid: id,
      email: d['email'] as String?,
      name: d['name'] as String?,
      photoUrl: d['photoUrl'] as String?,
      createdAt: d['createdAt'] as Timestamp?,
    );
  }
}

class AddFriendResult {
  final bool success;
  final String message;

  AddFriendResult._(this.success, this.message);

  factory AddFriendResult.ok(String msg) => AddFriendResult._(true, msg);
  factory AddFriendResult.fail(String msg) => AddFriendResult._(false, msg);
}
