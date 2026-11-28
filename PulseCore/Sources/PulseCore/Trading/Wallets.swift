import Foundation

/// Polygon contract addresses, from `@polymarket/client`'s production
/// environment (verified against https://docs.polymarket.com/resources/contracts).
public enum PolymarketContracts {
    public static let collateralToken = "0xC011a7E12a19f7B1f670d46F03B03f3342E82DFB"   // pUSD
    public static let conditionalTokens = "0x4D97DCd97eC945f40cF65F87097ACe5EA0476045"
    public static let positionManager = "0x006F54F7f9A22e0000CC2AB60031000000ae9fEF"
    public static let standardExchange = "0xE111180000d2663C0091e4f400237545B87B996B"
    public static let negRiskExchange = "0xe2222d279d744050d28e00520010520000310F59"
    public static let exchangeV3 = "0xe3333700cA9d93003F00f0F71f8515005F6c00Aa"
    public static let collateralAdapter = "0xAdA100Db00Ca00073811820692005400218FcE1f"
    public static let negRiskCollateralAdapter = "0xadA2005600Dec949baf300f4C6120000bDB6eAab"
    public static let protocolV2Router = "0x12121212006e4CD160D18e3f00711DA5c3372600"
    public static let binaryModule = "0x1000008dD9001B968442c1000017eaE6E0dA00Ba"
    public static let negRiskModule = "0x200000900045e3B6259600682756002200028933"
    public static let autoRedeemOperator = "0xa1200000d0002264C9a1698e001292D00E1b00af"

    public static let depositWalletFactory = "0x00000000000Fb5C9ADea0298D729A0CB3823Cc07"
    public static let depositWalletBeacon = "0x7A18EDfe055488A3128f01F563e5B479D92ffc3a"
    public static let depositWalletImplementation = "0x58CA52ebe0DadfdF531Cde7062e76746de4Db1eB"
    public static let proxyFactory = "0xaB45c5A4B0c941a2F231C04C3f49182e1A254052"
    public static let proxyImplementation = "0x44e999d5c2F66Ef0861317f9A4805AC2e90aEB4f"
    public static let safeFactory = "0xaacFeEa03eb1561C4e67d661e40682Bd20E3541b"
    public static let safeInitCodeHash = "0x2bce2127ff07fb632d16c8347c4ebf501f4841168bed00d9e6ef715ddb6fcecf"
}

// MARK: - Wallet derivation

/// Every Polymarket account wallet sits at a CREATE2 address derived from
/// its signer, so the wallet — and therefore the wallet *type* — can be
/// computed without asking a node.
///
/// Port of `@polymarket/client`'s `wallet.ts` (`deriveBeaconDepositWalletAddress`,
/// `deriveUupsDepositWalletAddress`, `deriveSafeWalletAddress`,
/// `deriveProxyWalletAddress`, `classifyAccount`). Checked against vectors
/// produced by that code in `WalletDerivationTests`.
public enum WalletDerivation {

    /// A Deposit Wallet deployed today (beacon proxy). This is the address a
    /// new Pulse user's wallet is deployed to.
    public static func depositWallet(signer: String) -> String? {
        guard let args = depositWalletArgs(signer: signer) else { return nil }
        var initCode = prefix("0x6100523d8160233d3973", argsLength: args.count)
        guard let beacon = Data(hexString: PolymarketContracts.depositWalletBeacon) else { return nil }
        initCode += beacon
        initCode += hex("0x60195155f3363d3d373d3d363d602036600436635c60da")
        initCode += hex("0x1b60e01b36527fa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6c")
        initCode += hex("0xb3582b35133d50545afa5036515af43d6000803e604d573d6000fd5b3d6000f3")
        initCode += args
        return create2(
            from: PolymarketContracts.depositWalletFactory,
            salt: Keccak256.hash(args),
            initCodeHash: Keccak256.hash(initCode)
        )
    }

    /// A Deposit Wallet deployed before the June 2026 beacon upgrade (UUPS).
    public static func legacyDepositWallet(signer: String) -> String? {
        guard let args = depositWalletArgs(signer: signer),
              let implementation = Data(hexString: PolymarketContracts.depositWalletImplementation)
        else { return nil }
        var initCode = prefix("0x61003d3d8160233d3973", argsLength: args.count)
        initCode += implementation
        initCode += hex("0x6009")
        initCode += hex("0x5155f3363d3d373d3d363d7f360894a13ba1a3210667c828492db98dca3e2076")
        initCode += hex("0xcc3735a920a3ca505d382bbc545af43d6000803e6038573d6000fd5b3d6000f3")
        initCode += args
        return create2(
            from: PolymarketContracts.depositWalletFactory,
            salt: Keccak256.hash(args),
            initCodeHash: Keccak256.hash(initCode)
        )
    }

    /// A legacy Gnosis Safe, created for accounts that signed up with a
    /// wallet app.
    public static func safe(owner: String) -> String? {
        guard let encodedOwner = EIP712.encodeAddress(owner),
              let initCodeHash = Data(hexString: PolymarketContracts.safeInitCodeHash)
        else { return nil }
        return create2(
            from: PolymarketContracts.safeFactory,
            salt: Keccak256.hash(encodedOwner),
            initCodeHash: initCodeHash
        )
    }

    /// A legacy Proxy Wallet, created for Magic (email) sign-ups.
    public static func proxy(owner: String) -> String? {
        guard let ownerBytes = Data(hexString: owner), ownerBytes.count == 20 else { return nil }
        let template = "3d3d606380380380913d393d73%s5af4602a57600080fd5b602d8060366000396000f3363d3d373d3d3d363d73%s5af43d82803e903d91602b57fd5bf352e831dd00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000"
        var code = template
        if let range = code.range(of: "%s") {
            code.replaceSubrange(range, with: PolymarketContracts.proxyFactory.dropFirst(2).lowercased())
        }
        if let range = code.range(of: "%s") {
            code.replaceSubrange(range, with: PolymarketContracts.proxyImplementation.dropFirst(2).lowercased())
        }
        guard let bytecode = Data(hexString: code) else { return nil }
        return create2(
            from: PolymarketContracts.proxyFactory,
            salt: Keccak256.hash(ownerBytes),       // abi.encodePacked(address)
            initCodeHash: Keccak256.hash(bytecode)
        )
    }

    /// Which kind of Polymarket wallet `wallet` is for `signer`, or nil when
    /// it is none of them (for example, a wallet a session key trades for).
    public static func classify(signer: String, wallet: String) -> SignatureType? {
        func same(_ a: String?) -> Bool { a?.lowercased() == wallet.lowercased() }
        if signer.lowercased() == wallet.lowercased() { return .eoa }
        if same(depositWallet(signer: signer)) || same(legacyDepositWallet(signer: signer)) {
            return .depositWallet
        }
        if same(safe(owner: signer)) { return .polyGnosisSafe }
        if same(proxy(owner: signer)) { return .polyProxy }
        return nil
    }

    // MARK: Helpers

    /// `abi.encode(address factory, bytes32 walletId)`, walletId = left-padded signer.
    private static func depositWalletArgs(signer: String) -> Data? {
        guard let factory = EIP712.encodeAddress(PolymarketContracts.depositWalletFactory),
              let walletId = EIP712.encodeAddress(signer) else { return nil }
        return factory + walletId
    }

    /// Solady's ten-byte clone prefix, with the args length added into its
    /// PUSH2 operand (`prefix + (argsLength << 56)`).
    ///
    /// Byte arithmetic rather than `UInt128`, which needs iOS 18. Bit 56 of a
    /// ten-byte big-endian number is byte 2, so the length is added there
    /// with the carry going into byte 1.
    private static func prefix(_ hex: String, argsLength: Int) -> Data {
        var bytes = [UInt8](Data(hexString: hex) ?? Data())
        guard bytes.count == 10 else { return Data() }
        var carry = argsLength
        for index in stride(from: 2, through: 0, by: -1) where carry > 0 {
            let sum = Int(bytes[index]) + (carry & 0xff)
            bytes[index] = UInt8(sum & 0xff)
            carry = (carry >> 8) + (sum >> 8)
        }
        return Data(bytes)
    }

    private static func hex(_ s: String) -> Data { Data(hexString: s) ?? Data() }

    /// `keccak256(0xff ‖ from ‖ salt ‖ initCodeHash)[12...]`
    static func create2(from: String, salt: Data, initCodeHash: Data) -> String? {
        guard let deployer = Data(hexString: from), deployer.count == 20 else { return nil }
        var payload = Data([0xff])
        payload += deployer
        payload += salt
        payload += initCodeHash
        return "0x" + Keccak256.hash(payload).suffix(20).hexString(prefixed: false)
    }
}

// MARK: - Contract calls

/// One call in a Deposit Wallet batch.
public struct ContractCall: Sendable, Hashable, Codable {
    public let target: String
    public let value: String
    public let data: String

    public init(target: String, value: String = "0", data: String) {
        self.target = target
        self.value = value
        self.data = data
    }

    /// `approve(address spender, uint256 amount)` for the maximum amount.
    public static func approveMax(token: String, spender: String) -> ContractCall? {
        guard let encodedSpender = EIP712.encodeAddress(spender) else { return nil }
        let data = Data([0x09, 0x5e, 0xa7, 0xb3]) + encodedSpender + Data(repeating: 0xff, count: 32)
        return ContractCall(target: token, data: data.hexString(prefixed: true))
    }

    /// `setApprovalForAll(address operator, bool approved)`.
    public static func setApprovalForAll(token: String, operator op: String, approved: Bool = true) -> ContractCall? {
        guard let encodedOperator = EIP712.encodeAddress(op) else { return nil }
        let data = Data([0xa2, 0x2c, 0xb4, 0x65]) + encodedOperator + EIP712.encodeBool(approved)
        return ContractCall(target: token, data: data.hexString(prefixed: true))
    }
}

/// The approvals a Deposit Wallet needs before it can trade.
///
/// Mirrors `getRequiredTradingApprovals` in `@polymarket/client`, without the
/// perps deposit contract Pulse does not use. Approving everything once is
/// what the SDK does; checking each allowance first would cost a node query
/// per approval for no user-visible benefit.
public enum TradingApprovals {
    public static var calls: [ContractCall] {
        let c = PolymarketContracts.self
        let erc20Spenders = [
            c.standardExchange, c.negRiskExchange, c.collateralAdapter,
            c.negRiskCollateralAdapter, c.protocolV2Router, c.exchangeV3
        ]
        let ctfOperators = [
            c.standardExchange, c.negRiskExchange, c.collateralAdapter, c.negRiskCollateralAdapter,
            c.autoRedeemOperator, c.binaryModule, c.negRiskModule
        ]
        let positionOperators = [c.protocolV2Router, c.exchangeV3, c.autoRedeemOperator]

        return erc20Spenders.compactMap { ContractCall.approveMax(token: c.collateralToken, spender: $0) }
            + ctfOperators.compactMap { ContractCall.setApprovalForAll(token: c.conditionalTokens, operator: $0) }
            + positionOperators.compactMap { ContractCall.setApprovalForAll(token: c.positionManager, operator: $0) }
    }
}

// MARK: - Deposit Wallet batch

public extension TypedData {
    /// `Batch(address wallet,uint256 nonce,uint256 deadline,Call[] calls)`,
    /// signed by the Deposit Wallet's owner to authorise a relayed batch.
    static func depositWalletBatch(
        wallet: String,
        nonce: String,
        deadline: String,
        calls: [ContractCall]
    ) -> TypedData {
        TypedData(
            domain: EIP712.Domain(name: "DepositWallet", version: "1", chainId: 137, verifyingContract: wallet),
            types: [
                "Batch": [
                    Field("wallet", "address"), Field("nonce", "uint256"),
                    Field("deadline", "uint256"), Field("calls", "Call[]")
                ],
                "Call": [Field("target", "address"), Field("value", "uint256"), Field("data", "bytes")]
            ],
            primaryType: "Batch",
            message: [
                "wallet": .string(wallet),
                "nonce": .string(nonce),
                "deadline": .string(deadline),
                "calls": .array(calls.map {
                    .object(["target": .string($0.target), "value": .string($0.value), "data": .string($0.data)])
                })
            ]
        )
    }
}
