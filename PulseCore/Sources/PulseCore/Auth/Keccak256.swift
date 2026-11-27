import Foundation

/// Keccak-256 as used by Ethereum.
///
/// This is **original Keccak**, not the finalised SHA-3 standard: the only
/// difference is the domain-separation byte in the padding (`0x01` here,
/// `0x06` for SHA3-256). Using SHA3-256 would produce valid-looking but
/// completely wrong hashes, so this is implemented explicitly rather than
/// reached for from a general-purpose hash library.
///
/// Verified in `Keccak256Tests` against the standard empty-string and "abc"
/// vectors and against a known EIP-712 domain separator.
public enum Keccak256 {

    private static let rounds = 24

    private static let roundConstants: [UInt64] = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
        0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
        0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008
    ]

    /// Rotation offsets for the rho step, indexed [x][y].
    private static let rotationOffsets: [[Int]] = [
        [0, 36, 3, 41, 18],
        [1, 44, 10, 45, 2],
        [62, 6, 43, 15, 61],
        [28, 55, 25, 21, 56],
        [27, 20, 39, 8, 14]
    ]

    /// Hashes `input`, returning 32 bytes.
    public static func hash(_ input: Data) -> Data {
        // Rate for Keccak-256 is 1088 bits = 136 bytes.
        let rateBytes = 136
        var state = [UInt64](repeating: 0, count: 25)

        // Re-base the buffer. A `Data` slice (anything from `dropFirst()`,
        // `suffix()`, etc.) keeps its parent's indices, so `padded[0]` would
        // trap and `padded[count - 1]` would address the wrong byte. Copying
        // into a fresh `Data` normalises indices to 0..<count.
        var padded = Data(input)

        // Pad: append 0x01, zero fill, set the high bit of the final rate byte.
        padded.append(0x01)
        while padded.count % rateBytes != 0 { padded.append(0x00) }
        padded[padded.count - 1] |= 0x80

        // Absorb.
        var offset = 0
        while offset < padded.count {
            for i in 0..<(rateBytes / 8) {
                let start = offset + i * 8
                var lane: UInt64 = 0
                for b in 0..<8 {
                    lane |= UInt64(padded[start + b]) << (8 * UInt64(b))
                }
                state[i] ^= lane
            }
            permute(&state)
            offset += rateBytes
        }

        // Squeeze 32 bytes. 32 < rate, so a single squeeze suffices.
        var out = Data(capacity: 32)
        for i in 0..<4 {
            let lane = state[i]
            for b in 0..<8 {
                out.append(UInt8truncating: lane >> (8 * UInt64(b)))
            }
        }
        return out
    }

    public static func hash(_ bytes: [UInt8]) -> Data { hash(Data(bytes)) }
    public static func hash(_ string: String) -> Data { hash(Data(string.utf8)) }

    // MARK: - Keccak-f[1600]

    private static func permute(_ a: inout [UInt64]) {
        var c = [UInt64](repeating: 0, count: 5)
        var d = [UInt64](repeating: 0, count: 5)
        var b = [UInt64](repeating: 0, count: 25)

        for round in 0..<rounds {
            // Theta
            for x in 0..<5 {
                c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20]
            }
            for x in 0..<5 {
                d[x] = c[(x + 4) % 5] ^ rotl(c[(x + 1) % 5], 1)
            }
            for x in 0..<5 {
                for y in 0..<5 {
                    a[x + 5 * y] ^= d[x]
                }
            }

            // Rho and Pi
            for x in 0..<5 {
                for y in 0..<5 {
                    let rotated = rotl(a[x + 5 * y], rotationOffsets[x][y])
                    b[y + 5 * ((2 * x + 3 * y) % 5)] = rotated
                }
            }

            // Chi
            for x in 0..<5 {
                for y in 0..<5 {
                    a[x + 5 * y] = b[x + 5 * y] ^ (~b[(x + 1) % 5 + 5 * y] & b[(x + 2) % 5 + 5 * y])
                }
            }

            // Iota
            a[0] ^= roundConstants[round]
        }
    }

    @inline(__always)
    private static func rotl(_ x: UInt64, _ n: Int) -> UInt64 {
        let n = UInt64(n % 64)
        if n == 0 { return x }
        return (x << n) | (x >> (64 - n))
    }
}

private extension Data {
    mutating func append(UInt8truncating value: UInt64) {
        append(UInt8(value & 0xff))
    }
}

// MARK: - Hex helpers

public extension Data {
    /// Lowercase hex, `0x`-prefixed by default.
    func hexString(prefixed: Bool = true) -> String {
        let body = map { String(format: "%02x", $0) }.joined()
        return prefixed ? "0x" + body : body
    }

    /// Parses hex with or without a `0x` prefix. Returns nil on odd length or
    /// any non-hex character.
    init?(hexString: String) {
        var hex = hexString
        if hex.hasPrefix("0x") || hex.hasPrefix("0X") { hex = String(hex.dropFirst(2)) }
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
