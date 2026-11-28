/**
 * Pulse relay.
 *
 * Polymarket's relayer deploys Deposit Wallets and executes their approval
 * batches gas-free, but only for requests signed with Builder API
 * credentials. Those credentials are a server secret, so the Pulse app sends
 * these calls here instead: this worker checks the caller is a signed-in
 * Pulse user (a valid Privy access token), allows only the few operations the
 * app needs, adds the builder headers and forwards to the relayer.
 *
 * It never holds user keys and cannot move funds: a `WALLET` batch only
 * executes with the wallet owner's own signature, which the app produces on
 * the device.
 */
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { builderHeaders } from './hmac';

export interface Env {
  POLYMARKET_BUILDER_API_KEY: string;
  POLYMARKET_BUILDER_SECRET: string;
  POLYMARKET_BUILDER_PASSPHRASE: string;
  PRIVY_APP_ID: string;
  RELAYER_URL: string;
}

export const DEPOSIT_WALLET_FACTORY = '0x00000000000fb5c9adea0298d729a0cb3823cc07';

/** Relayer paths the app may call, and how. */
const ROUTES: Record<string, 'GET' | 'POST'> = {
  '/deployed': 'GET',
  '/v1/account/transactions/params': 'GET',
  '/transaction': 'GET',
  '/submit': 'POST',
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === '/health') return json({ ok: true });
    if (!url.pathname.startsWith('/relayer/')) return json({ error: 'not found' }, 404);

    const relayerPath = url.pathname.slice('/relayer'.length);
    const method = ROUTES[relayerPath];
    if (!method) return json({ error: 'not found' }, 404);
    if (request.method !== method) return json({ error: 'method not allowed' }, 405);

    if (!env.POLYMARKET_BUILDER_API_KEY || !env.POLYMARKET_BUILDER_SECRET || !env.POLYMARKET_BUILDER_PASSPHRASE) {
      return json({ error: 'relay is not configured' }, 503);
    }

    const user = await authenticate(request, env);
    if (!user) return json({ error: 'unauthorized' }, 401);

    let body: string | undefined;
    if (method === 'POST') {
      body = await request.text();
      const problem = validateSubmit(body);
      if (problem) return json({ error: problem }, 400);
      if (!allow(user)) return json({ error: 'too many requests' }, 429);
    }

    const headers = await builderHeaders(
      {
        key: env.POLYMARKET_BUILDER_API_KEY,
        secret: env.POLYMARKET_BUILDER_SECRET,
        passphrase: env.POLYMARKET_BUILDER_PASSPHRASE,
      },
      method,
      relayerPath,
      body,
    );

    const upstream = await fetch(`${env.RELAYER_URL}${relayerPath}${url.search}`, {
      method,
      headers: { ...headers, ...(body !== undefined && { 'Content-Type': 'application/json' }) },
      body,
    });

    return new Response(upstream.body, {
      status: upstream.status,
      headers: { 'Content-Type': upstream.headers.get('Content-Type') ?? 'application/json' },
    });
  },
};

// MARK: Auth

let jwks: ReturnType<typeof createRemoteJWKSet> | undefined;

/** Returns the Privy user id when the bearer token is a valid access token for this app. */
async function authenticate(request: Request, env: Env): Promise<string | undefined> {
  const header = request.headers.get('Authorization') ?? '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (!token) return undefined;

  jwks ??= createRemoteJWKSet(
    new URL(`https://auth.privy.io/api/v1/apps/${env.PRIVY_APP_ID}/jwks.json`),
  );
  try {
    const { payload } = await jwtVerify(token, jwks, { issuer: 'privy.io', audience: env.PRIVY_APP_ID });
    return typeof payload.sub === 'string' ? payload.sub : undefined;
  } catch {
    return undefined;
  }
}

// MARK: Validation

/**
 * Only Deposit Wallet deployment and Deposit Wallet batches, both addressed
 * to the Deposit Wallet factory. Anything else the builder key could sign is
 * refused, so a leaked app token cannot use this relay for other actions.
 */
export function validateSubmit(body: string): string | undefined {
  let parsed: unknown;
  try {
    parsed = JSON.parse(body);
  } catch {
    return 'body must be JSON';
  }
  if (typeof parsed !== 'object' || parsed === null) return 'body must be an object';
  const request = parsed as Record<string, unknown>;

  if (request.type !== 'WALLET-CREATE' && request.type !== 'WALLET') return 'unsupported transaction type';
  if (typeof request.to !== 'string' || request.to.toLowerCase() !== DEPOSIT_WALLET_FACTORY) {
    return 'transactions must target the Deposit Wallet factory';
  }
  if (typeof request.from !== 'string' || !/^0x[0-9a-fA-F]{40}$/.test(request.from)) return 'invalid from address';
  if (request.type === 'WALLET') {
    const params = request.depositWalletParams as Record<string, unknown> | undefined;
    if (!params || !Array.isArray(params.calls) || params.calls.length === 0) return 'missing batch calls';
    if (typeof request.signature !== 'string') return 'missing owner signature';
  }
  return undefined;
}

// MARK: Rate limit

/**
 * Best effort, per worker instance: at most 20 writes a minute per user.
 * Enough for wallet setup (a deploy and one approval batch); a determined
 * abuser across instances would need Cloudflare's rate-limiting rules.
 */
const recent = new Map<string, number[]>();

export function allow(user: string, now: number = Date.now()): boolean {
  const windowStart = now - 60_000;
  const hits = (recent.get(user) ?? []).filter((t) => t > windowStart);
  if (hits.length >= 20) {
    recent.set(user, hits);
    return false;
  }
  hits.push(now);
  recent.set(user, hits);
  return true;
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), { status, headers: { 'Content-Type': 'application/json' } });
}
