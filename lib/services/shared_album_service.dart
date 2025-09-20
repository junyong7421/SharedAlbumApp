// lib/services/shared_album_service.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Firestore 구조(요지, 경로 분리 적용)
/// albums/{albumId}
///   - title, ownerUid, memberUids[], photoCount, coverPhotoUrl, createdAt, updatedAt
///   photos/{photoId}
///     - url, storagePath, uploaderUid, createdAt, likedBy[]
///   edited/{editedId}
///     - url, storagePath, originalPhotoId?, editorUid, createdAt, updatedAt,
///       isEditing, editingUid, editingStartedAt
///
/// 편집 세션 (유저별)
///   editing_by_user/{uid}
///     - uid, photoId?, photoUrl, source('original'|'edited'),
///       editedId?, originalPhotoId?, status('active'),
///       userDisplayName?, startedAt, updatedAt
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
  CollectionReference<Map<String, dynamic>> _albumsCol() =>
      _fs.collection('albums');

  DocumentReference<Map<String, dynamic>> _albumDoc(String albumId) =>
      _albumsCol().doc(albumId);

  CollectionReference<Map<String, dynamic>> _photosCol(String albumId) =>
      _albumDoc(albumId).collection('photos');

  CollectionReference<Map<String, dynamic>> _editedCol(String albumId) =>
      _albumDoc(albumId).collection('edited');

  CollectionReference<Map<String, dynamic>> _editingByUserCol(String albumId) =>
      _albumDoc(albumId).collection('editing_by_user');

  DocumentReference<Map<String, dynamic>> _editingByUserDoc(
    String albumId,
    String uid,
  ) =>
      _editingByUserCol(albumId).doc(uid);

  // ===== 앨범 =====

  Stream<List<Album>> watchAlbums(String uid) {
    final q = _albumsCol()
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
    final ref = _albumsCol().doc();
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
    await _albumDoc(albumId)
        .update({'title': newTitle, 'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> deleteAlbum({
    required String uid,
    required String albumId,
  }) async {
    final albumRef = _albumDoc(albumId);

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
      final single =
          await _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
      if (single != null) picked = [single];
    }
    if (picked.isEmpty) return;

    final albumRef = _albumDoc(albumId);
    final photosRef = _photosCol(albumId);

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
        'likedBy': <String>[],
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
    final photoRef = _photosCol(albumId).doc(photoId);

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

    final albumRef = _albumDoc(albumId);
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
        newCover =
            latest.docs.isNotEmpty ? latest.docs.first.data()['url'] as String : null;
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
    final col = _photosCol(albumId).orderBy('createdAt', descending: true);
    return col.snapshots().map(
          (qs) => qs.docs.map((d) => Photo.fromMap(d.id, d.data())).toList(),
        );
  }

  Future<void> toggleLike({
    required String uid,
    required String albumId,
    required String photoId,
    required bool like,
  }) async {
    final ref = _photosCol(albumId).doc(photoId);
    await ref.update({
      'likedBy':
          like ? FieldValue.arrayUnion([uid]) : FieldValue.arrayRemove([uid]),
    });
  }

  // ===== 내부: edited 잠금/해제 (선택적) =====
  Future<void> _lockEdited({
    required String albumId,
    required String editedId,
    required String uid,
  }) async {
    final ref = _editedCol(albumId).doc(editedId);
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
    final ref = _editedCol(albumId).doc(editedId);
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
    String? userDisplayName, // 추가: 이름 저장
  }) async {
    final ref = _editingByUserDoc(albumId, uid);

    // 기존 startedAt 보존
    Timestamp? existingStartedAt;
    try {
      final snap = await ref.get();
      final data = snap.data();
      if (snap.exists && data != null && data['startedAt'] is Timestamp) {
        existingStartedAt = data['startedAt'] as Timestamp;
      }
    } catch (_) {}

    // photoId 자동 보정
    final effectivePhotoId = (photoId != null && photoId.isNotEmpty)
        ? photoId
        : ((originalPhotoId != null && originalPhotoId.isNotEmpty)
            ? originalPhotoId
            : null);

    await ref.set({
      'uid': uid,
      if (effectivePhotoId != null) 'photoId': effectivePhotoId,
      'photoUrl': photoUrl,
      'source': source,
      if (editedId != null) 'editedId': editedId,
      if (originalPhotoId != null) 'originalPhotoId': originalPhotoId,
      if (userDisplayName != null && userDisplayName.isNotEmpty)
        'userDisplayName': userDisplayName,
      'status': 'active',
      'startedAt': existingStartedAt ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _albumDoc(albumId)
        .update({'updatedAt': FieldValue.serverTimestamp()});
  }

  /// [DEPRECATED] 기존 호출 호환용: 이제는 '일시정지' 없이 바로 세션 종료 처리
  Future<void> pauseEditing({
    required String uid,
    required String albumId,
  }) async {
    await endEditing(uid: uid, albumId: albumId);
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
      final qs =
          await col.where('originalPhotoId', isEqualTo: originalPhotoId).get();
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
      return EditingInfo.fromDoc(albumId, ds.data()!, docId: ds.id);
    });
  }

  // 앨범의 세션 실시간 목록 (active만)
  Stream<List<EditingInfo>> watchEditingForAlbum(String albumId) {
    final q = _editingByUserCol(albumId)
        .where('status', isEqualTo: 'active')
        .orderBy('updatedAt', descending: true)
        .limit(300);
    return q.snapshots().map((qs) {
      return qs.docs
          .map((d) => EditingInfo.fromDoc(albumId, d.data(), docId: d.id))
          .where((e) => e.photoUrl.trim().isNotEmpty)
          .toList();
    });
  }

  // ===== 사진별 편집자 =====

  // 사진별 "편집 중 인원수" 실시간 (active만)
  Stream<int> watchActiveEditorCount({
    required String albumId,
    required String photoId,
  }) {
    final q = _editingByUserCol(albumId)
        .where('status', isEqualTo: 'active')
        .where('photoId', isEqualTo: photoId);
    return q.snapshots().map((qs) => qs.docs.length);
  }

  // 사진별 "편집 중 사용자들" 실시간(실제 작업 중만: active)
  Stream<List<EditingInfo>> watchEditorsOfPhotoRT({
    required String albumId,
    required String photoId,
  }) {
    final q = _editingByUserCol(albumId)
        .where('status', isEqualTo: 'active')
        .where('photoId', isEqualTo: photoId)
        .orderBy('updatedAt', descending: true)
        .limit(50);
    return q.snapshots().map(
          (qs) =>
              qs.docs.map((d) => EditingInfo.fromDoc(albumId, d.data(), docId: d.id)).toList(),
        );
  }

  // 앨범의 세션(단발성) - active만
  Future<List<EditingInfo>> fetchActiveEditingSessions(String albumId) async {
    final qs = await _editingByUserCol(albumId)
        .where('status', isEqualTo: 'active')
        .orderBy('updatedAt', descending: true)
        .limit(300)
        .get();

    return qs.docs
        .map((d) => EditingInfo.fromDoc(albumId, d.data(), docId: d.id))
        .where((e) => e.photoUrl.trim().isNotEmpty)
        .toList();
  }

  // 사진별 "편집 중 사용자들" 단발성(작업 중만: active)
  Future<List<EditingInfo>> fetchEditorsOfPhoto(
    String albumId,
    String photoId,
  ) async {
    final qs = await _editingByUserCol(albumId)
        .where('status', isEqualTo: 'active')
        .where('photoId', isEqualTo: photoId)
        .orderBy('updatedAt', descending: true)
        .limit(50)
        .get();

    return qs.docs
        .map((d) => EditingInfo.fromDoc(albumId, d.data(), docId: d.id))
        .toList();
  }

  // 앨범에서 현재 '작업중(active)' 사진 ID 집합(단발성)
  Future<List<String>> fetchPhotoIdsBeingEditedFromSessions(
    String albumId,
  ) async {
    final qs = await _editingByUserCol(albumId)
        .where('status', isEqualTo: 'active')
        .orderBy('updatedAt', descending: true)
        .limit(300)
        .get();

    final set = <String>{};
    for (final d in qs.docs) {
      final m = d.data();
      final pid =
          (m['photoId'] as String?) ?? (m['originalPhotoId'] as String?) ?? '';
      if (pid.isNotEmpty) set.add(pid);
    }
    return set.toList();
  }

  /// '편집중 배지'로 표시해야 할 **사진 고유 ID 리스트**(단발성, active만)
  /// - photoId > originalPhotoId > editedId 우선순위로 키 생성 및 dedupe
  Future<List<String>> fetchEditingPhotoIds(String albumId) async {
    final qs = await _editingByUserCol(albumId)
        .where('status', isEqualTo: 'active')
        .orderBy('updatedAt', descending: true)
        .limit(300)
        .get();

    final set = <String>{};
    for (final d in qs.docs) {
      final m = d.data();
      final key = (m['photoId'] as String?)?.trim().isNotEmpty == true
          ? (m['photoId'] as String).trim()
          : (m['originalPhotoId'] as String?)?.trim().isNotEmpty == true
              ? (m['originalPhotoId'] as String).trim()
              : (m['editedId'] as String?)?.trim() ?? '';
      if (key.isNotEmpty) set.add(key);
    }
    return set.toList();
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
    final editedRef = _editedCol(albumId).doc();

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
    final ref = _editedCol(albumId).doc();
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
    await _albumDoc(albumId)
        .update({'updatedAt': FieldValue.serverTimestamp()});

    if (originalPhotoId != null && originalPhotoId.isNotEmpty) {
      await clearEditingForTarget(
        albumId: albumId,
        originalPhotoId: originalPhotoId,
        photoId: originalPhotoId,
      );
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
    final ref = _editedCol(albumId).doc(editedId);

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

    await _albumDoc(albumId)
        .update({'updatedAt': FieldValue.serverTimestamp()});

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
    final q = _editedCol(albumId).orderBy('createdAt', descending: true);
    return q.snapshots().map(
          (qs) => qs.docs.map((d) => EditedPhoto.fromDoc(d.id, d.data())).toList(),
        );
  }

  Future<void> deleteEditedPhoto({
    required String? albumId,
    required String editedId,
  }) async {
    if (albumId == null) throw ArgumentError('albumId is null');

    final ref = _editedCol(albumId).doc(editedId);
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
  final List<String> likedBy;

  Photo({required this.id, required this.url, this.likedBy = const []});

  factory Photo.fromMap(String id, Map<String, dynamic> m) {
    return Photo(
      id: id,
      url: (m['url'] as String?) ?? '',
      likedBy:
          (m['likedBy'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  Map<String, dynamic> toMap() {
    return {'url': url, 'likedBy': likedBy};
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
  final String? uid;
  final Timestamp? startedAt; // 가장 먼저 들어간 시각
  final String? userDisplayName;

  EditingInfo({
    required this.albumId,
    required this.photoUrl,
    this.photoId,
    this.source,
    this.editedId,
    this.originalPhotoId,
    this.status,
    this.updatedAt,
    this.uid,
    this.startedAt,
    this.userDisplayName,
  });

  factory EditingInfo.fromDoc(
    String albumId,
    Map<String, dynamic> d, {
    String? docId,
  }) {
    return EditingInfo(
      albumId: albumId,
      photoId: d['photoId'] as String?,
      photoUrl: (d['photoUrl'] ?? '') as String,
      source: d['source'] as String?,
      editedId: d['editedId'] as String?,
      originalPhotoId: d['originalPhotoId'] as String?,
      status: d['status'] as String?,
      updatedAt: d['updatedAt'] as Timestamp?,
      uid: (d['uid'] as String?) ?? docId,
      startedAt: d['startedAt'] as Timestamp?,
      userDisplayName: d['userDisplayName'] as String?,
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