// lib/services/shared_album_service.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

// [참고] Firestore 구조(요지)
// albums/{albumId}
//   - title, ownerUid, memberUids[], photoCount, coverPhotoUrl, createdAt, updatedAt
//   photos/{photoId}
//     - url, storagePath, uploaderUid, createdAt
//   editing/{uid}
//     - uid, photoId?, photoUrl, source('original'|'edited'), editedId?, originalPhotoId?, updatedAt
//   edited/{editedId}
//     - url, storagePath, originalPhotoId?, editorUid, createdAt, updatedAt, isEditing(bool), editingUid?, editingStartedAt?
//
// Storage 예시(권장):
// albums/{albumId}/original/{file}.jpg|png...
// albums/{albumId}/edited/{photoId}/{millis}.png   // [변경] 버전 경로

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

    // editing, edited 삭제 (+ Storage 정리)
    final editing = await albumRef.collection('editing').get();
    for (final d in editing.docs) {
      await d.reference.delete();
    }
    final edited = await albumRef.collection('edited').get();
    for (final d in edited.docs) {
      // [변경] edited 스토리지 잔여 파일 정리(가능하면)
      final data = d.data();
      final editedStoragePath = data['storagePath'] as String?;
      if (editedStoragePath != null) {
        try {
          await _storage.ref(editedStoragePath).delete();
        } catch (_) {}
      }
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
      final storagePath =
          'albums/$albumId/original/$fileName'; // [변경] original 하위로 안내(권장)

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

  // ===== 내부: edited 잠금/해제 =====
  // (동시 편집 허용 정책으로, 아래 락 API는 선택적/수동 사용만 가능)
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

    // 동시 편집 허용: 자동 락 사용 안 함

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

    // 동시 편집 허용이므로 락 해제는 선택적
    if (editedId != null) {
      try {
        await _unlockEdited(albumId: albumId, editedId: editedId);
      } catch (_) {}
    }
  }

  // [추가] 특정 이미지 URL로 editing/* 정리 (정밀 타깃팅)
  Future<void> clearEditingByUrl({
    required String albumId,
    required String photoUrl,
  }) async {
    final col = _fs.collection('albums').doc(albumId).collection('editing');
    final qs = await col.where('photoUrl', isEqualTo: photoUrl).get();
    for (final d in qs.docs) {
      try {
        await d.reference.delete();
      } catch (_) {}
    }
  }

  // 대상(editedId 또는 originalPhotoId 또는 photoId)으로 "모든 편집 세션" 정리
  // 저장 시 모든 멤버 화면을 동기화하려면 이 API를 사용
  Future<void> clearEditingForTarget({
    required String albumId,
    String? editedId,        // 재편집(편집본) 저장일 때
    String? originalPhotoId, // 원본에서 시작한 저장일 때
    String? photoId,         // photoId 기준 정리
  }) async {
    final col = _fs.collection('albums').doc(albumId).collection('editing');

    // editedId 기준으로 모두 삭제
    if (editedId != null && editedId.isNotEmpty) {
      final qs = await col.where('editedId', isEqualTo: editedId).get();
      for (final d in qs.docs) {
        try {
          await d.reference.delete();
        } catch (_) {}
      }
      // 편집본 락도 해제(선택)
      try {
        await _unlockEdited(albumId: albumId, editedId: editedId);
      } catch (_) {}
    }

    // originalPhotoId 기준으로 모두 삭제 (원본 편집 저장 케이스)
    if (originalPhotoId != null && originalPhotoId.isNotEmpty) {
      final qs = await col.where('originalPhotoId', isEqualTo: originalPhotoId).get();
      for (final d in qs.docs) {
        try {
          await d.reference.delete();
        } catch (_) {}
      }
    }

    // photoId 기준 정리
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

  /// 버전 경로 생성 유틸(공개): albums/{albumId}/edited/{photoId}/{millis}.{ext}
  String generateEditedStoragePath({
    required String albumId,
    required String photoId,
    String ext = 'png',
  }) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return 'albums/$albumId/edited/$photoId/$ts.$ext';
  }

  /// 원본에서 새 편집본 생성 (원본 photoId 추적)
  Future<void> saveEditedPhotoFromUrl({
    required String albumId,
    required String editorUid,
    required String originalPhotoId,
    required String editedUrl,
    String? storagePath,
  }) async {
    final editedRef =
        _fs.collection('albums').doc(albumId).collection('edited').doc();

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

    // [변경] 저장 시 "해당 사진"을 편집 중이던 모든 세션 일괄 제거 (전원 화면 동기화)
    await clearEditingForTarget(
      albumId: albumId,
      originalPhotoId: originalPhotoId,
      photoId: originalPhotoId,
    );
  }

  /// (호환) 원본 추적 없이 편집본 생성
  Future<void> saveEditedPhoto({
    required String albumId,
    required String url,
    required String editorUid,
    String? originalPhotoId,
    String? storagePath,
  }) async {
    final ref =
        _fs.collection('albums').doc(albumId).collection('edited').doc();
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

    // [변경] 원본 id가 있으면 해당 타깃의 모든 세션 제거,
    //        없으면 URL 기준으로라도 정리하여 전원 화면 동기화
    if (originalPhotoId != null && originalPhotoId.isNotEmpty) {
      await clearEditingForTarget(
        albumId: albumId,
        originalPhotoId: originalPhotoId,
        photoId: originalPhotoId,
      );
    } else {
      // [추가] 원본 추적이 없을 때는 photoUrl로 세션 정리
      try {
        await clearEditingByUrl(albumId: albumId, photoUrl: url);
      } catch (_) {}
    }
  }

  /// 편집본 덮어쓰기: "새 파일"로 업로드한 URL/경로로 문서 교체 + (선택) 이전 파일 삭제
  Future<void> saveEditedPhotoOverwrite({
    required String albumId,
    required String editedId,
    required String newUrl,
    required String editorUid,
    String? newStoragePath,
    bool deleteOld = true,
  }) async {
    final ref =
        _fs.collection('albums').doc(albumId).collection('edited').doc(editedId);

    // 이전 storagePath 읽기
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

    // 이전 파일 정리(선택)
    if (deleteOld &&
        oldStoragePath != null &&
        oldStoragePath.isNotEmpty &&
        oldStoragePath != newStoragePath) {
      try {
        await _storage.ref(oldStoragePath).delete();
      } catch (_) {}
    }

    // [변경] 덮어쓰기 저장 시, 이 편집본을 편집 중이던 모든 세션 제거 (전원 동기화)
    await clearEditingForTarget(
      albumId: albumId,
      editedId: editedId,
    );
  }

  Stream<List<EditedPhoto>> watchEditedPhotos(String albumId) {
    // 정책에 따라 isEditing 필터는 유지/제거 선택 가능
    final q = _fs
        .collection('albums')
        .doc(albumId)
        .collection('edited')
        // .where('isEditing', isEqualTo: false) // 필요 시 활성화
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

    // 삭제 전 문서의 storagePath 읽어서 파일 삭제
    final ref =
        _fs.collection('albums').doc(albumId).collection('edited').doc(editedId);
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
  final String? storagePath;          // [변경] 추가
  final String? originalPhotoId;
  final String editorUid;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  EditedPhoto({
    required this.id,
    required this.url,
    required this.editorUid,
    this.storagePath,                 // [변경]
    this.originalPhotoId,
    this.createdAt,
    this.updatedAt,
  });

  factory EditedPhoto.fromDoc(String id, Map<String, dynamic> d) {
    return EditedPhoto(
      id: id,
      url: (d['url'] ?? '') as String,
      storagePath: d['storagePath'] as String?,     // [변경]
      originalPhotoId: d['originalPhotoId'] as String?,
      editorUid: (d['editorUid'] ?? '') as String,
      createdAt: d['createdAt'] as Timestamp?,
      updatedAt: d['updatedAt'] as Timestamp?,
    );
  }
}