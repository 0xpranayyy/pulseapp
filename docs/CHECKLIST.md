# Development checklist

Status as of the final commit. "Verified" means covered by a test that runs,
or exercised against the live API during development.

## Core — verified

- [x] Gamma models decode unmodified production JSON — *verified, test*
- [x] JSON-string-encoded arrays (`outcomes`, `clobTokenIds`) — *verified, test*
- [x] Mixed string/number numerics — *verified, test*
- [x] Data API **v2** envelope, snake_case, cursor paging — *verified, test*
- [x] Order book normalisation (best-first, zero levels dropped) — *verified, test*
- [x] Price history decode — *verified, test*
- [x] All five date formats Polymarket emits — *verified, test*
- [x] Keccak-256 vs published vectors — *verified, test*
- [x] Address derivation vs known keys — *verified, test*
- [x] EIP-55 checksum — *verified, test*
- [x] EIP-712 domain separators per exchange — *verified, test*
- [x] Order struct hash, field-sensitive — *verified, test*
- [x] uint256 encoding of 77-digit token ids — *verified, test*
- [x] secp256k1 recoverable signing, `v = 27 + recid` — *verified, test*
- [x] L2 HMAC covers timestamp, method, path and body — *verified, test*
- [x] L1 header construction — *verified, test*
- [x] Order amount rounding vs the documented worked example — *verified, test*
- [x] Order book walking (buy/sell, partial, limits) — *verified, test*
- [x] Tick conformance and snapping — *verified, test*
- [x] Order validation (balance, size, tick, slippage, auth) — *verified, test*
- [x] Fee estimation, platform + builder — *verified, test*
- [x] Portfolio aggregation — *verified, test*
- [x] WebSocket frame parsing, all event types — *verified, test*
- [x] Retry classification and user-facing messages — *verified, test*
- [x] Money/probability formatting — *verified, test*
- [x] Secret store round-trip — *verified, test*

## Live integration — verified against the real APIs

Run with `PULSE_LIVE_TESTS=1 swift test --filter LiveSmokeTests`. All 5 passed
on 2026-11-27 against production hosts (read-only; no credentials, no orders).

- [x] Gamma returns tradable events with usable token ids and probabilities
- [x] CLOB book parses, is best-first, uncrossed, and agrees with `/midpoint`
- [x] Tick size is one of the six documented values
- [x] Price history is chronological and within 0–1
- [x] Data API **v2** envelope, cursor paging, `/value`, `/activity`
- [x] Search returns relevant events

## Networking — implemented

- [x] Centralised `HTTPClient`, retry with jittered backoff, `Retry-After`
- [x] Request cancellation, offline detection
- [x] L2 auth injected without the HTTP layer owning secrets
- [x] WebSocket reconnect, re-subscribe, 10s heartbeat, stale-state publishing
- [x] Cursor pagination (Data API) and offset pagination (Gamma)
- [x] Debounced search (280 ms)

## App — implemented, not yet run on a simulator

- [x] Five-tab architecture
- [x] Home: featured carousel, watchlist, trending, closing soon
- [x] Explore: search, 9 categories, 6 sort orders, infinite scroll
- [x] Market detail: themed header, Swift Charts price chart with scrubbing,
      6 ranges, stats, depth-visualised order book, holders, rules sheet
- [x] Multi-outcome event handling
- [x] Trade sheet: market + limit, buy + sell, live quote, fees, payout,
      confirmation step, success/failure states
- [x] Portfolio: value, P&L, allocations, 5 lifecycle filters
- [x] Activity: history with paging, open orders, cancel
- [x] Profile: wallet connect/disconnect, lifetime stats, settings, legal
- [x] Design system: pastel theme engine, pill controls, skeletons, empty and
      error states for every screen
- [x] Dynamic Type throughout, VoiceOver labels, Reduce Motion respected
- [x] Light and dark variants for every colour

## Not done

- [ ] **Run on a simulator.** No macOS available in this environment, so the
      app target has never been compiled. See the build caveat in the README.
- [ ] Proxy/Safe wallet discovery (needs the relayer API)
- [ ] Gasless relayer transactions
- [ ] Deposits/withdrawals and bridging
- [ ] Push notifications (no server to send them)
- [ ] User WebSocket channel for order/trade push
- [ ] iPad-optimised layouts (builds universal, laid out for iPhone)
