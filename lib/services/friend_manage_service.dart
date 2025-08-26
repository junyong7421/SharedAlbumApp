import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FriendManageService {
  FriendManageService._();
  static final FriendManageService instance = FriendManageService._();

  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  /// 내 친구 목록 실시간 구독
  /// - 작성 시각이 최근인 친구가 위로 오도록 정렬
  Stream<List<FriendUser>> watchFriends() {
    final me = _auth.currentUser;
    if (me == null) {
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

  /// 이메일로 친구 추가 (양방향, idempotent)
  Future<AddFriendResult> addFriendByEmail(String rawEmail) async {
    final me = _auth.currentUser;
    if (me == null) return AddFriendResult.fail('로그인이 필요합니다.');

    final email = normalizeEmail(rawEmail);
    if (email.isEmpty) return AddFriendResult.fail('이메일을 입력해 주세요.');

    // 1) 사용자 조회 (emailLower 우선 → fallback: email)
    final target = await getUserByEmail(email);
    if (target == null) {
      return AddFriendResult.fail('해당 이메일의 사용자를 찾을 수 없어요.');
    }

    final friendUid = target.id;
    final friendData = target.data()!;

    if (friendUid == me.uid) {
      return AddFriendResult.fail('자기 자신은 친구로 추가할 수 없어요.');
    }

    // 2) 이미 친구인지 확인 (idempotent)
    final already = await isAlreadyFriend(me.uid, friendUid);
    if (already) {
      return AddFriendResult.ok('이미 친구예요.');
    }

    // 3) 메타 구성
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

    // 4) 트랜잭션으로 양방향 쓰기
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

  // -------------------- 유틸 --------------------

  /// users 컬렉션에서 이메일로 사용자 문서를 찾는다.
  /// - emailLower 필드가 있는 경우 대소문자 구애 없이 빠르게 검색
  /// - 없다면 fallback 으로 email == 원본소문자 비교(케이스 맞는 데이터여야 히트)
  Future<DocumentSnapshot<Map<String, dynamic>>?> getUserByEmail(
    String normalizedEmail,
  ) async {
    // emailLower 우선
    final q1 = await _fs
        .collection('users')
        .where('emailLower', isEqualTo: normalizedEmail)
        .limit(1)
        .get();

    if (q1.docs.isNotEmpty) return q1.docs.first;

    // fallback: email (기존 데이터 호환)
    final q2 = await _fs
        .collection('users')
        .where('email', isEqualTo: normalizedEmail)
        .limit(1)
        .get();

    if (q2.docs.isNotEmpty) return q2.docs.first;

    return null;
  }

  /// 이미 친구인지 확인
  Future<bool> isAlreadyFriend(String myUid, String friendUid) async {
    final ref = _fs
        .collection('users')
        .doc(myUid)
        .collection('friends')
        .doc(friendUid);
    final snap = await ref.get();
    return snap.exists;
  }

  /// 이메일 정규화 (좌우 공백 제거 + 소문자)
  String normalizeEmail(String raw) => raw.trim().toLowerCase();
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
