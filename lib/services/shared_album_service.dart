// lib/services/shared_album_service.dart
import 'dart:io';
import 'dart:async'; // [추가] Timer, StreamSubscription

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

import 'package:http/http.dart' as http;                 // [추가]
import 'package:path_provider/path_provider.dart';        // [추가]
import 'package:image_gallery_saver/image_gallery_saver.dart';     // [추가]
import 'package:permission_handler/permission_handler.dart'; // [추가]
import 'package:path/path.dart' as p;                     // [추가]
import 'dart:typed_data';


// [추가] 클래스 밖(top-level)에 선언: ops 커서(초기 캐치업 + 꼬리 스트림용)
class OpsCursor {
  final Timestamp? createdAt;
  final String? docId;
  const OpsCursor({this.createdAt, this.docId});
}

/// Firestore 구조(요지, 경로 분리 적용)
/// albums/{albumId}
///   - title, ownerUid, memberUids[], photoCount, coverPhotoUrl, createdAt, updatedAt
/// photos/{photoId}
///   - url, storagePath, uploaderUid, createdAt, likedBy[]
/// edited/{editedId}
///   - url, storagePath, originalPhotoId?, editorUid, createdAt, updatedAt,
///     isEditing, editingUid, editingStartedAt,
///     lastCommitUid, lastCommitAt, saveToken,
///     **rootPhotoId**   // [추가][root] 최상위 원본(항상 photos/*의 id)
///
/// 편집 세션 (유저별)
///   editing_by_user/{uid}
///     - uid, **photoId(rootPhotoId로 고정)**, photoUrl, source('original'|'edited'),
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

  // ✅ Functions 리전 고정 (index.js와 동일)
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  // ---------- 공통 보장 유틸 ----------
  Future<User> _ensureSignedIn() async {
    final auth = FirebaseAuth.instance;
    var u = auth.currentUser;
    if (u == null) {
      u = (await auth.signInAnonymously()).user!;
    }
    // 권한/클레임 최신화
    await u.getIdToken(true);
    return u;
  }

  Future<void> _ensureAppCheckReady() async {
    try {
      await FirebaseAppCheck.instance.getToken(true);
    } catch (_) {
      // 아주 짧게 한 번 더
      await Future.delayed(const Duration(milliseconds: 200));
      await FirebaseAppCheck.instance.getToken(true);
    }
  }

  Future<void> _ensureReady() async {
    await _ensureSignedIn();
    await _ensureAppCheckReady();
  }
  // -----------------------------------

  // -----------------------------
  // [추가][root] 루트 ID 해석 유틸
  // -----------------------------
  /// 항상 **최상위 원본 photos/* 의 id** 를 반환.
  /// - original을 편집: originalPhotoId 또는 photoId 자체가 root
  /// - edited를 재편집: edited/{editedId}.originalPhotoId 를 root로 사용
  Future<String> _resolveRootPhotoId({
    required String albumId,
    String? photoId,          // 원본 편집 진입 시 전달되기도 함
    String? originalPhotoId,  // 원본 id가 이미 있으면 최우선
    String? editedId,         // 재편집 진입 시 전달
  }) async {
    // 1) 명시 originalPhotoId가 있으면 그것이 곧 root
    if (originalPhotoId != null && originalPhotoId.isNotEmpty) {
      return originalPhotoId;
    }

    // 2) 재편집: edited 문서에서 originalPhotoId를 가져와 root로 사용
    if (editedId != null && editedId.isNotEmpty) {
      try {
        final snap = await _editedCol(albumId).doc(editedId).get();
        final d = snap.data();
        final opid = d?['originalPhotoId'] as String?;
        if (opid != null && opid.isNotEmpty) return opid;
      } catch (_) {}
    }

    // 3) 원본 편집: 전달된 photoId가 원본이므로 그것을 root로
    if (photoId != null && photoId.isNotEmpty) {
      return photoId;
    }

    throw StateError('[root] rootPhotoId를 해석할 수 없습니다.');
  }

  // ====== Cloud Function 호출 래퍼 (enqueueOp) ======
  /// 실시간 편집 OP 전송
  /// - 서버(Functions)에서 Firestore albums/{albumId}/ops 에 적재됨
  /// - 클라에서는 ops 컬렉션을 **rootPhotoId** 기준으로 구독
  Future<void> sendEditOp({
    required String albumId,
    String? photoId,          // (원본 또는 미지정)
    String? originalPhotoId,  // (있으면 우선)
    String? editedId,         // (재편집일 수 있음)
    required Map<String, dynamic> op, // {type, data, by}
  }) async {
    await _ensureReady();

    // [변경][root] 항상 rootPhotoId로 통일하여 발행
    final rootPhotoId = await _resolveRootPhotoId(
      albumId: albumId,
      photoId: photoId,
      originalPhotoId: originalPhotoId,
      editedId: editedId,
    );

    // [추가] op 메타 보강: 중복 방지/추적용
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final opId = '${uid}_${DateTime.now().microsecondsSinceEpoch}_${_rand()}';
    final enriched = {
      'opId': opId,         // [추가]
      'editorUid': uid,     // [추가]
      ...op,
    };

    final callable = _functions.httpsCallable(
      'enqueueOp',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
    );

    Future<void> _call() async {
      // [변경][root] photoId → 항상 root를 보냄
      await callable.call({'albumId': albumId, 'photoId': rootPhotoId, 'op': enriched});
    }

    try {
      await _call();
    } on FirebaseFunctionsException catch (e) {
      // 인증 문제 → 토큰 리프레시 후 재시도
      final retryableAuth = e.code == 'unauthenticated';
      // 네트워크/일시 장애 → 재시도
      final retryableNet =
          e.code == 'deadline-exceeded' || e.code == 'unavailable';

      if (retryableAuth || retryableNet) {
        await FirebaseAuth.instance.currentUser?.getIdToken(true);
        await FirebaseAppCheck.instance.getToken(true);
        await _call();
        return;
      }
      rethrow;
    }
  }

  // ===== 편집 이벤트(ops) 실시간 구독 =====
  /// 같은 **rootPhotoId** 에 대한 OP를 createdAt → docId 순으로 정렬
  Stream<List<Map<String, dynamic>>> watchEditOps({
    required String albumId,
    required String photoId, // [주의] 여기에는 **rootPhotoId** 를 넣어야 함
  }) {
    final q = _albumDoc(albumId)
        .collection('ops')
        .where('photoId', isEqualTo: photoId)
        .orderBy('createdAt', descending: false) // 시간순 정렬
        .orderBy(FieldPath.documentId); // 동시간 충돌 방지

    // [변경] 메타데이터 변경 포함(오프라인→온라인 재동기화 대응)
    return q.snapshots(includeMetadataChanges: true).map(
      (qs) => qs.docs
          .map((d) => {
                'id': d.id, // 클라 dedupe에 유용
                ...d.data(),
              })
          .toList(),
    );
  }

  // === ops 정리 유틸 ===

  /// 현재 사진을 편집 중인 active 편집자 수(단발성)
  Future<int> fetchActiveEditorCountForPhoto({
    required String albumId,
    required String photoId, // [주의] rootPhotoId로 호출 권장
  }) async {
    final qs = await _editingByUserCol(albumId)
        .where('status', isEqualTo: 'active')
        .where('photoId', isEqualTo: photoId)
        .limit(50)
        .get();
    return qs.docs.length;
  }

  /// 특정 사진의 ops 전부 삭제(배치로 안전하게)
  Future<void> cleanupOpsForPhoto({
    required String albumId,
    required String photoId, // [주의] rootPhotoId로 호출
    int batchSize = 400,
  }) async {
    final col = _albumDoc(albumId).collection('ops');
    Query<Map<String, dynamic>> q =
        col.where('photoId', isEqualTo: photoId).limit(batchSize);

    while (true) {
      final qs = await q.get();
      if (qs.docs.isEmpty) break;

      final batch = _fs.batch();
      for (final d in qs.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (qs.docs.length < batchSize) break; // 더 이상 없음
    }
  }

  /// active 편집자가 없을 때에만 ops 비우기(경합 안전)
  Future<void> tryCleanupOpsIfNoEditors({
    required String albumId,
    required String photoId, // [주의] rootPhotoId로 호출
  }) async {
    final cnt = await fetchActiveEditorCountForPhoto(
      albumId: albumId,
      photoId: photoId,
    );
    if (cnt == 0) {
      await cleanupOpsForPhoto(albumId: albumId, photoId: photoId);
    }
  }

  // ====== ⬇⬇⬇ ops 캐치업/꼬리 스트림 (null-safe) [추가/변경] ⬇⬇⬇ ======

  // [추가] ops 초기 캐치업(커서 이후만 정렬 적용)
  Future<List<Map<String, dynamic>>> fetchEditOpsCatchup({
    required String albumId,
    required String photoId, // [주의] rootPhotoId
    OpsCursor? cursor,
  }) async {
    final col = _albumDoc(albumId).collection('ops');

    Query<Map<String, dynamic>> q = col
        .where('photoId', isEqualTo: photoId)
        .orderBy('createdAt', descending: false)
        .orderBy(FieldPath.documentId, descending: false);

    if (cursor?.createdAt != null) {
      q = q.where('createdAt', isGreaterThanOrEqualTo: cursor!.createdAt);
    }

    final qs = await q.get();
    final List<Map<String, dynamic>> out = [];

    for (final d in qs.docs) {
      final m = d.data();
      if (m == null) continue;

      final ts = m['createdAt'] as Timestamp?;
      final id = d.id;

      bool pass = (cursor == null || cursor.createdAt == null);
      if (!pass && ts != null) {
        final curMs = cursor!.createdAt!.millisecondsSinceEpoch;
        final tsMs = ts.millisecondsSinceEpoch;
        pass = tsMs > curMs ||
            (tsMs == curMs && id.compareTo(cursor.docId ?? '') > 0);
      }

      if (pass) out.add({'id': id, ...m});
    }

    out.sort((a, b) {
      final ta = (a['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      final tb = (b['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      if (ta != tb) return ta.compareTo(tb);
      return (a['id'] as String).compareTo(b['id'] as String);
    });

    return out;
  }

  // [추가] ops 꼬리 스트림(커서 '초과'만 흘려보냄)
  Stream<List<Map<String, dynamic>>> watchEditOpsTail({
    required String albumId,
    required String photoId, // [주의] rootPhotoId
    required OpsCursor cursor,
  }) {
    final q = _albumDoc(albumId)
        .collection('ops')
        .where('photoId', isEqualTo: photoId)
        .orderBy('createdAt', descending: false)
        .orderBy(FieldPath.documentId, descending: false);

    // [변경] 메타데이터 변경 포함(오프라인→온라인 재동기화 대응)
    return q.snapshots(includeMetadataChanges: true).map((qs) {
      final List<Map<String, dynamic>> added = [];

      for (final c in qs.docChanges) {
        if (c.type != DocumentChangeType.added) continue;

        final m = c.doc.data();
        if (m == null) continue;

        final ts = m['createdAt'] as Timestamp?;
        final id = c.doc.id;

        bool pass = (cursor.createdAt == null);
        if (!pass && ts != null) {
          final curMs = cursor.createdAt!.millisecondsSinceEpoch;
          final tsMs = ts.millisecondsSinceEpoch;
          pass = tsMs > curMs ||
              (tsMs == curMs && id.compareTo(cursor.docId ?? '') > 0);
        }

        if (pass) added.add({'id': id, ...m});
      }

      added.sort((a, b) {
        final ta = (a['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        final tb = (b['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        if (ta != tb) return ta.compareTo(tb);
        return (a['id'] as String).compareTo(b['id'] as String);
      });

      return added;
    });
  }

  // ====== ↑↑↑ ops 캐치업/꼬리 스트림 (null-safe) [추가/변경] ↑↑↑ ======

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
      final single = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
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
    final col = _photosCol(albumId).orderBy('createdAt', descending: true);
    return col.snapshots().map(
      (qs) => qs.docs.map((d) => Photo.fromMap(d.id, d.data())).toList(),
    );
  }

Future<bool> _ensureSavePermission() async {
  if (Platform.isAndroid) {
    // Android 13+: photos, 12↓: storage
    final photos = await Permission.photos.request();
    final storage = await Permission.storage.request();
    return photos.isGranted || storage.isGranted;
  } else if (Platform.isIOS) {
    final addOnly = await Permission.photosAddOnly.request();
    if (addOnly.isGranted) return true;
    final photos = await Permission.photos.request();
    return photos.isGranted;
  }
  return true; // 기타 플랫폼
}

  // ======================= [추가] 사진 다운로드 저장 ========================
Future<void> downloadPhotoToDevice({
  required String url,
  String? fileName,
}) async {
  // 권한 요청
  final ok = await _ensureSavePermission();
  if (!ok) {
    throw '저장 권한이 거부되었습니다. 설정에서 사진/미디어 권한을 허용해주세요.';
  }

  // 파일명/확장자 추출
  final uri = Uri.parse(url);
  final urlName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null;
  final extFromUrl = _extFromPath(urlName ?? '') ?? 'png';
  final baseName = (fileName ?? urlName ?? 'SharedAlbum_${DateTime.now().millisecondsSinceEpoch}')
      .replaceAll(RegExp(r'[^\w\.\-]'), '_');
  final finalNameNoExt = p.basenameWithoutExtension(baseName);

  // 바이트 다운로드
  final resp = await http.get(uri);
  if (resp.statusCode != 200) {
    throw '이미지 다운로드 실패 (${resp.statusCode})';
  }
  final bytes = Uint8List.fromList(resp.bodyBytes);

  // 갤러리에 저장
  final result = await ImageGallerySaver.saveImage(
    bytes,
    name: '${finalNameNoExt}_${DateTime.now().millisecondsSinceEpoch}',
  );

  final success = (result is Map) && (result['isSuccess'] == true);
  if (!success) {
    // 폴백: 파일로 저장 후 다시 시도
    final tempDir = await getTemporaryDirectory();
    final tempPath = p.join(tempDir.path, '$finalNameNoExt.$extFromUrl');
    final f = File(tempPath);
    await f.writeAsBytes(bytes);
    final result2 = await ImageGallerySaver.saveFile(f.path);
    final success2 = (result2 is Map) && (result2['isSuccess'] == true);
    if (!success2) throw '갤러리 저장에 실패했어요.';
  }
}

  Future<void> toggleLike({
    required String uid,
    required String albumId,
    required String photoId,
    required bool like,
  }) async {
    final ref = _photosCol(albumId).doc(photoId);
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
    String? photoId,            // 원본일 수도 있음
    required String photoUrl,
    String source = 'original', // 'original' | 'edited'
    String? editedId,           // 재편집이면 전달됨
    String? originalPhotoId,    // 가능하면 전달
    String? userDisplayName,    // 추가: 이름 저장
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

    // [변경][root] 세션의 photoId는 항상 **rootPhotoId** 로 저장
    final rootPhotoId = await _resolveRootPhotoId(
      albumId: albumId,
      photoId: photoId,
      originalPhotoId: originalPhotoId,
      editedId: editedId,
    );

    await ref.set({
      'uid': uid,
      'photoId': rootPhotoId, // [중요][root]
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
    // [변경] 삭제 전 photoId 추출 → 마지막 편집자일 때 ops 정리 위해 필요
    String? photoId;
    try {
      final snap = await _editingByUserDoc(albumId, uid).get();
      final data = snap.data();
      photoId = (data?['photoId'] as String?) ??
          (data?['originalPhotoId'] as String?);
    } catch (_) {}

    await _editingByUserDoc(albumId, uid).delete();

    // [추가] 마지막 편집자면 ops 정리
    if (photoId != null && photoId.isNotEmpty) {
      try {
        await tryCleanupOpsIfNoEditors(albumId: albumId, photoId: photoId);
      } catch (_) {}
    }
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
    required String photoId, // [주의] rootPhotoId
  }) {
    final q = _editingByUserCol(albumId)
        .where('status', isEqualTo: 'active')
        .where('photoId', isEqualTo: photoId);
    return q.snapshots().map((qs) => qs.docs.length);
  }

  // 사진별 "편집 중 사용자들" 실시간(실제 작업 중만: active)
  Stream<List<EditingInfo>> watchEditorsOfPhotoRT({
    required String albumId,
    required String photoId, // [주의] rootPhotoId
  }) {
    final q = _editingByUserCol(albumId)
        .where('status', isEqualTo: 'active')
        .where('photoId', isEqualTo: photoId)
        .orderBy('updatedAt', descending: true)
        .limit(50);
    return q.snapshots().map(
      (qs) => qs.docs
          .map((d) => EditingInfo.fromDoc(albumId, d.data(), docId: d.id))
          .toList(),
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
    String photoId, // [주의] rootPhotoId
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
  /// - **photoId(=rootPhotoId)** > originalPhotoId > editedId 우선순위
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

  // [변경][root] 마지막 커밋 주체 기록 + **rootPhotoId 저장**
  Future<void> saveEditedPhotoFromUrl({
    required String albumId,
    required String editorUid,
    required String originalPhotoId, // 원본 id(=root)
    required String editedUrl,
    String? storagePath,
    String? saveToken,
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

      'lastCommitUid': editorUid,
      'lastCommitAt': FieldValue.serverTimestamp(),
      if (saveToken != null) 'saveToken': saveToken,

      'rootPhotoId': originalPhotoId, // [추가][root]
    });

    await clearEditingForTarget(
      albumId: albumId,
      originalPhotoId: originalPhotoId,
      photoId: originalPhotoId,
    );
  }

  // [변경][root] 마지막 커밋 주체 기록 + **rootPhotoId 저장**
  Future<void> saveEditedPhoto({
    required String albumId,
    required String url,
    required String editorUid,
    String? originalPhotoId,   // 있으면 root로 사용
    String? storagePath,
    String? saveToken,
  }) async {
    final ref = _editedCol(albumId).doc();

    // [추가][root] 저장 시에도 root 보장(없으면 에러)
    if (originalPhotoId == null || originalPhotoId.isEmpty) {
      throw ArgumentError('[root] saveEditedPhoto에는 originalPhotoId가 필요합니다.');
    }

    await ref.set({
      'url': url,
      'storagePath': storagePath,
      'originalPhotoId': originalPhotoId,
      'editorUid': editorUid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isEditing': false,
      'editingUid': null,
      'editingStartedAt': null,

      'lastCommitUid': editorUid,
      'lastCommitAt': FieldValue.serverTimestamp(),
      if (saveToken != null) 'saveToken': saveToken,

      'rootPhotoId': originalPhotoId, // [추가][root]
    });
    await _albumDoc(albumId)
        .update({'updatedAt': FieldValue.serverTimestamp()});

    await clearEditingForTarget(
      albumId: albumId,
      originalPhotoId: originalPhotoId,
      photoId: originalPhotoId,
    );
  }

  Future<void> ensureAuthAndAppCheckReady() => _ensureReady();

  Future<void> debugWhoAmI() async {
    // 1) 로그인/앱체크 토큰 확보
    final u = FirebaseAuth.instance.currentUser ??
        (await FirebaseAuth.instance.signInAnonymously()).user!;
    await u.getIdToken(true);
    await FirebaseAppCheck.instance.getToken(true);

    // 2) v2 콜러블 호출 (리전은 서버와 동일)
    final fns = FirebaseFunctions.instanceFor(region: 'us-central1');
    final callable = fns.httpsCallable('whoAmI');
    final res = await callable.call();

    // 3) 로그 확인
    // ignore: avoid_print
    print('whoAmI -> $res');
  }

  // [변경][root] 마지막 커밋 주체 기록 + **rootPhotoId 유지**
  Future<void> saveEditedPhotoOverwrite({
    required String albumId,
    required String editedId,
    required String newUrl,
    required String editorUid,
    String? newStoragePath,
    bool deleteOld = true,
    String? saveToken,
  }) async {
    final ref = _editedCol(albumId).doc(editedId);

    String? oldStoragePath;
    String? rootPhotoId; // [추가][root]
    try {
      final snap = await ref.get();
      final data = snap.data();
      oldStoragePath = data?['storagePath'] as String?;
      rootPhotoId = (data?['rootPhotoId'] as String?) ??
          (data?['originalPhotoId'] as String?); // 호환
    } catch (_) {}

    await ref.update({
      'url': newUrl,
      if (newStoragePath != null) 'storagePath': newStoragePath,
      'editorUid': editorUid,
      'isEditing': false,
      'editingUid': null,
      'editingStartedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),

      'lastCommitUid': editorUid,
      'lastCommitAt': FieldValue.serverTimestamp(),
      if (saveToken != null) 'saveToken': saveToken,

      if (rootPhotoId != null) 'rootPhotoId': rootPhotoId, // [추가][root]
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
  final String? photoId;          // [의미] rootPhotoId로 고정 저장
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
      photoId: d['photoId'] as String?, // [중요] rootPhotoId
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
  final String? rootPhotoId; // [추가][root]

  EditedPhoto({
    required this.id,
    required this.url,
    required this.editorUid,
    this.storagePath,
    this.originalPhotoId,
    this.createdAt,
    this.updatedAt,
    this.rootPhotoId,
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
      rootPhotoId: d['rootPhotoId'] as String?, // [추가][root]
    );
  }
}