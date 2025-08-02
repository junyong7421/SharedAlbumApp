import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/edit_screen.dart'; // 🔹 edit_screen.dart import
import 'screens/shared_album_screen.dart';
import 'screens/friend_manage_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // 🔹 Firebase 초기화
  runApp(MyApp());
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
        scaffoldBackgroundColor: Color(0xFFEFEFFF), // 🔹 배경색 적용
      ),
      home: FriendManageScreen(), // 🔥 여기서 EditScreen을 첫 화면으로 설정
    );
  }
}
