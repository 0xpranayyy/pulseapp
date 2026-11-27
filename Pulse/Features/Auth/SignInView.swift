import SwiftUI
import PulseCore
import PrivySDK

/// Sign-in.
///
/// Two steps, never more than one decision on screen: choose how, then prove
/// it. The field colour shifts between them, so moving forward is felt
/// rather than announced by a progress dot.
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

    /// Entry is teal; verification is green. The shift reads as progress.
    private var theme: Palette.Theme {
        if case .awaitingCode = auth.state { return Palette.theme(named: "green") }
        return Palette.theme(named: "teal")
    }
    private var ink: Color { theme.onField }

    var body: some View {
        ZStack {
            ColourField(colour: theme.screen)

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: Layout.Space.l) {
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
                    .padding(.bottom, Layout.Space.xl)
                }
                .scrollDismissesKeyboard(.interactively)

                footer
            }
        }
        .animation(reduceMotion ? nil : Motion.expressive, value: auth.state)
        .onChange(of: auth.state) { _, new in
            if case .signedIn = new { dismiss() }
            if case .awaitingCode = new { focus = .code }
        }
        .task { focus = .email }
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
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ink)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(ink.opacity(0.14)))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Back")

            Spacer()
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, Layout.Space.s)
    }

    // MARK: Step one

    private var entryStep: some View {
        VStack(alignment: .leading, spacing: Layout.Space.l) {
            VStack(alignment: .leading, spacing: Layout.Space.s) {
                Text("Sign in")
                    .font(Typography.subheadlineMedium)
                    .foregroundStyle(ink.opacity(0.6))
                Text("Start\ntrading.")
                    .font(Typography.hero)
                    .foregroundStyle(ink)
                    .lineSpacing(-4)
                Text("A wallet is created for you. No seed phrase to lose, no extension to install.")
                    .font(Typography.callout)
                    .foregroundStyle(ink.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Layout.Space.l)

            VStack(spacing: Layout.Space.m) {
                emailField

                Button {
                    Task { await auth.sendCode(to: email) }
                } label: {
                    if auth.state == .working {
                        ProgressView().tint(theme.onControl)
                    } else {
                        Text("Continue with email")
                    }
                }
                .buttonStyle(
                    .pill(.primary, tint: theme.control, onTint: theme.onControl, fullWidth: true)
                )
                .disabled(!isEmailPlausible || auth.state == .working)
            }

            separator

            VStack(spacing: Layout.Space.s) {
                oauthButton("Continue with Apple", icon: "apple.logo", provider: .apple)
                oauthButton("Continue with Google", icon: "g.circle.fill", provider: .google)
            }

            if !auth.isConfigured {
                notConfiguredNote
            }
        }
    }

    private var emailField: some View {
        HStack(spacing: Layout.Space.s) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ink.opacity(0.45))
            TextField("", text: $email, prompt: Text("you@example.com")
                .foregroundColor(ink.opacity(0.4)))
                .font(Typography.bodyMedium)
                .foregroundStyle(ink)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .email)
                .submitLabel(.continue)
                .onSubmit { Task { await auth.sendCode(to: email) } }
        }
        .padding(.horizontal, Layout.Space.l)
        .frame(height: 54)
        .background(
            RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
                .fill(ink.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
                .strokeBorder(ink.opacity(focus == .email ? 0.4 : 0), lineWidth: 1.5)
        )
        .animation(Motion.quick, value: focus)
    }

    private var separator: some View {
        HStack(spacing: Layout.Space.m) {
            Rectangle().fill(ink.opacity(0.18)).frame(height: 1)
            Text("or").font(Typography.caption).foregroundStyle(ink.opacity(0.5))
            Rectangle().fill(ink.opacity(0.18)).frame(height: 1)
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
                    .font(.system(size: 17, weight: .medium))
                Text(title)
                    .font(Typography.headline)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(ink.opacity(0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(auth.state == .working || !auth.isConfigured)
    }

    // MARK: Step two

    private func codeStep(destination: String) -> some View {
        VStack(alignment: .leading, spacing: Layout.Space.l) {
            VStack(alignment: .leading, spacing: Layout.Space.s) {
                Text("Check your email")
                    .font(Typography.subheadlineMedium)
                    .foregroundStyle(ink.opacity(0.6))
                Text("Enter the\ncode.")
                    .font(Typography.hero)
                    .foregroundStyle(ink)
                    .lineSpacing(-4)
                Text("Sent to \(destination).")
                    .font(Typography.callout)
                    .foregroundStyle(ink.opacity(0.7))
            }
            .padding(.top, Layout.Space.l)

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
            .buttonStyle(.pill(.quiet, tint: ink, fullWidth: true))
            .disabled(auth.state == .working)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: Layout.Space.s) {
            if auth.state == .working {
                ProgressView().tint(ink)
            }
            Text("By continuing you agree that prediction markets carry risk and positions can lose their full value.")
                .font(Typography.caption)
                .foregroundStyle(ink.opacity(0.5))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.bottom, Layout.Space.l)
    }

    private func errorNote(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Layout.Space.s) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Palette.caution)
            Text(message)
                .font(Typography.footnote)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Layout.Space.m)
        .background(
            RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
                .fill(Palette.caution.opacity(0.22))
        )
        .transition(.opacity)
    }

    private var notConfiguredNote: some View {
        Text("Sign-in isn't configured in this build. Set PRIVY_CLIENT_ID in Config.xcconfig.")
            .font(Typography.caption)
            .foregroundStyle(ink.opacity(0.6))
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

        return RoundedRectangle(cornerRadius: Layout.Radius.small, style: .continuous)
            .fill(ink.opacity(filled ? 0.2 : 0.1))
            .overlay(
                RoundedRectangle(cornerRadius: Layout.Radius.small, style: .continuous)
                    .strokeBorder(ink.opacity(isNext && isFocused ? 0.5 : 0), lineWidth: 1.5)
            )
            .overlay(
                Text(filled ? String(characters[index]) : "")
                    .font(Allo.tabular(.bold, size: 24, relativeTo: .title2))
                    .foregroundStyle(ink)
            )
            .frame(height: 58)
            .animation(Motion.quick, value: filled)
    }
}
