import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// 앨범 & 사진 관리 서비스
/// Firestore: users/{uid}/albums/{albumId} (+ photos subcollection)
/// Storage: users/{uid}/albums/{albumId}/{file}.jpg/png
class SharedAlbumService {
  SharedAlbumService._();
  static final SharedAlbumService instance = SharedAlbumService._();

  final _fs = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _picker = ImagePicker();

  /// 내 앨범 목록 (실시간)
  Stream<List<Album>> watchAlbums(String uid) {
    final col = _fs
        .collection('users')
        .doc(uid)
        .collection('albums')
        .orderBy('createdAt', descending: true);

    return col.snapshots().map((qs) {
      return qs.docs.map((d) => Album.fromDoc(d.id, d.data())).toList();
    });
  }

  /// 앨범 생성
  Future<String> createAlbum({
    required String uid,
    required String title,
  }) async {
    final ref = _fs.collection('users').doc(uid).collection('albums').doc();
    await ref.set({
      'title': title,
      'photoCount': 0,
      'coverPhotoUrl': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// 앨범 이름 변경
  Future<void> renameAlbum({
    required String uid,
    required String albumId,
    required String newTitle,
  }) async {
    await _fs
        .collection('users')
        .doc(uid)
        .collection('albums')
        .doc(albumId)
        .update({'title': newTitle, 'updatedAt': FieldValue.serverTimestamp()});
  }

  /// 앨범 삭제 (사진 + 스토리지 포함)
  Future<void> deleteAlbum({
    required String uid,
    required String albumId,
  }) async {
    final albumRef = _fs
        .collection('users')
        .doc(uid)
        .collection('albums')
        .doc(albumId);
    final photosRef = albumRef.collection('photos');

    // 1) 모든 사진 문서와 스토리지 파일 삭제
    final photos = await photosRef.get();
    for (final doc in photos.docs) {
      final data = doc.data();
      final storagePath = data['storagePath'] as String?;
      if (storagePath != null) {
        try {
          await _storage.ref(storagePath).delete();
        } catch (_) {
          // 파일이 없을 수도 있으니 무시
        }
      }
      await doc.reference.delete();
    }

    // 2) 앨범 문서 삭제
    await albumRef.delete();

    // 3) Storage 폴더 정리 (잔여가 있을 수 있어 deleteIfExists 시도)
    try {
      final folderRef = _storage.ref('users/$uid/albums/$albumId');
      final list = await folderRef.listAll();
      for (final item in list.items) {
        await item.delete();
      }
    } catch (_) {}
  }

  /// 폰 갤러리에서 사진 추가(다중 선택 가능)
  /// - 스토리지 업로드 후 photos 하위 컬렉션에 메타 저장
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

    final albumRef = _fs
        .collection('users')
        .doc(uid)
        .collection('albums')
        .doc(albumId);
    final photosRef = albumRef.collection('photos');

    int added = 0;
    for (final x in picked) {
      final file = File(x.path);
      final ext = _extFromMime(x.mimeType) ?? _extFromPath(x.path) ?? 'jpg';
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${_rand()}.$ext';
      final storagePath = 'users/$uid/albums/$albumId/$fileName';

      // 1) Storage 업로드
      final task = await _storage.ref(storagePath).putFile(file);
      final url = await task.ref.getDownloadURL();

      // 2) Firestore photo 문서 추가
      await photosRef.add({
        'url': url,
        'storagePath': storagePath,
        'createdAt': FieldValue.serverTimestamp(),
      });
      added++;
    }

    // 3) coverPhoto 및 photoCount 갱신
    await _fs.runTransaction((tx) async {
      final snap = await tx.get(albumRef);
      final data = snap.data() ?? {};
      final current = (data['photoCount'] ?? 0) as int;
      final cover = data['coverPhotoUrl'];
      final needsCover = cover == null;

      tx.update(albumRef, {
        'photoCount': current + added,
        if (needsCover)
          // 가장 최근 추가한 사진을 cover로 쓰도록 다시 읽어서 최신 url 하나 가져옴
          'coverPhotoUrl':
              (await photosRef
                      .orderBy('createdAt', descending: true)
                      .limit(1)
                      .get())
                  .docs
                  .first
                  .data()['url'],
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// 사진 한 장 삭제
  Future<void> deletePhoto({
    required String uid,
    required String albumId,
    required String photoId,
  }) async {
    final photoRef = _fs
        .collection('users')
        .doc(uid)
        .collection('albums')
        .doc(albumId)
        .collection('photos')
        .doc(photoId);

    final snap = await photoRef.get();
    if (!snap.exists) return;
    final data = snap.data()!;
    final storagePath = data['storagePath'] as String?;

    // 1) 스토리지 파일 삭제
    if (storagePath != null) {
      try {
        await _storage.ref(storagePath).delete();
      } catch (_) {}
    }

    // 2) 문서 삭제
    await photoRef.delete();

    // 3) album 카운트/커버 갱신
    final albumRef = _fs
        .collection('users')
        .doc(uid)
        .collection('albums')
        .doc(albumId);

    await _fs.runTransaction((tx) async {
      final a = await tx.get(albumRef);
      final d = a.data() ?? {};
      final cnt = (d['photoCount'] ?? 0) as int;
      final newCnt = cnt > 0 ? cnt - 1 : 0;

      String? newCover;
      // 커버가 방금 지운 사진이었다면 최신 사진으로 교체
      if ((d['coverPhotoUrl'] as String?) == (data['url'] as String?)) {
        final latest = await albumRef
            .collection('photos')
            .orderBy('createdAt', descending: true)
            .limit(1)
            .get();
        newCover = latest.docs.isNotEmpty
            ? latest.docs.first.data()['url']
            : null;
      }

      tx.update(albumRef, {
        'photoCount': newCnt,
        'coverPhotoUrl': newCover,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// 특정 앨범의 사진들(실시간)
  Stream<List<Photo>> watchPhotos({
    required String uid,
    required String albumId,
  }) {
    final col = _fs
        .collection('users')
        .doc(uid)
        .collection('albums')
        .doc(albumId)
        .collection('photos')
        .orderBy('createdAt', descending: true);

    return col.snapshots().map((qs) {
      return qs.docs.map((d) => Photo.fromDoc(d.id, d.data())).toList();
    });
  }

  // ----------------- 유틸 -----------------
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
  final int photoCount;
  final String? coverPhotoUrl;
  final Timestamp? createdAt;

  Album({
    required this.id,
    required this.title,
    required this.photoCount,
    required this.coverPhotoUrl,
    required this.createdAt,
  });

  factory Album.fromDoc(String id, Map<String, dynamic> d) {
    return Album(
      id: id,
      title: d['title'] ?? '',
      photoCount: (d['photoCount'] ?? 0) as int,
      coverPhotoUrl: d['coverPhotoUrl'] as String?,
      createdAt: d['createdAt'] as Timestamp?,
    );
  }
}

class Photo {
  final String id;
  final String url;
  final String? storagePath;
  final Timestamp? createdAt;

  Photo({
    required this.id,
    required this.url,
    required this.storagePath,
    required this.createdAt,
  });

  factory Photo.fromDoc(String id, Map<String, dynamic> d) {
    return Photo(
      id: id,
      url: d['url'] ?? '',
      storagePath: d['storagePath'] as String?,
      createdAt: d['createdAt'] as Timestamp?,
    );
  }
}
