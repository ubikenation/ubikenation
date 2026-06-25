import crypto from 'node:crypto';

/**
 * ZEGOCLOUD token04 generator (standard algorithm) — issues a short-lived token a
 * client uses to authenticate into a voice-call room. Mirrors ZEGO's official
 * zego_server_assistant Node implementation.
 */
function makeNonce(): number {
  return Math.floor(Math.random() * (2 ** 31 - 1));
}

function aesEncrypt(plainText: string, key: string, iv: Buffer): Buffer {
  const keyBuf = Buffer.from(key);
  const algo =
    keyBuf.length === 16 ? 'aes-128-cbc' : keyBuf.length === 24 ? 'aes-192-cbc' : 'aes-256-cbc';
  const cipher = crypto.createCipheriv(algo, keyBuf, iv);
  cipher.setAutoPadding(true);
  return Buffer.concat([cipher.update(plainText, 'utf8'), cipher.final()]);
}

export function generateZegoToken(
  appId: number,
  userId: string,
  secret: string,
  effectiveTimeInSeconds: number,
  payload = '',
): string {
  const createTime = Math.floor(Date.now() / 1000);
  const tokenInfo = {
    app_id: appId,
    user_id: userId,
    nonce: makeNonce(),
    ctime: createTime,
    expire: createTime + effectiveTimeInSeconds,
    payload,
  };
  const plaintext = JSON.stringify(tokenInfo);
  const iv = crypto.randomBytes(16);
  const encrypted = aesEncrypt(plaintext, secret, iv);

  // pack: expire(int64 BE) | iv.len(int16 BE) | iv | encrypt.len(int16 BE) | encrypt
  const expireBuf = Buffer.alloc(8);
  expireBuf.writeBigInt64BE(BigInt(tokenInfo.expire));
  const ivLen = Buffer.alloc(2);
  ivLen.writeUInt16BE(iv.length);
  const encLen = Buffer.alloc(2);
  encLen.writeUInt16BE(encrypted.length);

  const body = Buffer.concat([expireBuf, ivLen, iv, encLen, encrypted]);
  return '04' + body.toString('base64');
}
