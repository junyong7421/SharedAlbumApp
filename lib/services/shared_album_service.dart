// lib/services/shared_album_service.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Firestore 구조(요지, 경로 분리 적용)
/// albums/{albumId}
///   - title, ownerUid, memberUids[], photoCount, coverPhotoUrl, createdAt, updatedAt
///   photos/{photoId}
///     - url, storagePath, uploaderUid, createdAt
///   edited/{editedId}
///     - url, storagePath, originalPhotoId?, editorUid, createdAt, updatedAt, isEditing, editingUid, editingStartedAt
///
///   // 편집 세션(유저별)과 프레즌스(사진별) 컬렉션 분리
///   editing_by_user/{uid}
///     - uid, photoId?, photoUrl, source('original'|'edited'), editedId?, originalPhotoId?,
///       status('active'|'paused'), startedAt, updatedAt
///
///   editing_presence/{photoId}
///     - photoId, isEditing, editorsCount, topEditorName, updatedAt
///     members/{uid}
///       - uid, name, previewUrl?, updatedAt
///
/// Storage 권장 경로:
///   albums/{albumId}/original/{file}.jpg|png...
///   albums/{albumId}/edited/{photoId}/{millis}.png

class SharedAlbumService {
  SharedAlbumService._();
  static final SharedAlbumService instance = SharedAlbumService._();

  final _fs = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _picker = ImagePicker();

  // 경로 헬퍼
  CollectionReference<Map<String, dynamic>> _editingByUserCol(String albumId) =>
      _fs.collection('albums').doc(albumId).collection('editing_by_user');

  DocumentReference<Map<String, dynamic>> _editingByUserDoc(
    String albumId,
    String uid,
  ) => _editingByUserCol(albumId).doc(uid);

  DocumentReference<Map<String, dynamic>> _presenceSummaryDoc(
    String albumId,
    String photoId,
  ) => _fs
      .collection('albums')
      .doc(albumId)
      .collection('editing_presence')
      .doc(photoId);

  CollectionReference<Map<String, dynamic>> _presenceMembersCol(
    String albumId,
    String photoId,
  ) => _presenceSummaryDoc(albumId, photoId).collection('members');

  // ===== 앨범 =====

  Stream<List<Album>> watchAlbums(String uid) {
    final q = _fs
        .collection('albums')
        .where('memberUids', arrayContains: uid)
        .orderBy('updatedAt', descending: true);
    return q.snapshots().map(
      (qs) => qs.docs.map((d) => Album.fromDoc(d.id, d.data())).toList(),
    );
  }

  Future<String> createAlbum({
    required String uid,
    required String title,
  }) async {
    final ref = _fs.collection('albums').doc();
    await ref.set({
      'title': title,
      'ownerUid': uid,
      'memberUids': [uid],
      'photoCount': 0,
      'coverPhotoUrl': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> renameAlbum({
    required String uid,
    required String albumId,
    required String newTitle,
  }) async {
    await _fs.collection('albums').doc(albumId).update({
      'title': newTitle,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteAlbum({
    required String uid,
    required String albumId,
  }) async {
    final albumRef = _fs.collection('albums').doc(albumId);

    // photos 삭제 + 스토리지 삭제
    final photos = await albumRef.collection('photos').get();
    for (final doc in photos.docs) {
      final data = doc.data();
      final storagePath = data['storagePath'] as String?;
      if (storagePath != null) {
        try {
          await _storage.ref(storagePath).delete();
        } catch (_) {}
      }
      await doc.reference.delete();
    }

    // editing_by_user 삭제
    final editingByUser = await albumRef.collection('editing_by_user').get();
    for (final d in editingByUser.docs) {
      await d.reference.delete();
    }

    // editing_presence + members 삭제
    final presence = await albumRef.collection('editing_presence').get();
    for (final d in presence.docs) {
      final members = await d.reference.collection('members').get();
      for (final m in members.docs) {
        await m.reference.delete();
      }
      await d.reference.delete();
    }

    // edited 삭제 (+ Storage 정리)
    final edited = await albumRef.collection('edited').get();
    for (final d in edited.docs) {
      final data = d.data();
      final editedStoragePath = data['storagePath'] as String?;
      if (editedStoragePath != null) {
        try {
          await _storage.ref(editedStoragePath).delete();
        } catch (_) {}
      }
      await d.reference.delete();
    }

    // 앨범 문서 삭제
    await albumRef.delete();

    // Storage 폴더 잔여 정리 (best effort)
    try {
      final folderRef = _storage.ref('albums/$albumId');
      final list = await folderRef.listAll();
      for (final item in list.items) {
        await item.delete();
      }
      for (final pref in list.prefixes) {
        final sub = await pref.listAll();
        for (final it in sub.items) {
          await it.delete();
        }
      }
    } catch (_) {}
  }

  // ===== 사진 업로드/삭제/조회 =====

  Future<void> addPhotosFromGallery({
    required String uid,
    required String albumId,
    bool allowMultiple = true,
  }) async {
    List<XFile> picked = [];
    if (allowMultiple) {
      picked = await _picker.pickMultiImage(imageQuality: 90);
    } else {
      final single = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (single != null) picked = [single];
    }
    if (picked.isEmpty) return;

    final albumRef = _fs.collection('albums').doc(albumId);
    final photosRef = albumRef.collection('photos');

    int added = 0;
    String? lastUrl;

    for (final x in picked) {
      final file = File(x.path);
      final ext = _extFromMime(x.mimeType) ?? _extFromPath(x.path) ?? 'jpg';
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${_rand()}.$ext';
      final storagePath = 'albums/$albumId/original/$fileName';

      final task = await _storage.ref(storagePath).putFile(file);
      final url = await task.ref.getDownloadURL();

      await photosRef.add({
  'url': url,
  'storagePath': storagePath,
  'uploaderUid': uid,
  'createdAt': FieldValue.serverTimestamp(),
  'likedBy': <String>[], // 👍 초기값 추가
});


      added++;
      lastUrl = url;
    }

    await _fs.runTransaction((tx) async {
      final snap = await tx.get(albumRef);
      final data = snap.data() ?? {};
      final current = (data['photoCount'] ?? 0) as int;
      final cover = data['coverPhotoUrl'];
      final needsCover = cover == null;

      tx.update(albumRef, {
        'photoCount': current + added,
        if (needsCover && lastUrl != null) 'coverPhotoUrl': lastUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> deletePhoto({
    required String uid,
    required String albumId,
    required String photoId,
  }) async {
    final photoRef = _fs
        .collection('albums')
        .doc(albumId)
        .collection('photos')
        .doc(photoId);

    final snap = await photoRef.get();
    if (!snap.exists) return;
    final data = snap.data()!;
    final storagePath = data['storagePath'] as String?;

    if (storagePath != null) {
      try {
        await _storage.ref(storagePath).delete();
      } catch (_) {}
    }

    await photoRef.delete();

    final albumRef = _fs.collection('albums').doc(albumId);
    await _fs.runTransaction((tx) async {
      final a = await tx.get(albumRef);
      final d = a.data() ?? {};
      final cnt = (d['photoCount'] ?? 0) as int;
      final newCnt = cnt > 0 ? cnt - 1 : 0;

      String? newCover;
      if ((d['coverPhotoUrl'] as String?) == (data['url'] as String?)) {
        final latest = await albumRef
            .collection('photos')
            .orderBy('createdAt', descending: true)
            .limit(1)
            .get();
        newCover = latest.docs.isNotEmpty
            ? latest.docs.first.data()['url'] as String
            : null;
      }

      tx.update(albumRef, {
        'photoCount': newCnt,
        'coverPhotoUrl': newCover,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Stream<List<Photo>> watchPhotos({
    required String uid,
    required String albumId,
  }) {
    final col = _fs
        .collection('albums')
        .doc(albumId)
        .collection('photos')
        .orderBy('createdAt', descending: true);

    return col.snapshots().map(
  (qs) => qs.docs.map((d) => Photo.fromMap(d.id, d.data())).toList(),
);

  }

  Future<void> toggleLike({
    required String uid,
    required String albumId,
    required String photoId,
    required bool like, // true면 추가, false면 제거
  }) async {
    final ref = _fs
        .collection('albums')
        .doc(albumId)
        .collection('photos')
        .doc(photoId);

    await ref.update({
      'likedBy': like
          ? FieldValue.arrayUnion([uid])
          : FieldValue.arrayRemove([uid]),
    });
  }

  // ===== 내부: edited 잠금/해제 (선택적) =====
  Future<void> _lockEdited({
    required String albumId,
    required String editedId,
    required String uid,
  }) async {
    final ref = _fs
        .collection('albums')
        .doc(albumId)
        .collection('edited')
        .doc(editedId);
    await ref.update({
      'isEditing': true,
      'editingUid': uid,
      'editingStartedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _unlockEdited({
    required String albumId,
    required String editedId,
  }) async {
    final ref = _fs
        .collection('albums')
        .doc(albumId)
        .collection('edited')
        .doc(editedId);
    await ref.update({
      'isEditing': false,
      'editingUid': null,
      'editingStartedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ===== 편집 세션 (editing_by_user/* by uid) =====

  Future<void> setEditing({
    required String uid,
    required String albumId,
    String? photoId,
    required String photoUrl,
    String source = 'original',
    String? editedId,
    String? originalPhotoId,
  }) async {
    final ref = _editingByUserDoc(albumId, uid);

    await ref.set({
      'uid': uid,
      if (photoId != null) 'photoId': photoId,
      'photoUrl': photoUrl,
      'source': source,
      if (editedId != null) 'editedId': editedId,
      if (originalPhotoId != null) 'originalPhotoId': originalPhotoId,
      'status': 'active',
      'startedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _fs.collection('albums').doc(albumId).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> touchEditing({
    required String uid,
    required String albumId,
  }) async {
    await _editingByUserDoc(albumId, uid).set({
      'status': 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> pauseEditing({
    required String uid,
    required String albumId,
  }) async {
    await _editingByUserDoc(albumId, uid).set({
      'status': 'paused',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> endEditing({
    required String uid,
    required String albumId,
  }) async {
    await _editingByUserDoc(albumId, uid).delete();
  }

  Future<void> clearEditingByUrl({
    required String albumId,
    required String photoUrl,
  }) async {
    final col = _editingByUserCol(albumId);
    final qs = await col.where('photoUrl', isEqualTo: photoUrl).get();
    for (final d in qs.docs) {
      try {
        await d.reference.delete();
      } catch (_) {}
    }
  }

  Future<void> clearEditingForTarget({
    required String albumId,
    String? editedId,
    String? originalPhotoId,
    String? photoId,
  }) async {
    final col = _editingByUserCol(albumId);

    if (editedId != null && editedId.isNotEmpty) {
      final qs = await col.where('editedId', isEqualTo: editedId).get();
      for (final d in qs.docs) {
        try {
          await d.reference.delete();
        } catch (_) {}
      }
      try {
        await _unlockEdited(albumId: albumId, editedId: editedId);
      } catch (_) {}
    }

    if (originalPhotoId != null && originalPhotoId.isNotEmpty) {
      final qs = await col
          .where('originalPhotoId', isEqualTo: originalPhotoId)
          .get();
      for (final d in qs.docs) {
        try {
          await d.reference.delete();
        } catch (_) {}
      }
    }

    if (photoId != null && photoId.isNotEmpty) {
      final qs = await col.where('photoId', isEqualTo: photoId).get();
      for (final d in qs.docs) {
        try {
          await d.reference.delete();
        } catch (_) {}
      }
    }
  }

  Stream<EditingInfo?> watchMyEditing({
    required String uid,
    required String albumId,
  }) {
    final ref = _editingByUserDoc(albumId, uid);
    return ref.snapshots().map((ds) {
      if (!ds.exists) return null;
      return EditingInfo.fromDoc(albumId, ds.data()!);
    });
  }

  // albums/{albumId}/editing_by_user 에서 active 세션 목록
  Stream<List<EditingInfo>> watchEditingForAlbum(String albumId) {
    final col = _editingByUserCol(albumId);
    final q = col
        .where('status', isEqualTo: 'active')
        .orderBy('updatedAt', descending: true)
        .limit(100);

    return q.snapshots().map((qs) {
      return qs.docs
          .map((d) => EditingInfo.fromDoc(albumId, d.data()))
          .where((e) => e.photoUrl.trim().isNotEmpty)
          .toList();
    });
  }

  // ===== 프레즌스 + 실시간 프리뷰 (editing_presence/{photoId}) =====

  Future<void> enterEditingPresence({
    required String albumId,
    required String photoId,
    required String uid,
    required String name,
  }) async {
    final summaryRef = _presenceSummaryDoc(albumId, photoId);
    final memberRef = _presenceMembersCol(albumId, photoId).doc(uid);

    await _fs.runTransaction((tx) async {
      final memberSnap = await tx.get(memberRef);
      final existed = memberSnap.exists;

      tx.set(memberRef, {
        'uid': uid,
        'name': name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final sumSnap = await tx.get(summaryRef);
      String? topName = sumSnap.exists
          ? (sumSnap.data()?['topEditorName'] as String?)
          : null;

      tx.set(summaryRef, {
        'photoId': photoId,
        'isEditing': true,
        if (!existed) 'editorsCount': FieldValue.increment(1),
        'topEditorName': topName ?? name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> heartbeatEditingPresence({
    required String albumId,
    required String photoId,
    required String uid,
  }) async {
    final memberRef = _presenceMembersCol(albumId, photoId).doc(uid);
    await memberRef.set({
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateEditingPreviewPresence({
    required String albumId,
    required String photoId,
    required String uid,
    required String previewUrl,
  }) async {
    final summaryRef = _presenceSummaryDoc(albumId, photoId);
    final memberRef = _presenceMembersCol(albumId, photoId).doc(uid);

    await _fs.runTransaction((tx) async {
      tx.set(memberRef, {
        'previewUrl': previewUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      tx.set(summaryRef, {
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> leaveEditingPresence({
    required String albumId,
    required String photoId,
    required String uid,
  }) async {
    final summaryRef = _presenceSummaryDoc(albumId, photoId);
    final memberRef = _presenceMembersCol(albumId, photoId).doc(uid);

    String? leavingName;
    String? currentTopName;
    bool existed = false;

    await _fs.runTransaction((tx) async {
      final mySnap = await tx.get(memberRef);
      existed = mySnap.exists;
      if (existed) {
        final md = mySnap.data() as Map<String, dynamic>;
        leavingName = md['name'] as String?;
        tx.delete(memberRef);
      }

      final sumSnap = await tx.get(summaryRef);
      if (sumSnap.exists) {
        final d = sumSnap.data() as Map<String, dynamic>;
        currentTopName = d['topEditorName'] as String?;
        tx.set(summaryRef, {
          if (existed) 'editorsCount': FieldValue.increment(-1),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });

    final after = await summaryRef.get();
    if (!after.exists) return;
    final data = after.data() as Map<String, dynamic>;
    final count = (data['editorsCount'] ?? 0) as int;

    if (count <= 0) {
      await summaryRef.set({
        'isEditing': false,
        'editorsCount': 0,
        'topEditorName': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    final iWasTop = (leavingName != null && leavingName == currentTopName);
    if (iWasTop) {
      final newest = await _presenceMembersCol(
        albumId,
        photoId,
      ).orderBy('updatedAt', descending: true).limit(1).get();
      String? newTop = newest.docs.isNotEmpty
          ? (newest.docs.first.data()['name'] as String?)
          : null;

      await summaryRef.set({
        'isEditing': true,
        'topEditorName': newTop,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      await summaryRef.set({
        'isEditing': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  // 요약 스트림: EditScreen 배지용
  Stream<DocumentSnapshot<Map<String, dynamic>>> editingSummaryStream({
    required String albumId,
    required String photoId,
  }) {
    return _presenceSummaryDoc(albumId, photoId).snapshots();
  }

  // 멤버 스트림: EditViewScreen에서 타인 프리뷰 표시용
  Stream<QuerySnapshot<Map<String, dynamic>>> editingMembersStream({
    required String albumId,
    required String photoId,
  }) {
    return _presenceMembersCol(
      albumId,
      photoId,
    ).orderBy('updatedAt', descending: true).snapshots();
  }

  // ===== 편집본 저장 (edited/*) =====

  String generateEditedStoragePath({
    required String albumId,
    required String photoId,
    String ext = 'png',
  }) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return 'albums/$albumId/edited/$photoId/$ts.$ext';
  }

  Future<void> saveEditedPhotoFromUrl({
    required String albumId,
    required String editorUid,
    required String originalPhotoId,
    required String editedUrl,
    String? storagePath,
  }) async {
    final editedRef = _fs
        .collection('albums')
        .doc(albumId)
        .collection('edited')
        .doc();

    await editedRef.set({
      'url': editedUrl,
      'storagePath': storagePath,
      'originalPhotoId': originalPhotoId,
      'editorUid': editorUid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isEditing': false,
      'editingUid': null,
      'editingStartedAt': null,
    });

    await clearEditingForTarget(
      albumId: albumId,
      originalPhotoId: originalPhotoId,
      photoId: originalPhotoId,
    );
  }

  Future<void> saveEditedPhoto({
    required String albumId,
    required String url,
    required String editorUid,
    String? originalPhotoId,
    String? storagePath,
  }) async {
    final ref = _fs
        .collection('albums')
        .doc(albumId)
        .collection('edited')
        .doc();
    await ref.set({
      'url': url,
      'storagePath': storagePath,
      if (originalPhotoId != null) 'originalPhotoId': originalPhotoId,
      'editorUid': editorUid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isEditing': false,
      'editingUid': null,
      'editingStartedAt': null,
    });
    await _fs.collection('albums').doc(albumId).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (originalPhotoId != null && originalPhotoId.isNotEmpty) {
      await clearEditingForTarget(
        albumId: albumId,
        originalPhotoId: originalPhotoId,
        photoId: originalPhotoId,
      );
    } else {
      // URL 중복 가능성이 있으므로 URL 기준 일괄 정리는 비활성화
      // try { await clearEditingByUrl(albumId: albumId, photoUrl: url); } catch (_) {}
    }
  }

  Future<void> saveEditedPhotoOverwrite({
    required String albumId,
    required String editedId,
    required String newUrl,
    required String editorUid,
    String? newStoragePath,
    bool deleteOld = true,
  }) async {
    final ref = _fs
        .collection('albums')
        .doc(albumId)
        .collection('edited')
        .doc(editedId);

    String? oldStoragePath;
    try {
      final snap = await ref.get();
      final data = snap.data();
      oldStoragePath = data?['storagePath'] as String?;
    } catch (_) {}

    await ref.update({
      'url': newUrl,
      if (newStoragePath != null) 'storagePath': newStoragePath,
      'editorUid': editorUid,
      'isEditing': false,
      'editingUid': null,
      'editingStartedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _fs.collection('albums').doc(albumId).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (deleteOld &&
        oldStoragePath != null &&
        oldStoragePath.isNotEmpty &&
        oldStoragePath != newStoragePath) {
      try {
        await _storage.ref(oldStoragePath).delete();
      } catch (_) {}
    }

    await clearEditingForTarget(albumId: albumId, editedId: editedId);
  }

  Stream<List<EditedPhoto>> watchEditedPhotos(String albumId) {
    final q = _fs
        .collection('albums')
        .doc(albumId)
        .collection('edited')
        .orderBy('createdAt', descending: true);

    return q.snapshots().map(
      (qs) => qs.docs.map((d) => EditedPhoto.fromDoc(d.id, d.data())).toList(),
    );
  }

  Future<void> deleteEditedPhoto({
    required String? albumId,
    required String editedId,
  }) async {
    if (albumId == null) throw ArgumentError('albumId is null');

    final ref = _fs
        .collection('albums')
        .doc(albumId)
        .collection('edited')
        .doc(editedId);
    String? storagePath;
    try {
      final snap = await ref.get();
      final data = snap.data();
      storagePath = data?['storagePath'] as String?;
    } catch (_) {}

    await ref.delete();

    if (storagePath != null) {
      try {
        await _storage.ref(storagePath).delete();
      } catch (_) {}
    }
  }

  // ===== 유틸 =====

  String _rand() =>
      (100000 + (DateTime.now().microsecondsSinceEpoch % 900000)).toString();

  String? _extFromMime(String? mime) {
    if (mime == null) return null;
    if (mime.contains('jpeg')) return 'jpg';
    if (mime.contains('png')) return 'png';
    if (mime.contains('gif')) return 'gif';
    if (mime.contains('webp')) return 'webp';
    return null;
  }

  String? _extFromPath(String path) {
    final i = path.lastIndexOf('.');
    if (i < 0) return null;
    return path.substring(i + 1).toLowerCase();
  }
}

// ===== 모델 =====

class Album {
  final String id;
  final String title;
  final String ownerUid;
  final List<String> memberUids;
  final int photoCount;
  final String? coverPhotoUrl;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  Album({
    required this.id,
    required this.title,
    required this.ownerUid,
    required this.memberUids,
    required this.photoCount,
    required this.coverPhotoUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Album.fromDoc(String id, Map<String, dynamic> d) {
    return Album(
      id: id,
      title: (d['title'] ?? '') as String,
      ownerUid: (d['ownerUid'] ?? '') as String,
      memberUids: List<String>.from((d['memberUids'] ?? []) as List),
      photoCount: (d['photoCount'] ?? 0) as int,
      coverPhotoUrl: d['coverPhotoUrl'] as String?,
      createdAt: d['createdAt'] as Timestamp?,
      updatedAt: d['updatedAt'] as Timestamp?,
    );
  }
}

class Photo {
  final String id;
  final String url;
  final List<String> likedBy; // 👍 누른 uid 목록

  Photo({
    required this.id,
    required this.url,
    this.likedBy = const [],
  });

  factory Photo.fromMap(String id, Map<String, dynamic> m) {
    return Photo(
      id: id,
      url: (m['url'] as String?) ?? '',
      likedBy: (m['likedBy'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'likedBy': likedBy,
    };
  }
}


class EditingInfo {
  final String albumId;
  final String? photoId;
  final String photoUrl;
  final String? source;
  final String? editedId;
  final String? originalPhotoId;
  final String? status;
  final Timestamp? updatedAt;

  EditingInfo({
    required this.albumId,
    required this.photoUrl,
    this.photoId,
    this.source,
    this.editedId,
    this.originalPhotoId,
    this.status,
    this.updatedAt,
  });

  factory EditingInfo.fromDoc(String albumId, Map<String, dynamic> d) {
    return EditingInfo(
      albumId: albumId,
      photoId: d['photoId'] as String?,
      photoUrl: (d['photoUrl'] ?? '') as String,
      source: d['source'] as String?,
      editedId: d['editedId'] as String?,
      originalPhotoId: d['originalPhotoId'] as String?,
      status: d['status'] as String?,
      updatedAt: d['updatedAt'] as Timestamp?,
    );
  }
}

class EditedPhoto {
  final String id;
  final String url;
  final String? storagePath;
  final String? originalPhotoId;
  final String editorUid;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  EditedPhoto({
    required this.id,
    required this.url,
    required this.editorUid,
    this.storagePath,
    this.originalPhotoId,
    this.createdAt,
    this.updatedAt,
  });

  factory EditedPhoto.fromDoc(String id, Map<String, dynamic> d) {
    return EditedPhoto(
      id: id,
      url: (d['url'] ?? '') as String,
      storagePath: d['storagePath'] as String?,
      originalPhotoId: d['originalPhotoId'] as String?,
      editorUid: (d['editorUid'] ?? '') as String,
      createdAt: d['createdAt'] as Timestamp?,
      updatedAt: d['updatedAt'] as Timestamp?,
    );
  }
}
