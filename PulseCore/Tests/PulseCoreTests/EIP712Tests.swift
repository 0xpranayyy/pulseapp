import XCTest
@testable import PulseCore

final class EIP712Tests: XCTestCase {

    // MARK: Encoding primitives

    func testEncodeUIntIsLeftPadded32Bytes() {
        let encoded = EIP712.encodeUInt(1)
        XCTAssertEqual(encoded.count, 32)
        XCTAssertEqual(encoded.last, 1)
        XCTAssertEqual(encoded.prefix(31), Data(repeating: 0, count: 31))

        XCTAssertEqual(
            EIP712.encodeUInt(255).hexString(prefixed: false).suffix(2),
            "ff"
        )
    }

    func testEncodeAddressIsLeftPadded() {
        let encoded = EIP712.encodeAddress("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
        XCTAssertEqual(encoded?.count, 32)
        XCTAssertEqual(encoded?.prefix(12), Data(repeating: 0, count: 12))
        XCTAssertNil(EIP712.encodeAddress("0x1234"), "wrong length must be rejected")
    }

    func testEncodeBytes32() {
        let zero = EIP712.encodeBytes32(PolymarketOrder.zeroBytes32)
        XCTAssertEqual(zero, Data(repeating: 0, count: 32))
        XCTAssertNil(EIP712.encodeBytes32("0x" + String(repeating: "ff", count: 33)))
    }

    /// Token ids are 77-digit uint256 values far beyond `UInt64`.
    func testEncodeUInt256HandlesRealTokenIds() {
        let tokenId = "33974309126560025921424163887577156840050159523787019456370396346777882352549"
        let encoded = EIP712.encodeUInt256(decimalString: tokenId)
        XCTAssertEqual(encoded?.count, 32)
        XCTAssertNotEqual(encoded, Data(repeating: 0, count: 32))
    }

    func testEncodeUInt256MatchesSmallValues() {
        // Must agree with the UInt64 path for values both can represent.
        for value: UInt64 in [0, 1, 255, 256, 1_000_000, UInt64(Int32.max)] {
            XCTAssertEqual(
                EIP712.encodeUInt256(decimalString: String(value)),
                EIP712.encodeUInt(value),
                "mismatch at \(value)"
            )
        }
    }

    func testEncodeUInt256RejectsBadInput() {
        XCTAssertNil(EIP712.encodeUInt256(decimalString: "-1"))
        XCTAssertNil(EIP712.encodeUInt256(decimalString: "12.5"))
        XCTAssertNil(EIP712.encodeUInt256(decimalString: "abc"))
        XCTAssertNil(EIP712.encodeUInt256(decimalString: ""))
        // 2^256 overflows.
        XCTAssertNil(EIP712.encodeUInt256(
            decimalString: "115792089237316195423570985008687907853269984665640564039457584007913129639936"
        ))
        // 2^256 - 1 is the largest valid value.
        XCTAssertNotNil(EIP712.encodeUInt256(
            decimalString: "115792089237316195423570985008687907853269984665640564039457584007913129639935"
        ))
    }

    // MARK: Domains

    /// The ClobAuth domain omits `verifyingContract`, which changes both the
    /// type string and the encoding.
    func testClobAuthDomainSeparatorIsStable() throws {
        let separator = try EIP712.ClobAuth.domain.separator()
        XCTAssertEqual(separator.count, 32)

        // Recomputed by hand from the documented type string.
        let typeHash = Keccak256.hash(
            "EIP712Domain(string name,string version,uint256 chainId)"
        )
        var expected = typeHash
        expected += Keccak256.hash("ClobAuthDomain")
        expected += Keccak256.hash("1")
        expected += EIP712.encodeUInt(137)
        XCTAssertEqual(separator, Keccak256.hash(expected))
    }

    func testExchangeDomainsDifferPerContract() throws {
        let v2 = try ExchangeDomain.protocolV2.domain.separator()
        let ctf = try ExchangeDomain.ctf.domain.separator()
        let negRisk = try ExchangeDomain.ctfNegRisk.domain.separator()

        XCTAssertNotEqual(v2, ctf)
        XCTAssertNotEqual(ctf, negRisk)
        XCTAssertNotEqual(v2, negRisk)
    }

    func testExchangeDomainSelection() {
        XCTAssertEqual(ExchangeDomain.select(isProtocolV2: true, negRisk: false), .protocolV2)
        XCTAssertEqual(ExchangeDomain.select(isProtocolV2: true, negRisk: true), .protocolV2)
        XCTAssertEqual(ExchangeDomain.select(isProtocolV2: false, negRisk: false), .ctf)
        XCTAssertEqual(ExchangeDomain.select(isProtocolV2: false, negRisk: true), .ctfNegRisk)
    }

    func testExchangeDomainVersions() {
        XCTAssertEqual(ExchangeDomain.protocolV2.domainVersion, "3")
        XCTAssertEqual(ExchangeDomain.ctf.domainVersion, "2")
        XCTAssertEqual(ExchangeDomain.ctfNegRisk.domainVersion, "2")
        XCTAssertEqual(ExchangeDomain.ctf.domain.name, "Polymarket CTF Exchange")
        XCTAssertEqual(ExchangeDomain.ctf.domain.chainId, 137)
    }

    // MARK: ClobAuth

    func testClobAuthDigestChangesWithEveryField() throws {
        let base = EIP712.ClobAuth(address: "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf",
                                   timestamp: "1700000000", nonce: 0)
        let baseDigest = try base.signingDigest()
        XCTAssertEqual(baseDigest.count, 32)

        let otherTime = EIP712.ClobAuth(address: base.address, timestamp: "1700000001", nonce: 0)
        XCTAssertNotEqual(try otherTime.signingDigest(), baseDigest)

        let otherNonce = EIP712.ClobAuth(address: base.address, timestamp: base.timestamp, nonce: 1)
        XCTAssertNotEqual(try otherNonce.signingDigest(), baseDigest)

        let otherAddress = EIP712.ClobAuth(address: "0x2b5ad5c4795c026514f8317c7a215e218dccd6cf",
                                           timestamp: base.timestamp, nonce: 0)
        XCTAssertNotEqual(try otherAddress.signingDigest(), baseDigest)
    }

    func testClobAuthMessageTextMatchesSpec() {
        XCTAssertEqual(
            EIP712.ClobAuth.messageText,
            "This message attests that I control the given wallet"
        )
    }

    // MARK: Order struct hash

    private func sampleOrder(
        side: OrderSide = .buy,
        builder: String = PolymarketOrder.zeroBytes32
    ) -> PolymarketOrder {
        PolymarketOrder(
            salt: 479249096354,
            maker: "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf",
            signer: "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf",
            tokenId: "33974309126560025921424163887577156840050159523787019456370396346777882352549",
            makerAmount: "5200000",
            takerAmount: "10000000",
            side: side,
            signatureType: .polyProxy,
            timestamp: "1700000000000",
            builder: builder
        )
    }

    func testOrderTypeStringMatchesDocumentedSpec() {
        XCTAssertEqual(
            PolymarketOrder.typeString,
            "Order(uint256 salt,address maker,address signer,uint256 tokenId,uint256 makerAmount,uint256 takerAmount,uint8 side,uint8 signatureType,uint256 timestamp,bytes32 metadata,bytes32 builder)"
        )
    }

    func testOrderStructHashIsStableAndFieldSensitive() throws {
        let order = sampleOrder()
        let hash = try order.structHash()
        XCTAssertEqual(hash.count, 32)
        XCTAssertEqual(try sampleOrder().structHash(), hash, "same inputs must hash the same")

        // Flipping the side must change the hash: BUY encodes 0, SELL encodes 1.
        XCTAssertNotEqual(try sampleOrder(side: .sell).structHash(), hash)

        // A builder code is part of the signed payload.
        let withBuilder = sampleOrder(
            builder: "0x1111111111111111111111111111111111111111111111111111111111111111"
        )
        XCTAssertNotEqual(try withBuilder.structHash(), hash)
    }

    func testOrderSideEncoding() {
        XCTAssertEqual(sampleOrder(side: .buy).sideValue, 0)
        XCTAssertEqual(sampleOrder(side: .sell).sideValue, 1)
    }

    func testOrderDigestDiffersPerExchange() throws {
        let order = sampleOrder()
        let a = try order.signingDigest(domain: .ctf)
        let b = try order.signingDigest(domain: .ctfNegRisk)
        let c = try order.signingDigest(domain: .protocolV2)
        XCTAssertEqual(a.count, 32)
        XCTAssertNotEqual(a, b, "neg-risk orders must not be replayable on the standard exchange")
        XCTAssertNotEqual(a, c)
    }

    func testOrderRejectsInvalidFields() {
        var order = PolymarketOrder(
            salt: 1, maker: "not-an-address", signer: "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf",
            tokenId: "1", makerAmount: "1", takerAmount: "1", side: .buy,
            signatureType: .eoa, timestamp: "1"
        )
        XCTAssertThrowsError(try order.structHash())

        order = PolymarketOrder(
            salt: 1, maker: "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf",
            signer: "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf",
            tokenId: "not-a-number", makerAmount: "1", takerAmount: "1", side: .buy,
            signatureType: .eoa, timestamp: "1"
        )
        XCTAssertThrowsError(try order.structHash())
    }

    // MARK: Submission body

    func testSubmissionBodySerializesStably() throws {
        let order = sampleOrder()
        let submission = OrderSubmission(
            order: order, signature: "0xdeadbeef", orderType: .gtc, owner: "api-key-123"
        )
        let data = try submission.serialized()
        let json = String(data: data, encoding: .utf8) ?? ""

        // Sorted keys make the bytes reproducible — the L2 HMAC signs exactly
        // these bytes, so two serializations must be byte-identical.
        XCTAssertEqual(try submission.serialized(), data)

        // salt is a number; amounts are strings.
        XCTAssertTrue(json.contains("\"salt\":479249096354"), json)
        XCTAssertTrue(json.contains("\"makerAmount\":\"5200000\""), json)
        XCTAssertTrue(json.contains("\"side\":\"BUY\""), json)
        XCTAssertTrue(json.contains("\"orderType\":\"GTC\""), json)
        XCTAssertTrue(json.contains("\"owner\":\"api-key-123\""), json)
        XCTAssertTrue(json.contains("\"deferExec\":false"), json)
    }

    // MARK: Builder configuration

    func testBuilderFieldFallsBackToZeroWhenUnset() {
        XCTAssertEqual(PulseConfiguration().builderField, PolymarketOrder.zeroBytes32)
        XCTAssertEqual(
            PulseConfiguration(builderCode: "0xnonsense").builderField,
            PolymarketOrder.zeroBytes32,
            "a malformed builder code must not produce an unsignable order"
        )
        XCTAssertEqual(
            PulseConfiguration(builderCode: "0x12").builderField,
            PolymarketOrder.zeroBytes32,
            "a short builder code is not a valid bytes32"
        )

        let valid = "0x" + String(repeating: "ab", count: 32)
        XCTAssertEqual(PulseConfiguration(builderCode: valid).builderField, valid)
    }
}
