import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'screens/login_screen.dart';
import 'screens/voice_call_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Firebase 초기화
  await Firebase.initializeApp();

  // 2) App Check 활성화
  await FirebaseAppCheck.instance.activate(
    // **안드로이드는 테스트 목적상 강제로 디버그 모드** (물리 단말 Play Services 이슈 회피)
    androidProvider: AndroidProvider.debug, // **변경**
    appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
  );

  // 3) App Check 토큰 자동 갱신
  await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

  // (선택) 디버그에서 App Check 토큰 미리 받아서 준비
  if (kDebugMode) {
    try {
      final appCheckToken = await FirebaseAppCheck.instance.getToken(
        true,
      ); // String? 반환
      debugPrint('AppCheck token: $appCheckToken');
    } catch (e) {
      debugPrint('App Check token fetch failed: $e');
    }
  }

  // 4) Functions 호출 전 인증 보장: 익명 로그인 + ID 토큰 강제 갱신
  if (FirebaseAuth.instance.currentUser == null) {
    await FirebaseAuth.instance.signInAnonymously();
  }
  await FirebaseAuth.instance.currentUser!.getIdToken(true); // **유지(중요)**
  await FirebaseAuth.instance.authStateChanges().firstWhere((u) => u != null);

  // **추가: 최종 셀프 체크 로그**
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final idt = await FirebaseAuth.instance.currentUser?.getIdToken();
  debugPrint('Auth uid=$uid, idToken? ${idt != null}'); // **추가**

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      title: 'Shared Album App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        scaffoldBackgroundColor: const Color(0xFFEFEFFF),
      ),
      home: LoginScreen(),
    );
  }
}
