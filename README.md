# Pulse

A native SwiftUI client for Polymarket's prediction markets.

Pulse is an independent client built on Polymarket's public APIs. It is not
affiliated with or endorsed by Polymarket.

---

## Build caveat — read this first

**The app target has never been compiled.** It was written in a Linux
container with no macOS, Xcode or iOS SDK, so `Pulse/` has had no compiler
run over it. Expect to fix some errors on first build.

What *has* been verified, by a Swift 6.2 toolchain in this environment:

* `PulseCore` — all 25 source files — **compiles clean** under Swift 6 strict
  concurrency.
* **124 tests pass**, including decoding of unmodified production JSON and
  cryptographic vectors from outside this codebase.

Verifying the core this way caught two real bugs that would otherwise have
shipped: `Data` slices keep their parent's indices, so hashing anything from
`dropFirst()` trapped; and the currency formatter rendered `US$` instead of
`$` on a non-US locale.

---

## Requirements

* Xcode 16 or later
* iOS 17.0+ deployment target
* Swift 6

## Running it

```bash
open Pulse.xcodeproj
```

Select the **Pulse** scheme and an iPhone simulator, then run. Swift Package
Manager resolves two dependencies on first build:

* [`swift-secp256k1`](https://github.com/21-DOT-DEV/swift-secp256k1) — the
  audited libsecp256k1 wrapper, for order signing
* [`swift-crypto`](https://github.com/apple/swift-crypto) — HMAC-SHA256 for
  CLOB request signing

No configuration is needed to browse markets. To place orders, see
[docs/CONFIGURATION.md](docs/CONFIGURATION.md).

## Running the core tests

On macOS, via Xcode, or from the command line on any platform with a Swift
toolchain:

```bash
cd PulseCore && swift test
```

## Making a distributable build

```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Release -destination 'generic/platform=iOS' -archivePath build/Pulse.xcarchive archive
```

```bash
xcodebuild -exportArchive -archivePath build/Pulse.xcarchive -exportPath build/export -exportOptionsPlist ExportOptions.plist
```

You will need your own signing team and bundle identifier; set
`PRODUCT_BUNDLE_IDENTIFIER` in `Config.xcconfig`.

---

## Architecture

```
Pulse/                    SwiftUI app — views and view models only
  App/                    entry point, DI container, session/settings stores
  DesignSystem/           palette, type scale, layout, components
  Features/               Home, Explore, MarketDetail, Trade, Portfolio,
                          Activity, Profile

PulseCore/                platform-independent, fully tested
  Models/                 Gamma, CLOB and Data API v2 types
  Networking/             HTTPClient, errors, retry
  Services/               GammaService, ClobService, DataService
  Realtime/               MarketSocket
  Auth/                   Keccak-256, EIP-712, signer, Keychain
  Trading/                quotes, fees, validation, order building, portfolio
  Util/                   lenient decoding, formatting
```

The split is deliberate: everything with a correct answer — decoding, money
arithmetic, signing, validation — lives in `PulseCore`, which has no UI
dependency and runs its tests anywhere. Views hold no business logic and
reach for no singletons; `AppEnvironment` constructs every service and
injects it down the tree.

### Design

The visual language comes from the supplied references: flat pastel colour
fields, pill-shaped controls, generous radii and floating navigation. Each
market is assigned one of eight themes by an FNV-1a hash of its id, so the
feed is colourful without being random — a market keeps the same identity on
every launch and every device. `hashValue` would not do this, since Swift
seeds it per process.

Yes and No keep one pair of hues everywhere — rows, charts, order book, trade
sheet — so the mapping is learned once.

Liquid Glass is left to the system: `TabView` and `.toolbar` adopt it
automatically when built against the iOS 26 SDK. Calling `glassEffect`
directly would break the build on Xcode 16, since an `if #available` check
does not conjure a symbol the SDK lacks.

### Safety properties worth knowing

* **Nothing is simulated.** Every order goes to the real CLOB. The success
  screen appears only when the exchange acknowledges the order; the CLOB
  signals business failures inside a 200 response, and that case is checked.
* **What you confirm is what is signed.** The confirmation screen renders the
  same `PreparedOrder` that submission sends. Nothing is recomputed between.
* **Unknown is not zero.** A missing balance renders as `—`, never `$0.00`.
* **Stale prices say so.** When the socket drops, the header shows *Delayed*
  instead of presenting frozen numbers as live.
* **Open markets never show certainty.** A 99.85% market renders as `>99%`,
  because `100%` is a resolution value.
* **Keys stay on device.** The private key lives only in the Keychain,
  device-only and excluded from backups. Only signatures leave.

---

## Documentation

* [docs/API_INTEGRATION.md](docs/API_INTEGRATION.md) — every endpoint used,
  the auth scheme, order signing, and three API behaviours that are easy to
  get wrong
* [docs/CONFIGURATION.md](docs/CONFIGURATION.md) — credentials and what is
  and is not a secret
* [docs/CHECKLIST.md](docs/CHECKLIST.md) — feature status

## Risk

Prediction markets carry risk, and a position can lose its entire value.
Prices are set by other traders, not by any forecast. Nothing in this app is
financial advice. Availability depends on your jurisdiction and account
eligibility, which Polymarket determines — this client does not work around
those controls.
