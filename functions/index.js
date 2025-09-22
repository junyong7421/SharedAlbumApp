// functions/index.js
/*** [통합] 공통 import ***/
const admin = require('firebase-admin');
const { onCall, HttpsError } = require('firebase-functions/v2/https'); // **v2/https + HttpsError 통일**
const { setGlobalOptions } = require('firebase-functions/v2/options');  // **v2/options로 통일**
const logger = require('firebase-functions/logger');
const { AccessToken } = require('livekit-server-sdk');

/*** [안전 가드] Admin 초기화 ***/
if (admin.apps.length === 0) {
  admin.initializeApp(); // **중복 init 방지**
}

/*** [전역 옵션] 리전/인스턴스 통일 설정 (1회만) ***/
setGlobalOptions({
  region: 'us-central1',
  maxInstances: 10,
  // invoker: 'public', // **App Check를 쓰므로 보통 불필요. 필요하면 주석 해제**
});

/**
 * [유지 + 보강] 실시간 편집 OP 적재 (Callable)
 * Firestore 경로: albums/{albumId}/ops
 * 문서 필드: photoId, by, createdAt, type, data, op(원본)
 */
exports.enqueueOp = onCall(
  {
    region: 'us-central1',
    enforceAppCheck: true, // **[추가] App Check 강제**
  },
  async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Sign in required'); // **에러 타입 통일**
    }

    const albumId = request.data?.albumId;
    const photoId = request.data?.photoId;
    const op = request.data?.op; // { type, data }

    if (!albumId || !photoId || !op || !op.type) {
      throw new HttpsError('invalid-argument', 'albumId/photoId/op.type required');
    }

    const db = admin.firestore();
    const opsCol = db.collection('albums').doc(albumId).collection('ops');

    await opsCol.add({
      photoId,
      by: uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      type: op.type,
      data: op.data ?? {},
      op,
    });

    return { ok: true };
  }
);

/**
 * [유지] LiveKit 토큰 발급 (Callable)
 * .env 필요: LK_URL, LK_KEY, LK_API_SECRET
 */
exports.createLivekitToken = onCall(
  {
    region: 'us-central1',
    enforceAppCheck: true, // **App Check 강제 (401 방지)**
  },
  async (req) => {
    const uid = req.auth?.uid || null;
    const roomName = req.data?.room;
    const name = req.data?.name || '';

    logger.info('[createLivekitToken] start', { uid, roomName, name });
    if (!uid) throw new HttpsError('unauthenticated', 'Sign in required'); // **에러 타입 통일**
    if (!roomName) throw new HttpsError('invalid-argument', 'room required');

    // **환경변수 사용(defineSecret/functions.config() 미사용)**
    const url = process.env.LK_URL;
    const apiKey = process.env.LK_KEY;
    const apiSecret = process.env.LK_API_SECRET;

    if (!url || !apiKey || !apiSecret) {
      logger.error('[createLivekitToken] missing env', {
        hasUrl: !!url, hasKey: !!apiKey, hasSecret: !!apiSecret,
      });
      throw new HttpsError('failed-precondition', 'LiveKit config missing');
    }

    try {
      const at = new AccessToken(apiKey, apiSecret, {
        identity: uid,
        name: name || uid,
      });
      at.addGrant({
        roomJoin: true,
        room: roomName,
        canPublish: true,
        canSubscribe: true,
        canPublishData: true,
      });

      const token = await at.toJwt();
      logger.info('[createLivekitToken] success', {
        urlHost: url.split('://')[1],
        tokenLen: token.length,
      });
      return { url, token };
    } catch (e) {
      logger.error('[createLivekitToken] error', e);
      throw new HttpsError('internal', 'token failed');
    }
  }
);