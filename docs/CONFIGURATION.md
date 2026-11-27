# Configuration & credentials

## What the app needs

| Value | Required? | Where it goes | Secret? |
| --- | --- | --- | --- |
| Polymarket builder code | No | `Config.xcconfig` → Info.plist | **No** — public attribution id |
| Builder fee (bps) | No | `Config.xcconfig` → Info.plist | No |
| Wallet private key | Only to trade | iOS Keychain, entered by the user | **Yes** |
| CLOB API credentials | Derived automatically | iOS Keychain | **Yes** |

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

## Wallet keys — what this app does and does not do

The private key is entered by the user on the Connect screen and:

* is written straight to the **iOS Keychain** with
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, so it is unreadable while the
  device is locked and is excluded from iCloud backups and device transfers;
* is **never** held in a view model, logged, or placed in `UserDefaults`, a
  plist, or the app bundle;
* is read only at the moment a signature is produced, then released;
* never leaves the device. Only signatures do.

There is no server component, so there is no server-side secret to protect.

### If you would rather not hold keys in the app

The signing path is behind the `EthereumSigner` protocol
(`PulseCore/Sources/PulseCore/Auth/Signer.swift`). Implementing it against
WalletConnect, a hardware signer or a passkey-backed service requires no
changes to the trading layer — supply a different signer in
`SessionStore.signingContext()`.

## Things deliberately not done

* **No committed secrets.** `Config.xcconfig` holds only public values, and
  `Secrets.xcconfig` is gitignored if you prefer to keep even those out.
* **No geo or eligibility bypass.** Polymarket enforces jurisdiction and KYC
  rules server-side; the app surfaces failures rather than working around them.
* **No simulated fills.** Every order goes to the real CLOB, and the UI only
  reports success when the exchange acknowledges it.
