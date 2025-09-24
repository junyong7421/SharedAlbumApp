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
Future<User?> _safeEnsureSignedIn() async {
  try {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) return auth.currentUser;
    final cred = await auth.signInAnonymously(); // 콘솔에서 Anonymous 꺼져있으면 예외
    return cred.user;
  } catch (e) {
    debugPrint('Anonymous sign-in failed: $e');
    // 로그인 강제하지 않고 게스트/비로그인 모드로 계속 진행
    return FirebaseAuth.instance.currentUser; // 여전히 null일 수 있음
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // App Check: 개발은 debug, 배포는 정식 프로바이더
  await FirebaseAppCheck.instance.activate(
    androidProvider: kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
    appleProvider: kReleaseMode ? AppleProvider.deviceCheck : AppleProvider.debug,
  );
  await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
  if (kDebugMode) {
    try { await FirebaseAppCheck.instance.getToken(true); } catch (e) { debugPrint('AppCheck token: $e'); }
  }

  // 로그인 시도(실패해도 크래시 X)
  final user = await _safeEnsureSignedIn();

  // user가 있을 때만 ID 토큰 강제 갱신
  if (user != null) {
    try { await user.getIdToken(true); } catch (e) { debugPrint('getIdToken failed: $e'); }
  } else {
    debugPrint('No user session. Running without authentication.');
  }

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