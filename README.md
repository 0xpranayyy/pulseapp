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
Supporting/               Info.plists (outside the synced folders — see below)
  generate_project.py     regenerates Pulse.xcodeproj; refuses to write a
                          file with a dangling object id
Pulse/                    SwiftUI app — views and view models only
  Features/Onboarding/    four colour-field pages, one interactive
PulseWidgets/             Live Activity / Dynamic Island
PulseWatch/               standalone watchOS app
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

`Pulse/` is a **synchronized file group** (Xcode 16), so files added to that
folder join the target automatically with no pbxproj edit. The one consequence
worth knowing: anything in there is also a candidate bundle resource, so
`Info.plist` lives in `Supporting/` instead. Inside `Pulse/` it would be both
copied as a resource and processed via `INFOPLIST_FILE`, and Xcode fails the
build with *"Multiple commands produce …/Pulse.app/Info.plist"*.

The split is deliberate: everything with a correct answer — decoding, money
arithmetic, signing, validation — lives in `PulseCore`, which has no UI
dependency and runs its tests anywhere. Views hold no business logic and
reach for no singletons; `AppEnvironment` constructs every service and
injects it down the tree.

### Design

Bright and trading-first. Working screens sit on a warm cream canvas with
navy ink and white **chunky cards** — hard, unblurred offset shadows that
buttons press down into. Two colours mean exactly one thing each: **green is
Yes, red is No**, everywhere from feed pills to the order book. Lime is the
live accent.

* **The tug.** Every market shows its odds as a rope: green Yes share on the
  left, red No on the right, a lime knot at the price. The odds read as a
  position before they read as a number (`TugBar` in
  `DesignSystem/Components/Chunky.swift`).
* **Category colour.** A market's Gamma tags pick its category (sport,
  crypto, politics, economy, tech, culture, world) in `MarketCategory`.
  Each has a bright *fill* for dots and icons and a deeper *panel* shade,
  tested to clear 4.5:1 under white text, for headers and featured cards.
  No category is green or red.
* **Pip**, the mascot (`DesignSystem/Pip/Pip.swift`), reacts to what
  happened — an order placed, a portfolio up or down, an empty list — and
  never picks a side. Drawn in one `Canvas`, animated from one
  `TimelineView`, still under Reduce Motion.
* **The meadow** (`MeadowScene`) is the brand stage for onboarding and
  sign-in only, never behind data.

Type is **Fredoka** for display and **Nunito** for UI (both OFL-1.1, bundled
with their licences; `Supporting/fonts/build_fonts.sh` cuts the static
weights). Anything that ticks is set in Nunito, whose figures are fixed-width,
so live prices do not jitter. All type is routed through `relativeTo:` so
Dynamic Type works.

The app runs light only for now: the palette is designed against cream, and a
dark theme is its own piece of design rather than an inversion.

The app icon is rendered by `Supporting/render/make_icon.js` (Pip peeking
over the meadow).

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
