# Configuration & credentials

## What the app needs

| Value | Required? | Where it goes | Secret? |
| --- | --- | --- | --- |
| Privy App ID | To sign in | `Config.xcconfig` → Info.plist | **No** — public client id |
| Privy Client ID | To sign in | `Config.xcconfig` → Info.plist | **No** — public client id |
| Privy **App Secret** | Never | **nowhere in this app** | **Yes** — server only |
| Polymarket builder code | No | `Config.xcconfig` → Info.plist | **No** — public attribution id |
| Builder fee (bps) | No | `Config.xcconfig` → Info.plist | No |
| CLOB API credentials | Derived automatically | iOS Keychain | **Yes** |

## Privy

Sign-in and the wallet come from [Privy](https://privy.io). The app never
handles key material: Privy holds the embedded wallet and returns
signatures, so the worst case for a lost device is a session rather than a
key.

```
PRIVY_APP_ID    = your app id          # Dashboard → App settings
PRIVY_CLIENT_ID = client-...           # Dashboard → App settings → Clients
```

Both are **public** client identifiers and are meant to ship in the bundle.

### The App Secret must never be in the app

`privy_app_secret_…` is a **server-side** credential. Anything inside an iOS
bundle can be extracted from a distributed IPA in minutes, and that secret
can mint user tokens and read the Privy account. The iOS SDK does not accept
it and does not need it.

It has no representation anywhere in this codebase on purpose — not in
`Config.xcconfig`, not in `Info.plist`, not in `PulseConfiguration`. If you
need server-side Privy calls, that belongs in a backend the app talks to.

If a secret has ever been pasted into a chat, a terminal history or a commit,
rotate it in the Privy dashboard.

### OAuth callback

`Info.plist` registers the `pulse://` URL scheme, which must match the
redirect URI configured in the Privy dashboard and the `callbackScheme`
passed to `PrivyAuth`.

Browsing, search, charts, order books and market data need **no credentials at
all**. Only order placement and portfolio reads need a wallet.

## Builder code

A builder code is a `bytes32` identifier from polymarket.com → Settings →
[Builders](https://polymarket.com/settings?tab=builder). It is attached to
each order's `builder` field and indexed on-chain, so it is public by
construction — shipping it in the app bundle is correct.

```
// Config.xcconfig
POLYMARKET_BUILDER_CODE = 0x<64 hex characters>
POLYMARKET_BUILDER_FEE_BPS = 0
```

Fee limits: taker 0–100 bps, maker 0–50 bps. Leave blank to charge nothing.

Without a code the app still works; orders simply carry the zero value and
earn no attribution. A malformed code is ignored rather than producing an
order the exchange would reject.

## Signing

The app builds the EIP-712 digest itself — Keccak-256, the domain separator
and the order struct all live in `PulseCore` and are covered by tests against
published vectors. Privy performs only the final secp256k1 operation over
that digest, through `secp256k1Sign`.

That split matters: swapping the signer changed nothing about *what* gets
signed. `personalSign` would have been wrong here, because it prefixes the
Ethereum signed-message header and yields a signature the exchange rejects.

The only secret the app stores is the CLOB API credential triple, derived
once per wallet from a signature and kept in the Keychain with
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — unreadable while the device
is locked, and excluded from iCloud backups and device transfers.

Other custody models plug in behind the `EthereumSigner` protocol without
touching the trading layer.

## Things deliberately not done

* **No committed secrets.** `Config.xcconfig` holds only public values, and
  `Secrets.xcconfig` is gitignored if you prefer to keep even those out.
* **No geo or eligibility bypass.** Polymarket enforces jurisdiction and KYC
  rules server-side; the app surfaces failures rather than working around them.
* **No simulated fills.** Every order goes to the real CLOB, and the UI only
  reports success when the exchange acknowledges it.
