import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  /// 구글 로그인 + Firestore에 사용자 프로필 upsert
  Future<User?> signInWithGoogle() async {
    try {
      // 1) 구글 계정 선택
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return null;

      // 2) 인증 토큰
      final googleAuth = await googleUser.authentication;

      // 3) Firebase 자격
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 4) 로그인
      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) return null;

      // 5) Firestore에 사용자 프로필 저장(업서트)
      await _saveUserToFirestore(user);

      return user;
    } catch (e) {
      print("🔴 Google 로그인 실패: $e");
      return null;
    }
  }

  /// Firestore: users/{uid} 문서에 upsert (서버 시간 사용)
  Future<void> _saveUserToFirestore(User user) async {
    final doc = _fs.collection('users').doc(user.uid);

    // 이미 존재하면 merge, 없으면 생성
    await doc.set({
      'uid': user.uid,
      'email': user.email,
      'name': user.displayName,
      'photoUrl': user.photoURL,
      'loginMethod': 'google',
      'createdAt': FieldValue.serverTimestamp(), // 서버 시간
      'updatedAt': FieldValue.serverTimestamp(), // 선택: 업데이트 시간
    }, SetOptions(merge: true));
  }
}
