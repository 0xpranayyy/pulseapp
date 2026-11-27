// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PulseCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PulseCore", targets: ["PulseCore"])
    ],
    dependencies: [
        // Audited libsecp256k1 (Bitcoin Core) wrapper. Used for EIP-712 order
        // signing. We never hand-roll elliptic-curve crypto.
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1", from: "0.25.1"),
        // HMAC-SHA256 for CLOB L2 request signing. On Apple platforms this is a
        // thin shim over CryptoKit; on Linux it gives us the same API so the
        // signing path is testable off-device.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.8.0")
    ],
    targets: [
        .target(
            name: "PulseCore",
            dependencies: [
                .product(name: "P256K", package: "swift-secp256k1"),
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .testTarget(
            name: "PulseCoreTests",
            dependencies: ["PulseCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
