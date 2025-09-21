const admin = require("firebase-admin");

// v2 import
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2/options");

// Admin 초기화
if (admin.apps.length === 0) {
  admin.initializeApp();
}

// 리전/인스턴스 전역 기본값
setGlobalOptions({
  region: "us-central1",
  maxInstances: 10,
  invoker: "public",
});

/**
 * 실시간 편집 OP 적재
 * Firestore 경로: albums/{albumId}/ops
 * 문서 필드: photoId, by, createdAt, type, data, op(원본)
 */
exports.enqueueOp = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }

  const albumId = request.data?.albumId;
  const photoId = request.data?.photoId;
  const op = request.data?.op; // { type, data }

  if (!albumId || !photoId || !op || !op.type) {
    throw new HttpsError(
      "invalid-argument",
      "albumId/photoId/op.type required"
    );
  }

  const db = admin.firestore();
  const opsCol = db.collection("albums").doc(albumId).collection("ops");

  await opsCol.add({
    photoId,
    by: uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    type: op.type,
    data: op.data ?? {},
    op,
  });

  return { ok: true };
});