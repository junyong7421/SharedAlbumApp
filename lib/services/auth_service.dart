import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_database/firebase_database.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  /// 구글 로그인 수행 + 사용자 DB에 자동 등록
  Future<User?> signInWithGoogle() async {
    try {
      // 1. 구글 계정 선택
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return null;

      // 2. 인증 정보 가져오기
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // 3. Firebase 인증 자격 생성
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 4. Firebase 로그인
      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );
      final user = userCredential.user;
      if (user == null) return null;

      // 5. 사용자 정보 DB에 저장
      await _saveUserToDatabase(user);

      return user;
    } catch (e) {
      print("🔴 Google 로그인 실패: $e");
      return null;
    }
  }

  /// 사용자 정보를 Realtime Database에 저장
  Future<void> _saveUserToDatabase(User user) async {
    final ref = _db.ref("users/${user.uid}");
    final snapshot = await ref.get();

    if (!snapshot.exists) {
      // DB에 사용자 정보가 없는 경우만 저장
      await ref.set({
        "uid": user.uid,
        "email": user.email,
        "name": user.displayName,
        "photoUrl": user.photoURL,
        "loginMethod": "google",
        "createdAt": DateTime.now().toIso8601String(),
      });
    }
  }
}
