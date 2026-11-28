/**
 * Polymarket builder authentication headers.
 *
 * Same algorithm as `buildHmacSignature` in `@polymarket/client`:
 * `urlsafeBase64(HMAC-SHA256(base64Decode(secret), timestamp + METHOD + path + body))`,
 * where `path` excludes the query string and `body` is the exact string sent.
 */
export async function builderSignature(
  secret: string,
  timestamp: number,
  method: string,
  path: string,
  body?: string,
): Promise<string> {
  let message = `${timestamp}${method}${path}`;
  if (body !== undefined) message += body;

  const key = await crypto.subtle.importKey(
    'raw',
    base64ToBytes(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(message));
  return bytesToBase64(new Uint8Array(mac)).replace(/\+/g, '-').replace(/\//g, '_');
}

export async function builderHeaders(
  credentials: { key: string; secret: string; passphrase: string },
  method: string,
  path: string,
  body?: string,
  now: () => number = Date.now,
): Promise<Record<string, string>> {
  const timestamp = Math.floor(now() / 1000);
  return {
    POLY_BUILDER_API_KEY: credentials.key,
    POLY_BUILDER_PASSPHRASE: credentials.passphrase,
    POLY_BUILDER_SIGNATURE: await builderSignature(credentials.secret, timestamp, method, path, body),
    POLY_BUILDER_TIMESTAMP: `${timestamp}`,
  };
}

function base64ToBytes(value: string): Uint8Array {
  const clean = value.replace(/-/g, '+').replace(/_/g, '/').replace(/[^A-Za-z0-9+/=]/g, '');
  const binary = atob(clean);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}
