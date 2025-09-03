// lib/services/edit_album_list_service.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class EditAlbumListService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  /// 로그인한 사용자가 속한 편집 가능한 앨범 리스트 가져오기
  Future<List<Map<String, dynamic>>> fetchEditableAlbums() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    final uid = user.uid;
    final snapshot = await _db.child("sharedAlbums").get();

    final List<Map<String, dynamic>> result = [];

    for (final albumEntry in snapshot.children) {
      final data = albumEntry.value as Map<dynamic, dynamic>;
      final members = data['members'] as Map<dynamic, dynamic>? ?? {};
      final isEditing = data['isEditing'] == true;

      if (members.containsKey(uid)) {
        result.add({
          'albumId': albumEntry.key,
          'name': data['name'],
          'members': members.length,
          'photos': data['photoCount'] ?? 0,
          'isEditing': isEditing,
        });
      }
    }

    return result;
  }
}
