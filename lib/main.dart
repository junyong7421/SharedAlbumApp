import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';

// [병합] LiveKit SDK 사용을 위한 import 유지
import 'package:livekit_client/livekit_client.dart' as lk; // alias 유지
import 'dart:developer' as dev;

import 'screens/login_screen.dart';
import 'screens/voice_call_overlay.dart';

/// [병합] LiveKit SDK 로그 안내(실제 이벤트 로그는 서비스 레벨에서 출력)
void enableLiveKitDebugLogs() {
  // Flutter용 livekit_client에는 전역 enableLogs가 없으므로 알림만 남김
  dev.log(
    'LiveKit debug logs: handled via our event listeners',
    name: 'LiveKitSDK',
  );
}

/// [병합] FirebaseAuth 로그인 보장 (익명 로그인)
Future<void> _ensureSignedIn() async {
  if (FirebaseAuth.instance.currentUser == null) {
    final cred = await FirebaseAuth.instance.signInAnonymously();
    dev.log('Signed in anonymously: ${cred.user?.uid}', name: 'Auth');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // [병합/유지] App Check 활성화 (안드로이드 디버그 강제, iOS는 디버그 시 debug)
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug, // 물리 단말 Play Services 이슈 회피
    appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
  );

  // [유지] App Check 토큰 자동 갱신
  await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

  // [병합] 디버그 환경에서 사전 토큰 발급 로그
  if (kDebugMode) {
    try {
      final token = await FirebaseAppCheck.instance.getToken(true); // 강제 갱신
      debugPrint('🔥 App Check debug token: $token');
    } catch (e) {
      debugPrint('App Check token fetch failed: $e');
    }
  }

  // [병합] Auth 보장 + ID 토큰 강제 갱신(Functions 401 방지)
  await _ensureSignedIn(); // 익명 로그인 보장
  await FirebaseAuth.instance.currentUser!.getIdToken(true); // **중요: 강제 갱신**
  await FirebaseAuth.instance.authStateChanges().firstWhere((u) => u != null);

  // [추가] 최종 셀프 체크 로그
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final idt = await FirebaseAuth.instance.currentUser?.getIdToken();
  debugPrint('Auth uid=$uid, idToken? ${idt != null}');

  // [병합] LiveKit 로그 알림
  enableLiveKitDebugLogs();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey, // [유지] 전역 오버레이 네비게이터
      title: 'Shared Album App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        scaffoldBackgroundColor: const Color(0xFFEFEFFF),
      ),
      home: LoginScreen(),
    );
  }
}