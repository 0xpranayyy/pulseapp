import { createHmac } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { builderHeaders, builderSignature } from '../src/hmac';
import { allow, validateSubmit } from '../src/index';

// A made-up secret in the URL-safe base64 alphabet Polymarket issues.
const secret = 'c2VjcmV0LWZvci10ZXN0cy1vbmx5LW5vdC1yZWFs_-A=';

function reference(timestamp: number, method: string, path: string, body?: string): string {
  const key = Buffer.from(secret.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
  return createHmac('sha256', key)
    .update(`${timestamp}${method}${path}${body ?? ''}`)
    .digest('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

describe('builder signature', () => {
  it('matches an independent HMAC-SHA256 over timestamp + method + path + body', async () => {
    const body = '{"type":"WALLET-CREATE","from":"0x7e5f4552091a69125d5dfcb7b8c2659029395bdf"}';
    expect(await builderSignature(secret, 1_700_000_000, 'POST', '/submit', body))
      .toBe(reference(1_700_000_000, 'POST', '/submit', body));
    expect(await builderSignature(secret, 1_700_000_000, 'GET', '/deployed'))
      .toBe(reference(1_700_000_000, 'GET', '/deployed'));
  });

  it('builds the four headers with a seconds timestamp', async () => {
    const headers = await builderHeaders({ key: 'k', secret, passphrase: 'p' }, 'GET', '/transaction', undefined, () => 1_700_000_123_456);
    expect(headers.POLY_BUILDER_TIMESTAMP).toBe('1700000123');
    expect(headers.POLY_BUILDER_API_KEY).toBe('k');
    expect(headers.POLY_BUILDER_PASSPHRASE).toBe('p');
    expect(headers.POLY_BUILDER_SIGNATURE).toBe(reference(1_700_000_123, 'GET', '/transaction'));
  });
});

describe('submit validation', () => {
  const factory = '0x00000000000Fb5C9ADea0298D729A0CB3823Cc07';
  const from = '0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf';

  it('accepts a deploy and a batch addressed to the factory', () => {
    expect(validateSubmit(JSON.stringify({ type: 'WALLET-CREATE', from, to: factory }))).toBeUndefined();
    expect(validateSubmit(JSON.stringify({
      type: 'WALLET', from, to: factory, signature: '0x00',
      depositWalletParams: { calls: [{ target: factory, value: '0', data: '0x' }] },
    }))).toBeUndefined();
  });

  it('refuses anything else', () => {
    expect(validateSubmit('nope')).toBeDefined();
    expect(validateSubmit(JSON.stringify({ type: 'SAFE', from, to: factory }))).toBeDefined();
    expect(validateSubmit(JSON.stringify({ type: 'WALLET-CREATE', from, to: from }))).toBeDefined();
    expect(validateSubmit(JSON.stringify({ type: 'WALLET', from, to: factory, depositWalletParams: { calls: [] } }))).toBeDefined();
  });
});

describe('rate limit', () => {
  it('allows 20 writes a minute per user', () => {
    const now = 10_000_000;
    for (let i = 0; i < 20; i += 1) expect(allow('did:privy:test', now + i)).toBe(true);
    expect(allow('did:privy:test', now + 21)).toBe(false);
    expect(allow('did:privy:other', now + 21)).toBe(true);
    expect(allow('did:privy:test', now + 61_000)).toBe(true);
  });
});
