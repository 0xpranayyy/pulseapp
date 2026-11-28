import SwiftUI
import AuthenticationServices
import PulseCore
import PrivySDK

/// Sign-in.
///
/// Two steps, never more than one decision on screen: choose how, then prove
/// it. Both sit on the meadow under the same sky, with Pip holding up the
/// wallet you are about to get — the brand's one moment before the app gets
/// down to markets.
///
/// There is no password and no seed phrase to write down — Privy holds the
/// wallet — so the screen can be about getting in rather than about warning
/// people what they are about to lose.
struct SignInView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var email = ""
    @State private var code = ""
    @FocusState private var focus: Field?

    private enum Field { case email, code }

    private var auth: PrivyAuth { environment.auth }

    /// Everything here is white on green; the one exception is text inside
    /// white surfaces, which is navy.
    private let ink: Color = .white

    var body: some View {
        ZStack(alignment: .top) {
            MeadowGround().ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: Layout.Space.l) {
                        scene

                        Group {
                            switch auth.state {
                            case .awaitingCode(let destination):
                                codeStep(destination: destination)
                            default:
                                entryStep
                            }

                            if let error = auth.lastError {
                                errorNote(error)
                            }
                        }
                        .padding(.horizontal, Layout.gutter)
                    }
                    .padding(.bottom, Layout.Space.xl)
                }
                .scrollDismissesKeyboard(.interactively)
                .ignoresSafeArea(edges: .top)

                footer
            }

            header
        }
        .animation(reduceMotion ? nil : Motion.expressive, value: auth.state)
        .onChange(of: auth.state) { _, new in
            if case .signedIn = new { dismiss() }
            if case .awaitingCode = new { focus = .code }
        }
    }

    // MARK: Scene

    /// Sky, hills and Pip with the wallet card. Scrolls away with the
    /// content, so the keyboard never pushes the field off screen.
    private var scene: some View {
        ZStack(alignment: .bottom) {
            MeadowScene()
            Pip(pose: isAwaitingCode ? .hello : .holdingCard, size: 190)
                .padding(.bottom, 26)
                .animation(nil, value: isAwaitingCode)
        }
        .frame(height: 330)
    }

    private var isAwaitingCode: Bool {
        if case .awaitingCode = auth.state { return true }
        return false
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button {
                if case .awaitingCode = auth.state {
                    code = ""
                    Task { await auth.restore() }
                } else {
                    dismiss()
                }
            } label: {
                // White on the sky: a white disc with navy, not white type.
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(Brand.ink)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(.white))
                    .background(Circle().fill(Brand.cloudShade).offset(y: 3))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(isAwaitingCode ? "Use a different email" : "Close")

            Spacer()
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, Layout.Space.s)
    }

    // MARK: Step one

    private var entryStep: some View {
        VStack(spacing: Layout.Space.l) {
            heading(
                "Start trading.",
                "A wallet is created for you. No seed phrase to lose, no extension to install."
            )

            VStack(spacing: Layout.Space.m) {
                emailField

                Button {
                    Task { await auth.sendCode(to: email) }
                } label: {
                    if auth.state == .working {
                        ProgressView().tint(Brand.yes)
                    } else {
                        Text("Continue with email")
                    }
                }
                .buttonStyle(.chunkyOnMeadow)
                .disabled(!isEmailPlausible || auth.state == .working)
            }

            separator

            VStack(spacing: Layout.Space.m) {
                AppleSignInButton(cornerRadius: 27) {
                    Task { await auth.signIn(with: .apple) }
                }
                .frame(height: 54)
                .disabled(auth.state == .working || !auth.isConfigured)
                .opacity(auth.state == .working || !auth.isConfigured ? 0.5 : 1)

                oauthButton("Continue with Google", icon: "g.circle.fill", provider: .google)
            }

            if !auth.isConfigured {
                notConfiguredNote
            }
        }
    }

    private func heading(_ title: String, _ body: String) -> some View {
        VStack(spacing: Layout.Space.s) {
            Text(title)
                .font(Typography.hero)
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
                .accessibilityAddTraits(.isHeader)
            Text(body)
                .font(BrandFont.ui(.extrabold, size: 18, relativeTo: .body))
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var emailField: some View {
        HStack(spacing: Layout.Space.s) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(ink)
            TextField("", text: $email, prompt: Text("you@example.com")
                .foregroundColor(ink.opacity(0.8)))
                .font(BrandFont.ui(.extrabold, size: 17, relativeTo: .body))
                .foregroundStyle(ink)
                .tint(Brand.lime)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .email)
                .submitLabel(.continue)
                .onSubmit { Task { await auth.sendCode(to: email) } }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(Capsule().fill(.white.opacity(0.18)))
        .overlay(
            Capsule().strokeBorder(.white.opacity(focus == .email ? 1 : 0.5), lineWidth: 2)
        )
        .animation(Motion.quick, value: focus)
        .accessibilityLabel("Email address")
    }

    private var separator: some View {
        HStack(spacing: Layout.Space.m) {
            Capsule().fill(.white.opacity(0.3)).frame(height: 2)
            Text("or").font(Typography.captionMedium).foregroundStyle(ink)
            Capsule().fill(.white.opacity(0.3)).frame(height: 2)
        }
    }

    private func oauthButton(
        _ title: String, icon: String, provider: OAuthProvider
    ) -> some View {
        Button {
            Task { await auth.signIn(with: provider) }
        } label: {
            HStack(spacing: Layout.Space.s) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                Text(title)
            }
        }
        .buttonStyle(.chunky(
            Brand.meadowShadow, ink: .white, shadow: Color(hex: "124A0A"),
            height: 54, font: Typography.headline
        ))
        .disabled(auth.state == .working || !auth.isConfigured)
    }

    // MARK: Apple

    /// Apple's own button, not a facsimile.
    ///
    /// Sign in with Apple has to use `ASAuthorizationAppleIDButton`: the HIG
    /// requires that exact mark, App Review rejects look-alikes, and the Privy
    /// SDK drives `ASAuthorizationController` behind it. A styled SF Symbol
    /// passes none of those tests, however well it matches the rest of the
    /// screen. Corner radius is the one thing Apple lets us set, so it meets
    /// the capsule next to it.
    private struct AppleSignInButton: UIViewRepresentable {
        let cornerRadius: CGFloat
        let action: () -> Void

        @Environment(\.colorScheme) private var colorScheme

        func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
            let button = ASAuthorizationAppleIDButton(
                authorizationButtonType: .continue,
                authorizationButtonStyle: colorScheme == .dark ? .white : .black
            )
            button.cornerRadius = cornerRadius
            button.addTarget(
                context.coordinator,
                action: #selector(Coordinator.tapped),
                for: .touchUpInside
            )
            return button
        }

        func updateUIView(_ view: ASAuthorizationAppleIDButton, context: Context) {
            context.coordinator.action = action
        }

        func makeCoordinator() -> Coordinator { Coordinator(action: action) }

        final class Coordinator {
            var action: () -> Void
            init(action: @escaping () -> Void) { self.action = action }
            @objc func tapped() { action() }
        }
    }

    // MARK: Step two

    private func codeStep(destination: String) -> some View {
        VStack(spacing: Layout.Space.l) {
            heading("Enter the code.", "Sent to \(destination).")

            CodeField(code: $code, ink: ink, length: 6)
                .focused($focus, equals: .code)
                .onChange(of: code) { _, value in
                    // Six digits is the whole input, so submitting on the
                    // last one saves a tap nobody needs to make.
                    if value.count == 6 {
                        Task { await auth.submit(code: value, for: destination) }
                    }
                }

            Button("Send a new code") {
                code = ""
                Task { await auth.sendCode(to: destination) }
            }
            .font(Typography.buttonSmall)
            .foregroundStyle(ink)
            .underline()
            .frame(minHeight: 44)
            .disabled(auth.state == .working)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: Layout.Space.s) {
            if auth.state == .working {
                ProgressView().tint(ink)
            }
            Text("Prediction markets carry risk. A position can lose its full value.")
                .font(Typography.captionMedium)
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, Layout.Space.s)
        .padding(.bottom, Layout.Space.m)
    }

    /// A white card, so the exchange's message reads in navy rather than
    /// fighting the grass.
    private func errorNote(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Layout.Space.s) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Palette.caution)
            Text(message)
                .font(Typography.footnote)
                .foregroundStyle(Brand.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Layout.Space.m)
        .chunkyCard(shadow: Brand.meadowShadow, radius: Layout.Radius.medium)
        .transition(.opacity)
    }

    private var notConfiguredNote: some View {
        Text("Sign-in isn't configured in this build. Set PRIVY_CLIENT_ID in Config.xcconfig.")
            .font(Typography.captionMedium)
            .foregroundStyle(ink)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Deliberately loose. Rejecting addresses on a regex annoys people with
    /// valid ones; Privy decides whether it can actually send.
    private var isEmailPlausible: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = trimmed.firstIndex(of: "@") else { return false }
        return at > trimmed.startIndex && trimmed[at...].contains(".")
    }
}

// MARK: - Code field

/// Six boxes backed by one hidden text field.
///
/// Six separate fields fight the keyboard and break paste; one field with a
/// drawn representation keeps autofill from Messages working, which is how
/// most people enter these.
struct CodeField: View {
    @Binding var code: String
    var ink: Color
    var length: Int = 6

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .opacity(0.01)
                .onChange(of: code) { _, value in
                    let digits = value.filter(\.isNumber)
                    code = String(digits.prefix(length))
                }

            HStack(spacing: Layout.Space.s) {
                ForEach(0..<length, id: \.self) { index in
                    box(at: index)
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .onAppear { isFocused = true }
        .accessibilityElement()
        .accessibilityLabel("Verification code")
        .accessibilityValue(code.isEmpty ? "empty" : code.map(String.init).joined(separator: " "))
    }

    private func box(at index: Int) -> some View {
        let characters = Array(code)
        let filled = index < characters.count
        let isNext = index == characters.count

        return RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(ink.opacity(filled ? 0.28 : 0.16))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(ink.opacity(isNext && isFocused ? 1 : 0.4), lineWidth: 2)
            )
            .overlay(
                Text(filled ? String(characters[index]) : "")
                    .font(BrandFont.ui(.black, size: 24, relativeTo: .title2))
                    .foregroundStyle(ink)
            )
            .frame(height: 58)
            .animation(Motion.quick, value: filled)
    }
}
