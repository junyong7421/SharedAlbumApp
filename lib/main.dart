import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Firebase 초기화
  await Firebase.initializeApp();

  // 2) App Check 활성화
  //
  //  - 개발(kDebugMode=true): Debug Provider 사용
  //    * App Check가 Enforce(강제)면 '디버그 토큰'을 콘솔에 등록해야 통과합니다.
  //    * Monitoring(모니터링) 상태면 등록 없이도 요청은 통과(로그만 남음).
  //
  //  - 릴리즈: Android는 Play Integrity, iOS는 App Attest(미지원 기기는 DeviceCheck 고려)
  await FirebaseAppCheck.instance.activate(
    androidProvider: kDebugMode
        ? AndroidProvider.debug
        : AndroidProvider.playIntegrity,
    appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
  );

  // 3) App Check 토큰 자동 갱신 (기본값 true지만 명시해도 OK)
  await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

  // (선택) 디버그에서 토큰 한 번 받아보기 — 개발 확인용. 배포 시 제거 권장.
  if (kDebugMode) {
    try {
      final token = await FirebaseAppCheck.instance.getToken();
      debugPrint('🔥 App Check debug token (for dev check only): $token');
      // 실제 운영 로그에 토큰 노출은 비추!
    } catch (e) {
      debugPrint('App Check token fetch failed: $e');
    }
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Shared Album App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        scaffoldBackgroundColor: const Color(0xFFEFEFFF),
      ),
      home: LoginScreen(),
    );
  }
}
