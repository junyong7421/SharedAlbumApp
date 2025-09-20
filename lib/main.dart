import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:livekit_client/livekit_client.dart' as lk; // alias만 유지
import 'dart:developer' as dev;

import 'screens/login_screen.dart';
import 'screens/voice_call_overlay.dart';

/// LiveKit SDK 로그 활성화 (Flutter SDK에는 전역 enableLogs API가 없음)
void enableLiveKitDebugLogs() {
  // Flutter용 livekit_client에는 Logger/enableLogs가 없으므로
  // 여기서는 개발 로그 시작 알림만 남기고,
  // 실제 상세 로그는 join 서비스에서 이벤트별로 찍는다.
  dev.log('LiveKit debug logs: handled via our event listeners', name: 'LiveKitSDK');
}

/// FirebaseAuth 로그인 보장 (익명 로그인)
Future<void> _ensureSignedIn() async {
  if (FirebaseAuth.instance.currentUser == null) {
    final cred = await FirebaseAuth.instance.signInAnonymously();
    dev.log('Signed in anonymously: ${cred.user?.uid}', name: 'Auth');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  await FirebaseAppCheck.instance.activate(
    androidProvider: kDebugMode
        ? AndroidProvider.debug
        : AndroidProvider.playIntegrity,
    appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
  );
  await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

  if (kDebugMode) {
    try {
      final token = await FirebaseAppCheck.instance.getToken();
      debugPrint('🔥 App Check debug token (dev only): $token');
    } catch (e) {
      debugPrint('App Check token fetch failed: $e');
    }
  }

  // 로그 안내 (실제 상세 로그는 서비스에서 출력)
  enableLiveKitDebugLogs();

  // Auth 보장
  await _ensureSignedIn();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey, // 전역 오버레이
      title: 'Shared Album App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        scaffoldBackgroundColor: const Color(0xFFEFEFFF),
      ),
      home: LoginScreen(),
    );
  }
}
