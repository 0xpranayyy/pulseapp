import Foundation

/// Who an order is placed for, and who signs it.
///
/// From https://docs.polymarket.com/trading/place-orders:
///
/// | Wallet  | type | `maker`        | order `signer`  |
/// |---------|------|----------------|-----------------|
/// | Deposit | 3    | Deposit Wallet | Deposit Wallet  |
/// | Proxy   | 1    | Proxy Wallet   | account signer  |
/// | Safe    | 2    | Safe Wallet    | account signer  |
/// | EOA     | 0    | EOA            | EOA             |
///
/// The account signer is always the key that actually produces signatures
/// and authenticates with the CLOB (`POLY_ADDRESS`); `wallet` holds the funds.
public struct TradingAccount: Sendable, Hashable, Codable {
    /// The key that signs (a Privy embedded wallet, or a wallet app's EOA).
    public let signer: String
    /// The account wallet holding funds and positions.
    public let wallet: String
    public let type: SignatureType

    public init(signer: String, wallet: String, type: SignatureType) {
        self.signer = signer
        self.wallet = wallet
        self.type = type
    }

    /// A plain EOA trading for itself.
    public static func eoa(_ address: String) -> TradingAccount {
        TradingAccount(signer: address, wallet: address, type: .eoa)
    }

    public var maker: String { wallet }

    /// The address that goes in the order's `signer` field.
    public var orderSigner: String {
        switch type {
        case .depositWallet, .eoa: wallet
        case .polyProxy, .polyGnosisSafe: signer
        }
    }

    /// Signs an order for this account.
    ///
    /// Deposit Wallets validate through ERC-7739, so the owner signs the
    /// order nested in a `TypedDataSign` and the result is wrapped; every
    /// other wallet type signs the exchange `Order` directly.
    public func sign(
        _ order: PolymarketOrder,
        exchange: ExchangeDomain,
        with signer: EthereumSigner
    ) async throws -> String {
        switch type {
        case .depositWallet:
            let inner = try await signer.signTypedData(
                TypedData.depositWalletOrder(order, exchange: exchange)
            )
            return try DepositWalletSignature.wrap(
                innerSignature: inner, order: order, exchange: exchange
            )
        case .eoa, .polyProxy, .polyGnosisSafe:
            return try await signer.signTypedData(TypedData.order(order, exchange: exchange))
        }
    }
}
