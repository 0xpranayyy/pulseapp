import Foundation
import Observation
import PulseCore
import PrivySDK

/// Wallet and identity, via Privy.
///
/// Replaces the private-key import screen entirely. Nothing in the app ever
/// sees key material now: Privy holds the embedded wallet and returns
/// signatures, so the worst case for a lost device is a session, not a key.
///
/// The signing path is unchanged. `PulseCore` still builds the EIP-712
/// digest — the Keccak, domain separator and order struct work that is
/// covered by tests — and Privy only performs the final secp256k1 operation
/// over that digest. Swapping the signer did not move any logic that decides
/// what gets signed.
@MainActor
@Observable
final class PrivyAuth {

    enum State: Equatable {
        case starting
        case signedOut
        /// A code has been sent and we are waiting for the user to enter it.
        case awaitingCode(destination: String)
        case working
        case signedIn(address: String)

        var address: String? {
            if case .signedIn(let address) = self { return address }
            return nil
        }
    }

    private(set) var state: State = .starting
    private(set) var lastError: String?

    private let privy: (any Privy)?
    private var wallet: (any EmbeddedEthereumWallet)?

    /// The URL scheme OAuth returns to. Must match a CFBundleURLSchemes entry.
    private let callbackScheme: String

    init(configuration: PulseConfiguration, callbackScheme: String = "pulse") {
        self.callbackScheme = callbackScheme

        guard let appId = configuration.privyAppId,
              let clientId = configuration.privyClientId else {
            // Running without Privy configured is a valid state: browsing
            // needs no account, so the app stays usable and only trading is
            // unavailable.
            self.privy = nil
            self.state = .signedOut
            return
        }

        self.privy = PrivySDK.Privy.initialize(
            config: PrivyConfig(appId: appId, appClientId: clientId)
        )
    }

    var isConfigured: Bool { privy != nil }

    // MARK: Session

    /// Restores an existing session. Privy persists its own, so a returning
    /// user is signed in before the first screen appears.
    func restore() async {
        guard let privy else { return }
        switch await privy.getAuthState() {
        case .authenticated(let user):
            await adopt(user)
        case .unauthenticated, .notReady, .authenticatedUnverified:
            state = .signedOut
        }
    }

    // MARK: Email

    func sendCode(to email: String) async {
        guard let privy else { return }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        state = .working
        lastError = nil
        do {
            try await privy.email.sendCode(to: address)
            state = .awaitingCode(destination: address)
        } catch {
            lastError = Self.message(for: error)
            state = .signedOut
        }
    }

    func submit(code: String, for email: String) async {
        guard let privy else { return }
        state = .working
        lastError = nil
        do {
            let user = try await privy.email.loginWithCode(code, sentTo: email)
            await adopt(user)
        } catch {
            lastError = Self.message(for: error)
            // Back to the code screen, not all the way out: the user has
            // a code in hand and most likely just mistyped it.
            state = .awaitingCode(destination: email)
        }
    }

    // MARK: OAuth

    func signIn(with provider: OAuthProvider) async {
        guard let privy else { return }
        state = .working
        lastError = nil
        do {
            let user = try await privy.oAuth.login(
                with: provider, appUrlScheme: callbackScheme
            )
            await adopt(user)
        } catch {
            lastError = Self.message(for: error)
            state = .signedOut
        }
    }

    // MARK: Sign out

    func signOut() async {
        guard let privy, let user = await privy.getUser() else {
            state = .signedOut
            return
        }
        await user.logout()
        wallet = nil
        state = .signedOut
    }

    // MARK: Wallet

    /// Adopts a signed-in user, creating the embedded wallet on first login.
    private func adopt(_ user: any PrivyUser) async {
        do {
            let existing = user.embeddedEthereumWallets.first
            let resolved = try await existing ?? user.createEthereumWallet()
            wallet = resolved
            state = .signedIn(address: resolved.address)
            lastError = nil
        } catch {
            lastError = Self.message(for: error)
            state = .signedOut
        }
    }

    /// A signer backed by the embedded wallet, for `TradingService`.
    func signer() throws -> any EthereumSigner {
        guard let wallet else { throw SignerError.noKeyAvailable }
        return PrivySigner(wallet: wallet)
    }

    // MARK: Errors

    /// Privy's errors are not written for end users, so anything unrecognised
    /// becomes a plain sentence rather than a leaked type name.
    private static func message(for error: Error) -> String {
        let text = String(describing: error).lowercased()
        if text.contains("code") && (text.contains("invalid") || text.contains("expired")) {
            return "That code didn't work. Check it, or send a new one."
        }
        if text.contains("network") || text.contains("connection") {
            return "Network problem. Check your connection and try again."
        }
        if text.contains("cancel") {
            return "Sign-in was cancelled."
        }
        return "Couldn't sign in. Try again."
    }
}

// MARK: - Signer

/// Signs EIP-712 digests with a Privy embedded wallet.
///
/// `secp256k1Sign` takes the 32-byte digest directly, which is what the
/// order flow needs: `PolymarketOrder` has already produced the digest and
/// must not have it re-hashed. Using `personalSign` here would prefix the
/// Ethereum signed-message header and produce a signature the exchange
/// rejects.
struct PrivySigner: EthereumSigner {
    let wallet: any EmbeddedEthereumWallet

    var address: String {
        get async throws { wallet.address }
    }

    func signDigest(_ digest: Data) async throws -> String {
        guard digest.count == 32 else {
            throw SignerError.invalidDigestLength(digest.count)
        }

        let signature = try await wallet.provider.request(
            .secp256k1Sign(hash: digest.hexString(prefixed: true))
        )

        guard let bytes = Data(hexString: signature), bytes.count == 65 else {
            throw SignerError.signingFailed(
                "expected a 65-byte signature, got \(signature.count) characters"
            )
        }

        // Privy may return v as 0/1 rather than 27/28. Both appear in the
        // wild; the exchange only accepts the latter.
        var normalised = Data(bytes.prefix(64))
        let v = bytes[bytes.index(bytes.startIndex, offsetBy: 64)]
        normalised.append(v < 27 ? v &+ 27 : v)
        return normalised.hexString(prefixed: true)
    }
}
