// functions/index.js
const { onCall } = require('firebase-functions/v2/https');
const { setGlobalOptions } = require('firebase-functions/v2');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');
const { AccessToken } = require('livekit-server-sdk');

admin.initializeApp();

// 리전/인스턴스 옵션
setGlobalOptions({ region: 'us-central1', maxInstances: 10 });

// LiveKit 토큰 발급 (Callable)
exports.createLivekitToken = onCall(
  {
    region: 'us-central1',
    enforceAppCheck: true, // App Check 없으면 401
  },
  async (req) => {
    const uid = req.auth?.uid || null;
    const roomName = req.data?.room;
    const name = req.data?.name || '';

    logger.info('[createLivekitToken] start', { uid, roomName, name });
    if (!uid) throw new Error('unauthenticated');
    if (!roomName) throw new Error('invalid-argument: room required');

    // ✅ .env에서 읽어옴 (defineSecret / functions.config() 사용 안 함)
    const url = process.env.LK_URL;
    const apiKey = process.env.LK_KEY;
    const apiSecret = process.env.LK_API_SECRET;

    if (!url || !apiKey || !apiSecret) {
      logger.error('[createLivekitToken] missing env', {
        hasUrl: !!url, hasKey: !!apiKey, hasSecret: !!apiSecret,
      });
      throw new Error('failed-precondition: LiveKit config missing');
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
      throw new Error('internal: token failed');
    }
  }
);
