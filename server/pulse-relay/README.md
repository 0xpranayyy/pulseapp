# Pulse relay

A tiny Cloudflare Worker that keeps Pulse's **Polymarket Builder API
credentials** off the phone.

Polymarket's relayer deploys each new user's **Deposit Wallet** and sets its
trading approvals for free, but only for requests signed with Builder API
credentials. Anything shipped inside an app can be extracted, so those
credentials live here. The app sends wallet-setup calls to this worker, and
the worker:

1. checks the caller is a signed-in Pulse user (a valid Privy access token
   for this app),
2. allows only Deposit Wallet deployment and Deposit Wallet batches
   addressed to the Deposit Wallet factory,
3. adds the builder signature headers and forwards to
   `relayer-v2.polymarket.com`.

It holds no user keys and cannot move anyone's money: a wallet batch only
runs with the wallet owner's signature, which is made on the phone.

## Deploy (about 5 minutes)

You need a free Cloudflare account and Node 18+.

1. **Create Builder API credentials.** polymarket.com → Settings →
   Builders → API Keys → create. Copy the **API Key**, **Secret** and
   **Passphrase**. You will paste each one once, below, and nowhere else.

2. **Install and log in.**

   ```bash
   cd server/pulse-relay
   npm install
   npx wrangler login
   ```

3. **Store the three secrets** (each command prompts for the value):

   ```bash
   npx wrangler secret put POLYMARKET_BUILDER_API_KEY
   npx wrangler secret put POLYMARKET_BUILDER_SECRET
   npx wrangler secret put POLYMARKET_BUILDER_PASSPHRASE
   ```

4. **Deploy.**

   ```bash
   npx wrangler deploy
   ```

   Wrangler prints the worker's URL, like
   `https://pulse-relay.<your-subdomain>.workers.dev`.

5. **Point the app at it.** In `Config.xcconfig` set

   ```
   PULSE_RELAY_URL = https:/$()/pulse-relay.<your-subdomain>.workers.dev
   ```

   (`/$()/` is how an xcconfig writes `//`; a bare `//` starts a comment.)
   Rebuild the app.

Check it is up: open `https://pulse-relay.<your-subdomain>.workers.dev/health`
in a browser; it answers `{"ok":true}`.

## Never

- Never put the Builder secret or passphrase in `Config.xcconfig`,
  `Info.plist`, the repository, or a chat. Only `wrangler secret put`.
- If they leak, delete the key on polymarket.com and create a new one.

## Routes

| Route | Forwards to |
|---|---|
| `GET /relayer/deployed?address=&type=WALLET` | `/deployed` |
| `GET /relayer/v1/account/transactions/params?address=&type=WALLET` | same path |
| `GET /relayer/transaction?id=` | `/transaction` |
| `POST /relayer/submit` | `/submit` (only `WALLET-CREATE` and `WALLET` to the factory) |
| `GET /health` | — |

All `/relayer/*` routes require `Authorization: Bearer <Privy access token>`.

## Develop

```bash
npm test          # HMAC, validation and rate-limit tests
npx wrangler dev  # local server; put secrets in .dev.vars (gitignored)
```

## Hardening you may want later

- Use Cloudflare's rate-limiting rules for a hard per-user cap across
  instances; the in-worker limit is best effort.
- Bind `from` to the caller's own Privy wallet by looking the user up with
  Privy's server API (that needs the Privy app secret as another worker
  secret).
