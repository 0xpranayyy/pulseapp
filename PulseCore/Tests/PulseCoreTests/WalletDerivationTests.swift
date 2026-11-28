import XCTest
@testable import PulseCore

/// Vectors computed with `ox` using the exact algorithms in
/// `@polymarket/client` 0.20.1 (`wallet.ts`, `exchange.ts`, `actions/gasless.ts`,
/// `actions/approvals.ts`). If Polymarket changes any of these, a mismatch
/// here is the first place it shows.
final class WalletDerivationTests: XCTestCase {

    private let signer = "0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf"
    private let tokenId = "71321045679252212594626385532706912750332728571942532289631379312455583992563"
    private let builder = "0xbf6c25151535c7ab13e362497953bb4dbd848abe07222e53bb075c936c179377"

    // MARK: Derivation

    func testDepositWalletAddresses() {
        XCTAssertEqual(WalletDerivation.depositWallet(signer: signer), "0x6f908b3b67b9f9c40413775fff48b286aef9a081")
        XCTAssertEqual(WalletDerivation.legacyDepositWallet(signer: signer), "0x73310c2e333fb7fb177dcb43e164958a9d443d6f")
    }

    func testLegacyWalletAddresses() {
        XCTAssertEqual(WalletDerivation.safe(owner: signer), "0x51b7c68a71dccbc0b7fa4400934a293d8f4d3ba8")
        XCTAssertEqual(WalletDerivation.proxy(owner: signer), "0x909deda326ed2ae677f5f8c2527e32977c9838c3")
    }

    func testClassification() {
        XCTAssertEqual(WalletDerivation.classify(signer: signer, wallet: signer), .eoa)
        XCTAssertEqual(WalletDerivation.classify(signer: signer, wallet: "0x6F908B3B67B9F9C40413775FFF48B286AEF9A081"), .depositWallet)
        XCTAssertEqual(WalletDerivation.classify(signer: signer, wallet: "0x73310c2e333fb7fb177dcb43e164958a9d443d6f"), .depositWallet)
        XCTAssertEqual(WalletDerivation.classify(signer: signer, wallet: "0x51b7c68a71dccbc0b7fa4400934a293d8f4d3ba8"), .polyGnosisSafe)
        XCTAssertEqual(WalletDerivation.classify(signer: signer, wallet: "0x909deda326ed2ae677f5f8c2527e32977c9838c3"), .polyProxy)
        XCTAssertNil(WalletDerivation.classify(signer: signer, wallet: "0x" + String(repeating: "1", count: 40)))
    }

    // MARK: Orders

    private func order(maker: String, signer orderSigner: String, type: SignatureType) -> PolymarketOrder {
        PolymarketOrder(
            salt: 479_249_096_354, maker: maker, signer: orderSigner, tokenId: tokenId,
            makerAmount: "5200000", takerAmount: "10000000", side: .buy,
            signatureType: type, timestamp: "1760000000000", builder: builder
        )
    }

    func testOrderTypedDataMatchesReferenceAndHandRolledHash() throws {
        let eoa = order(maker: signer, signer: signer, type: .eoa)
        let typed = TypedData.order(eoa, exchange: .ctf)
        XCTAssertEqual(try typed.signingDigest().hexString(prefixed: true),
                       "0xdecb4ffeeda1cb00bdbd27ba0f2afeb04536e6f3e0bcc436a900eea7ded7a15d")
        // The general engine and the hand-written struct hash agree.
        XCTAssertEqual(try typed.signingDigest(), try eoa.signingDigest(domain: .ctf))
    }

    func testDepositWalletOrderDigestAndWrap() throws {
        let wallet = try XCTUnwrap(WalletDerivation.depositWallet(signer: signer))
        let dw = order(maker: wallet, signer: wallet, type: .depositWallet)
        XCTAssertEqual(try TypedData.depositWalletOrder(dw, exchange: .ctf).signingDigest().hexString(prefixed: true),
                       "0x162682be70bac37d47293e5bb77c3d9aab4404d2252dd4aaba279d184f5f0e92")

        let inner = "0x" + String(repeating: "11", count: 64) + "1b"
        let wrapped = try DepositWalletSignature.wrap(innerSignature: inner, order: dw, exchange: .ctf)
        XCTAssertEqual(wrapped, "0x111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111b3264e159346253e26a64e00b69032db0e7d32f94628de3e6eecb50304d7af3d25cbfa813190f6a3668acf0a0d023dbf10a58952d98d54895e9856ac18d45834b4f726465722875696e743235362073616c742c61646472657373206d616b65722c61646472657373207369676e65722c75696e7432353620746f6b656e49642c75696e74323536206d616b6572416d6f756e742c75696e743235362074616b6572416d6f756e742c75696e743820736964652c75696e7438207369676e6174757265547970652c75696e743235362074696d657374616d702c62797465733332206d657461646174612c62797465733332206275696c6465722900ba")
    }

    func testTradingAccountOrderIdentity() {
        let wallet = "0x6f908b3b67b9f9c40413775fff48b286aef9a081"
        let deposit = TradingAccount(signer: signer, wallet: wallet, type: .depositWallet)
        XCTAssertEqual(deposit.maker, wallet)
        XCTAssertEqual(deposit.orderSigner, wallet)
        let safe = TradingAccount(signer: signer, wallet: "0x51b7c68a71dccbc0b7fa4400934a293d8f4d3ba8", type: .polyGnosisSafe)
        XCTAssertEqual(safe.orderSigner, signer)
    }

    /// A real key signs both paths end to end, so the signature plumbing is
    /// exercised, not only the hashing.
    func testAccountSigningProducesExpectedShapes() async throws {
        let key = try PrivateKeySigner(privateKeyHex: "0x" + String(repeating: "0", count: 63) + "1")
        let address = try await key.address
        XCTAssertEqual(address.lowercased(), signer.lowercased())
        let wallet = try XCTUnwrap(WalletDerivation.depositWallet(signer: address))

        let eoaSig = try await TradingAccount.eoa(address)
            .sign(order(maker: address, signer: address, type: .eoa), exchange: .ctf, with: key)
        XCTAssertEqual(Data(hexString: eoaSig)?.count, 65)

        let dwSig = try await TradingAccount(signer: address, wallet: wallet, type: .depositWallet)
            .sign(order(maker: wallet, signer: wallet, type: .depositWallet), exchange: .ctf, with: key)
        // 65 + 32 + 32 + type string + 2
        XCTAssertEqual(Data(hexString: dwSig)?.count, 65 + 64 + PolymarketOrder.typeString.utf8.count + 2)
    }

    func testRecoveryReturnsTheSigningAddress() async throws {
        let key = try PrivateKeySigner(privateKeyHex: "0x" + String(repeating: "0", count: 63) + "1")
        let typed = TypedData.clobAuth(EIP712.ClobAuth(address: signer, timestamp: "1700000000"))
        let signature = try await key.signTypedData(typed)
        let recovered = try EthereumRecovery.address(signature: signature, digest: try typed.signingDigest())
        XCTAssertEqual(recovered.lowercased(), signer.lowercased())
        // A different digest recovers someone else.
        let other = try EthereumRecovery.address(signature: signature, digest: Data(repeating: 7, count: 32))
        XCTAssertNotEqual(other.lowercased(), signer.lowercased())
    }

    // MARK: Relayer batch and approvals

    func testApprovalCalldata() {
        XCTAssertEqual(ContractCall.approveMax(token: PolymarketContracts.collateralToken,
                                               spender: PolymarketContracts.standardExchange)?.data,
                       "0x095ea7b3000000000000000000000000e111180000d2663c0091e4f400237545b87b996bffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
        XCTAssertEqual(ContractCall.setApprovalForAll(token: PolymarketContracts.conditionalTokens,
                                                      operator: PolymarketContracts.standardExchange)?.data,
                       "0xa22cb465000000000000000000000000e111180000d2663c0091e4f400237545b87b996b0000000000000000000000000000000000000000000000000000000000000001")
        XCTAssertEqual(TradingApprovals.calls.count, 16)
    }

    func testBatchDigest() throws {
        let wallet = try XCTUnwrap(WalletDerivation.depositWallet(signer: signer))
        let calls = [
            try XCTUnwrap(ContractCall.approveMax(token: PolymarketContracts.collateralToken, spender: PolymarketContracts.standardExchange)),
            try XCTUnwrap(ContractCall.setApprovalForAll(token: PolymarketContracts.conditionalTokens, operator: PolymarketContracts.standardExchange))
        ]
        let batch = TypedData.depositWalletBatch(wallet: wallet, nonce: "7", deadline: "1760000600", calls: calls)
        XCTAssertEqual(try batch.signingDigest().hexString(prefixed: true),
                       "0x7cf5128943f1abd860d230c3e4bc3f053fc1bb6ef2a670e9a57f5ed6745aa4ad")
    }

    func testClobAuthTypedDataMatchesReferenceAndHandRolledHash() throws {
        let auth = EIP712.ClobAuth(address: signer, timestamp: "1700000000")
        let typed = TypedData.clobAuth(auth)
        XCTAssertEqual(try typed.signingDigest().hexString(prefixed: true),
                       "0x29cc0fe956d73b8f2962f2e3939a1248a4b094e07b914f8ef1ece85c7ee7e59a")
        XCTAssertEqual(try typed.signingDigest(), try auth.signingDigest())
    }

    // MARK: Wallet-app JSON

    func testV4JSONShape() throws {
        let wallet = try XCTUnwrap(WalletDerivation.depositWallet(signer: signer))
        let json = try TypedData.depositWalletOrder(order(maker: wallet, signer: wallet, type: .depositWallet), exchange: .ctf).v4JSON()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(object["primaryType"] as? String, "TypedDataSign")
        let types = try XCTUnwrap(object["types"] as? [String: Any])
        XCTAssertNotNil(types["EIP712Domain"]); XCTAssertNotNil(types["Order"]); XCTAssertNotNil(types["TypedDataSign"])
        let message = try XCTUnwrap(object["message"] as? [String: Any])
        let contents = try XCTUnwrap(message["contents"] as? [String: Any])
        // A 77-digit token id must stay a string; small integers become numbers.
        XCTAssertEqual(contents["tokenId"] as? String, tokenId)
        XCTAssertEqual(contents["side"] as? Int, 0)
        XCTAssertEqual(contents["builder"] as? String, builder)
    }
}
