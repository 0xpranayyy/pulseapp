# Polymarket integration map

Everything below was verified against live endpoints on **2026-11-27**, not
taken from memory. Where the official docs and the live API disagreed, the
live response won and the difference is noted.

Sources: <https://docs.polymarket.com> (the `.md` variants of each page) and
direct probes of each host.

---

## Hosts

| Surface | Base URL | Auth |
| --- | --- | --- |
| Gamma (discovery) | `https://gamma-api.polymarket.com` | none |
| CLOB (prices, orders) | `https://clob.polymarket.com` | L2 for private routes |
| Data API v2 | `https://data-api.polymarket.com` | none |
| Market stream | `wss://ws-subscriptions-clob.polymarket.com/ws/market` | none |
| User stream | `wss://ws-subscriptions-clob.polymarket.com/ws/user` | L2 |
| Relayer | `https://relayer-v2.polymarket.com` | **not integrated** |

---

## Three findings that shaped the code

### 1. Data API v1 is retired

`GET /positions` and `GET /activity` return **HTTP 410**:

```json
{"error":"Data API v1 has been retired","migration":"https://data-api.polymarket.com/v2/"}
```

v2 differs in three ways that break any v1 model:

* every response is wrapped in a `data` envelope, with `pagination` alongside;
* fields are `snake_case` (`proxy_wallet`), not `camelCase` (`proxyWallet`);
* paging uses an opaque `cursor`. Passing `offset` is now a **400**, even `offset=0`.

Implemented in `DataModels.swift` / `DataService`.

### 2. Gamma encodes arrays as JSON strings

`outcomes`, `outcomePrices` and `clobTokenIds` arrive as *strings containing
JSON*:

```json
"outcomes": "[\"Yes\", \"No\"]",
"clobTokenIds": "[\"33974309126560025921424163887577156840050159523787019456370396346777882352549\", …]"
```

Gamma is also inconsistent about numeric types: `event.liquidity` is a number
while `market.liquidity` is the string `"19722.914"`; `market.volume` is a
string while `market.volumeNum` is a number. Handled by `JSONStringArray` and
`LenientDouble` / `LenientInt` / `LenientBool` in `Decoding.swift`, all covered
by tests that decode unmodified production payloads.

### 3. Ethereum needs Keccak-256, not SHA3-256

The two differ only in one padding byte (`0x01` vs `0x06`) and produce
completely different, equally valid-looking hashes. `Keccak256.swift`
implements the original Keccak and is tested against published vectors plus
the `private key = 1, 2, 3` → address vectors.

---

## Endpoints used

### Gamma

| Method | Path | Used for |
| --- | --- | --- |
| GET | `/events` | feed, categories, sorting, search, single event by `id`/`slug` |
| GET | `/markets` | single market refresh, condition lookup |
| GET | `/tags` | category chips |

Query parameters used: `limit`, `offset`, `order`, `ascending`, `active`,
`closed`, `archived`, `tag_slug`, `volume_num_min`, `end_date_min`,
`title_contains`, `id`, `slug`, `condition_ids`.

### CLOB — public

| Method | Path | Used for |
| --- | --- | --- |
| GET | `/book` | full order book for one outcome token |
| GET | `/price` | best bid/ask for a side |
| GET | `/midpoint` | mid price |
| GET | `/spread` | spread |
| GET | `/tick-size` | minimum price increment |
| GET | `/prices-history` | chart (`market`, `interval`, `fidelity`) |

### CLOB — authenticated (L2)

| Method | Path | Used for |
| --- | --- | --- |
| POST | `/auth/api-key` | create credentials |
| GET | `/auth/derive-api-key` | recover existing credentials |
| GET | `/data/orders` | open orders |
| POST | `/order` | submit a signed order |
| DELETE | `/order` | cancel one order |
| DELETE | `/cancel-all` | cancel everything |

### Data API v2

| Method | Path | Used for |
| --- | --- | --- |
| GET | `/v2/positions` | portfolio, held shares for sell validation |
| GET | `/v2/activity` | activity feed |
| GET | `/v2/value` | total positions value |
| GET | `/v2/user-stats` | lifetime stats on the profile |
| GET | `/v2/trades` | recent trades on a market |
| GET | `/v2/holders` | top holders on a market |

---

## Authentication

Two layers, both implemented in `ClobAuthenticator`.

**L1 — prove wallet control (once).** Sign the `ClobAuth` EIP-712 struct:

```
domain:  { name: "ClobAuthDomain", version: "1", chainId: 137 }   // no verifyingContract
types:   ClobAuth(address address,string timestamp,uint256 nonce,string message)
message: "This message attests that I control the given wallet"
```

Exchange it at `/auth/api-key` (create) or `/auth/derive-api-key` (recover)
with headers `POLY_ADDRESS`, `POLY_SIGNATURE`, `POLY_TIMESTAMP`, `POLY_NONCE`.
Returns `apiKey`, `secret`, `passphrase`.

Note the domain omits `verifyingContract`, which changes both the type string
and the encoding — getting this wrong yields a well-formed signature the
server rejects.

**L2 — sign each request.**

```
message   = timestamp + METHOD + path + body
signature = urlsafeBase64(HMAC-SHA256(base64Decode(secret), message))
```

Sent as `POLY_ADDRESS`, `POLY_SIGNATURE`, `POLY_TIMESTAMP`, `POLY_API_KEY`,
`POLY_PASSPHRASE`. The signature covers the **path only**, never the query
string, and for `POST /order` it covers the exact serialized body — so the
body is serialized once with sorted keys and those same bytes are both signed
and sent.

---

## Order signing

```
Order(uint256 salt,address maker,address signer,uint256 tokenId,
      uint256 makerAmount,uint256 takerAmount,uint8 side,uint8 signatureType,
      uint256 timestamp,bytes32 metadata,bytes32 builder)
```

Domain: `name: "Polymarket CTF Exchange"`, `chainId: 137`, with the contract
and version chosen by market type:

| Market | version | verifyingContract |
| --- | --- | --- |
| Protocol V2 book | `"3"` | `0xe3333700cA9d93003F00f0F71f8515005F6c00Aa` |
| CTF, `neg_risk: false` | `"2"` | `0xE111180000d2663C0091e4f400237545B87B996B` |
| CTF, `neg_risk: true` | `"2"` | `0xe2222d279d744050d28e00520010520000310F59` |

Amounts are 6-decimal integers. For a BUY, `makerAmount` is USDC and
`takerAmount` is shares; for a SELL they swap. Rounding follows the documented
order: price to the tick's precision, size **down**, then the USD amount up to
`amount+4` decimals and back down to `amount`. `side` is `0` for BUY, `1` for
SELL. `timestamp` is Unix **milliseconds**. `signatureType` is `0` EOA,
`1` proxy, `2` Safe, `3` deposit wallet.

Signature is 65 bytes `r ‖ s ‖ v` with `v = 27 + recoveryId`, produced by
`libsecp256k1` via `swift-secp256k1` — no hand-rolled elliptic curve code.

---

## Builder attribution

The `builder` field is a `bytes32` builder code, registered at
polymarket.com → Settings → Builders. When set it is serialized into the
signed order and indexed on-chain from the `OrderFilled` event. Builder fees
are flat (`notional × bps / 10000`) and additive to the platform fee
(`C × feeRate × p × (1-p)`, taker only). Both are modelled in `FeeEstimator`.

A malformed builder code falls back to the zero value rather than producing an
order the exchange would reject — see `PulseConfiguration.builderField`.

---

## WebSocket

Subscribe with:

```json
{ "assets_ids": ["<token id>"], "type": "market", "custom_feature_enabled": true }
```

The server requires a text `PING` every 10 seconds and replies `PONG`.

Event types handled: `book`, `price_change` (batches several assets in one
frame), `last_trade_price`, `tick_size_change`, `best_bid_ask`. A
`tick_size_change` triggers a market refetch, because a stale tick size makes
every later order invalid.

Reconnection uses exponential backoff with jitter capped at 30s, re-subscribes
on reconnect, and publishes `SocketState` so the UI marks prices **Delayed**
rather than showing frozen numbers as live.

---

## Not integrated

| Capability | Why |
| --- | --- |
| Relayer (`relayer-v2`) gasless ops | Needs builder enrolment; not required for CLOB order flow with a funded wallet. |
| Bridge deposit/withdraw | Separate quote/status flow; the app directs users to fund on Polymarket. |
| User WebSocket channel | Order/trade push. Activity and open orders are fetched on appear and refresh instead. |
| Perps, NEX, combos, RFQ | Out of scope for a prediction-market client. |
| Proxy / Safe wallets | Signing supports `signatureType` 1 and 2, but discovering a user's proxy address needs the relayer. The app uses an EOA (`signatureType 0`). |
