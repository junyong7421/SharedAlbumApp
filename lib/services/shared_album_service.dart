// lib/services/shared_album_service.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Firestore 구조
/// albums/{albumId}
///   - title, ownerUid, memberUids[], photoCount, coverPhotoUrl, createdAt, updatedAt
///   photos/{photoId}
///     - url, storagePath, uploaderUid, createdAt
///   editing/{uid}
///     - uid, photoId?, photoUrl, source('original'|'edited'), editedId?, originalPhotoId?, updatedAt
///   edited/{editedId}
///     - url, originalPhotoId?, editorUid, createdAt, updatedAt, isEditing(bool), editingUid?, editingStartedAt?
///
/// Storage: albums/{albumId}/{file}.jpg|png...
class SharedAlbumService {
  SharedAlbumService._();
  static final SharedAlbumService instance = SharedAlbumService._();

  final _fs = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _picker = ImagePicker();

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
    required String uid, // 시그니처 호환용
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

    // editing, edited 삭제
    final editing = await albumRef.collection('editing').get();
    for (final d in editing.docs) {
      await d.reference.delete();
    }
    final edited = await albumRef.collection('edited').get();
    for (final d in edited.docs) {
      await d.reference.delete();
    }

    // 앨범 삭제
    await albumRef.delete();

    // Storage 폴더 잔여 정리 (best effort)
    try {
      final folderRef = _storage.ref('albums/$albumId');
      final list = await folderRef.listAll();
      for (final item in list.items) {
        await item.delete();
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
      final storagePath = 'albums/$albumId/$fileName';

      final task = await _storage.ref(storagePath).putFile(file);
      final url = await task.ref.getDownloadURL();

      await photosRef.add({
        'url': url,
        'storagePath': storagePath,
        'uploaderUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
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
      (qs) => qs.docs.map((d) => Photo.fromDoc(d.id, d.data())).toList(),
    );
  }

  // ===== 내부: edited 잠금/해제 =====

  Future<void> _lockEdited({
    required String albumId,
    required String editedId,
    required String uid,
  }) async {
    final ref =
        _fs.collection('albums').doc(albumId).collection('edited').doc(editedId);
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
    final ref =
        _fs.collection('albums').doc(albumId).collection('edited').doc(editedId);
    await ref.update({
      'isEditing': false,
      'editingUid': null,
      'editingStartedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ===== 편집 상태 (editing/*) =====
  // 구버전/신버전 호출 모두 호환
  Future<void> setEditing({
    required String uid,
    required String albumId,

    // 구버전: 원본 사진 편집 시작 시 사용
    String? photoId,

    // 공통: 현재 화면에 보여줄 이미지 URL (원본/편집본 상관없이)
    required String photoUrl,

    // 신버전: 편집본에서 재편집 시작 시 사용
    String source = 'original', // 'original' | 'edited'
    String? editedId, // 편집본 문서 id
    String? originalPhotoId, // 원본 photoId (있으면 기록)
  }) async {
    final ref = _fs
        .collection('albums')
        .doc(albumId)
        .collection('editing')
        .doc(uid);

    await ref.set({
      'uid': uid,
      if (photoId != null) 'photoId': photoId,
      'photoUrl': photoUrl,
      'source': source,
      if (editedId != null) 'editedId': editedId,
      if (originalPhotoId != null) 'originalPhotoId': originalPhotoId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 편집본에서 시작이면 해당 edited 문서 잠금
    if (source == 'edited' && editedId != null) {
      await _lockEdited(albumId: albumId, editedId: editedId, uid: uid);
    }

    await _fs.collection('albums').doc(albumId).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> clearEditing({
    required String uid,
    required String albumId,
    String? editedId, // 재편집 취소 시 잠금 해제용
  }) async {
    final ref = _fs
        .collection('albums')
        .doc(albumId)
        .collection('editing')
        .doc(uid);
    await ref.delete();

    if (editedId != null) {
      try {
        await _unlockEdited(albumId: albumId, editedId: editedId);
      } catch (_) {}
    }
  }

  Stream<EditingInfo?> watchMyEditing({
    required String uid,
    required String albumId,
  }) {
    final ref = _fs
        .collection('albums')
        .doc(albumId)
        .collection('editing')
        .doc(uid);
    return ref.snapshots().map((ds) {
      if (!ds.exists) return null;
      return EditingInfo.fromDoc(albumId, ds.data()!);
    });
  }

  Stream<List<EditingInfo>> watchEditingForAlbum(String albumId) {
    final q = _fs
        .collection('albums')
        .doc(albumId)
        .collection('editing')
        .orderBy('updatedAt', descending: true);
    return q.snapshots().map(
      (qs) =>
          qs.docs.map((d) => EditingInfo.fromDoc(albumId, d.data())).toList(),
    );
  }

  // ===== 편집본 저장 (edited/*) =====

  /// 원본에서 새 편집본 생성 (원본 photoId 추적)
  Future<void> saveEditedPhotoFromUrl({
    required String albumId,
    required String editorUid,
    required String originalPhotoId,
    required String editedUrl,
  }) async {
    final editedRef =
        _fs.collection('albums').doc(albumId).collection('edited').doc();

    await editedRef.set({
      'url': editedUrl,
      'originalPhotoId': originalPhotoId,
      'editorUid': editorUid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isEditing': false,
      'editingUid': null,
      'editingStartedAt': null,
    });

    try {
      await clearEditing(uid: editorUid, albumId: albumId);
    } catch (_) {}
  }

  /// (호환) 원본 추적 없이 편집본 생성
  Future<void> saveEditedPhoto({
    required String albumId,
    required String url,
    required String editorUid,
    String? originalPhotoId,
  }) async {
    final ref =
        _fs.collection('albums').doc(albumId).collection('edited').doc();
    await ref.set({
      'url': url,
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
  }

  /// 편집본 덮어쓰기: 기존 edited/{editedId} 문서의 url만 교체
  Future<void> saveEditedPhotoOverwrite({
    required String albumId,
    required String editedId,
    required String newUrl,
    required String editorUid,
  }) async {
    final ref =
        _fs.collection('albums').doc(albumId).collection('edited').doc(editedId);

    await ref.update({
      'url': newUrl,
      'editorUid': editorUid,
      'isEditing': false,
      'editingUid': null,
      'editingStartedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _fs.collection('albums').doc(albumId).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 덮어쓰기 완료 후 편집중 해제(선택)
    try {
      await clearEditing(uid: editorUid, albumId: albumId);
    } catch (_) {}
  }

  Stream<List<EditedPhoto>> watchEditedPhotos(String albumId) {
    // 편집 중(isEditing==true)은 숨김
    final q = _fs
        .collection('albums')
        .doc(albumId)
        .collection('edited')
        .where('isEditing', isEqualTo: false)
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
    await _fs
        .collection('albums')
        .doc(albumId)
        .collection('edited')
        .doc(editedId)
        .delete();
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
  final String? storagePath;
  final String? uploaderUid;
  final Timestamp? createdAt;

  Photo({
    required this.id,
    required this.url,
    required this.storagePath,
    required this.uploaderUid,
    required this.createdAt,
  });

  factory Photo.fromDoc(String id, Map<String, dynamic> d) {
    return Photo(
      id: id,
      url: (d['url'] ?? '') as String,
      storagePath: d['storagePath'] as String?,
      uploaderUid: d['uploaderUid'] as String?,
      createdAt: d['createdAt'] as Timestamp?,
    );
  }
}

class EditingInfo {
  final String albumId;
  final String? photoId;
  final String photoUrl;
  final String? source; // 'original' | 'edited'
  final String? editedId; // 편집본 id
  final String? originalPhotoId; // 원본 photoId
  final Timestamp? updatedAt;

  EditingInfo({
    required this.albumId,
    required this.photoUrl,
    this.photoId,
    this.source,
    this.editedId,
    this.originalPhotoId,
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
      updatedAt: d['updatedAt'] as Timestamp?,
    );
  }
}

class EditedPhoto {
  final String id;
  final String url;
  final String? originalPhotoId; // ← null 허용 (덮어쓰기에도 안전)
  final String editorUid;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  EditedPhoto({
    required this.id,
    required this.url,
    required this.editorUid,
    this.originalPhotoId,
    this.createdAt,
    this.updatedAt,
  });

  factory EditedPhoto.fromDoc(String id, Map<String, dynamic> d) {
    return EditedPhoto(
      id: id,
      url: (d['url'] ?? '') as String,
      originalPhotoId: d['originalPhotoId'] as String?,
      editorUid: (d['editorUid'] ?? '') as String,
      createdAt: d['createdAt'] as Timestamp?,
      updatedAt: d['updatedAt'] as Timestamp?,
    );
  }
}