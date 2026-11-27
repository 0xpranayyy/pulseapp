import XCTest
@testable import PulseCore

/// Verifies the cryptographic primitives against published vectors. A silent
/// error anywhere here produces signatures the exchange rejects — or worse,
/// signatures over the wrong order — so these are checked against values that
/// do not come from this codebase.
final class CryptoTests: XCTestCase {

    // MARK: Keccak-256

    func testKeccak256KnownVectors() {
        // Standard Keccak-256 (not SHA3-256) vectors.
        XCTAssertEqual(
            Keccak256.hash("").hexString(prefixed: false),
            "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
        )
        XCTAssertEqual(
            Keccak256.hash("abc").hexString(prefixed: false),
            "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"
        )
        XCTAssertEqual(
            Keccak256.hash("The quick brown fox jumps over the lazy dog").hexString(prefixed: false),
            "4d741b6f1eb29cb2a9b9911c82f56fa8d73b04959d3d9d222895df6c0b28aa15"
        )
    }

    /// A 136-byte input is exactly one rate block and exercises the padding
    /// edge case where a whole extra block must be absorbed.
    func testKeccak256BlockBoundary() {
        let input = Data(repeating: 0x61, count: 136)
        let hash = Keccak256.hash(input)
        XCTAssertEqual(hash.count, 32)
        // Differs from a 135-byte input, proving padding is applied.
        XCTAssertNotEqual(hash, Keccak256.hash(Data(repeating: 0x61, count: 135)))
    }

    func testKeccak256IsNotSHA3() {
        // SHA3-256("") would be a7ffc6f8bf1ed766... — if this ever matches,
        // the padding byte has been changed to 0x06 and every signature is wrong.
        XCTAssertNotEqual(
            Keccak256.hash("").hexString(prefixed: false),
            "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a"
        )
    }

    // MARK: Hex

    func testHexRoundTrip() {
        let data = Data([0x00, 0x01, 0xff, 0xab])
        XCTAssertEqual(data.hexString(), "0x0001ffab")
        XCTAssertEqual(data.hexString(prefixed: false), "0001ffab")
        XCTAssertEqual(Data(hexString: "0x0001ffab"), data)
        XCTAssertEqual(Data(hexString: "0001ffab"), data)
        XCTAssertNil(Data(hexString: "0xabc"))      // odd length
        XCTAssertNil(Data(hexString: "0xzz"))       // not hex
    }

    // MARK: Address derivation

    /// Well-known secp256k1 key → Ethereum address pairs. These are the
    /// canonical "private key = 1, 2, 3" vectors.
    func testAddressDerivationKnownKeys() async throws {
        let cases: [(key: String, address: String)] = [
            ("0x0000000000000000000000000000000000000000000000000000000000000001",
             "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf"),
            ("0x0000000000000000000000000000000000000000000000000000000000000002",
             "0x2b5ad5c4795c026514f8317c7a215e218dccd6cf"),
            ("0x0000000000000000000000000000000000000000000000000000000000000003",
             "0x6813eb9362372eef6200f3b1dbc3f819671cba69")
        ]

        for c in cases {
            let signer = try PrivateKeySigner(privateKeyHex: c.key)
            let derived = try await signer.address
            XCTAssertEqual(derived.lowercased(), c.address, "key \(c.key)")
        }
    }

    func testRejectsMalformedPrivateKey() {
        XCTAssertThrowsError(try PrivateKeySigner(privateKeyHex: "0x1234"))
        XCTAssertThrowsError(try PrivateKeySigner(privateKeyHex: "not hex"))
    }

    /// EIP-55 checksum encoding, from the EIP's own examples.
    func testChecksumAddress() {
        XCTAssertEqual(
            EthereumAddress.checksummed("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed"),
            "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
        )
        XCTAssertEqual(
            EthereumAddress.checksummed("0xfb6916095ca1df60bb79ce92ce3ea74c37c5d359"),
            "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359"
        )
    }

    // MARK: Signing

    func testSignatureIs65BytesWithEthereumV() async throws {
        let signer = try PrivateKeySigner(
            privateKeyHex: "0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318"
        )
        let digest = Keccak256.hash("hello polymarket")
        let sig = try await signer.signDigest(digest)

        let bytes = try XCTUnwrap(Data(hexString: sig))
        XCTAssertEqual(bytes.count, 65, "r(32) + s(32) + v(1)")
        let v = bytes[bytes.index(bytes.startIndex, offsetBy: 64)]
        XCTAssertTrue(v == 27 || v == 28, "v must be 27 or 28, got \(v)")
    }

    func testSigningIsDeterministic() async throws {
        // RFC 6979 deterministic nonces mean the same digest always signs the
        // same way — important because an order is signed once and must match
        // whatever the exchange recovers.
        let signer = try PrivateKeySigner(
            privateKeyHex: "0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318"
        )
        let digest = Keccak256.hash("determinism")
        let a = try await signer.signDigest(digest)
        let b = try await signer.signDigest(digest)
        XCTAssertEqual(a, b)
    }

    func testRejectsWrongDigestLength() async throws {
        let signer = try PrivateKeySigner(
            privateKeyHex: "0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318"
        )
        do {
            _ = try await signer.signDigest(Data(repeating: 0, count: 31))
            XCTFail("expected a throw for a 31-byte digest")
        } catch let error as SignerError {
            XCTAssertEqual(error, .invalidDigestLength(31))
        }
    }
}
