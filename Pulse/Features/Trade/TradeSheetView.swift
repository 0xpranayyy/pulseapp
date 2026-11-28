import SwiftUI
import PulseCore

/// The order entry sheet.
///
/// A white sheet rising over the market, with Pip peeking over its top edge.
/// Green and red appear only where they mean Yes and No; the controls are
/// navy.
///
/// The ordering is deliberate: choose the outcome, choose the side, then the
/// amount, and only then see what it costs. The quote sits directly under
/// the amount so the consequence of a keystroke is visible without scrolling,
/// and the confirm step renders the very same `PreparedOrder` that gets
/// signed — nothing is recomputed between seeing it and sending it.
struct TradeSheet: View {
    let request: TradeRequest

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var model: TradeViewModel?
    @FocusState private var amountFocused: Bool

    private var theme: Palette.Theme { Palette.brand }
    private var ink: Color { theme.onField }
    private var isYes: Bool { request.isYes }
    /// The outcome's own colour: green for Yes, red for No.
    private var outcomeTint: Color { isYes ? Brand.yes : Brand.no }
    private var outcomeShadow: Color { isYes ? Brand.yesDeep : Brand.noDeep }
    /// The other side of this market, for "If No, you lose…".
    private var otherLabel: String {
        let labels = request.market.outcomeLabels
        return isYes ? (labels.count > 1 ? labels[1] : "No") : (labels.first ?? "Yes")
    }

    var body: some View {
        ZStack {
            if let model {
                content(model)
            } else {
                ProgressView()
                    .tint(ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34, style: .continuous)
                .fill(Brand.card)
                .ignoresSafeArea(edges: .bottom)
        )
        // Pip peeks over the sheet's top edge while you build the order; the
        // result screens show their own Pip, so this one steps away.
        .overlay(alignment: .top) {
            if showsPeek {
                Pip(pose: .peek, size: 96, shadow: nil)
                    .offset(y: -67)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .padding(.top, 64)
        .task {
            if model == nil {
                model = TradeViewModel(
                    request: request,
                    clob: environment.clob,
                    data: environment.data,
                    trading: environment.trading,
                    session: environment.session,
                    settings: environment.settings
                )
                await model?.load()
            }
        }
    }

    private var showsPeek: Bool {
        guard let model else { return true }
        switch model.phase {
        case .succeeded, .failed: return false
        default: return true
        }
    }

    @ViewBuilder
    private func content(_ model: TradeViewModel) -> some View {
        switch model.phase {
        case .succeeded(let orderId):
            OrderResultView(
                outcome: .success(orderId: orderId),
                summary: model.prepared,
                outcomeLabel: request.outcomeLabel,
                theme: theme
            ) { dismiss() }
                .onAppear { Haptics.success(enabled: environment.settings.hapticsEnabled) }

        case .failed(let message):
            OrderResultView(
                outcome: .failure(message: message),
                summary: model.prepared,
                outcomeLabel: request.outcomeLabel,
                theme: theme
            ) { model.reset() }
                .onAppear { Haptics.error(enabled: environment.settings.hapticsEnabled) }

        case .confirming:
            confirmation(model)

        case .editing, .submitting:
            editor(model)
        }
    }

    // MARK: Editor

    private func editor(_ model: TradeViewModel) -> some View {
        @Bindable var model = model

        return VStack(spacing: 0) {
            handle

            ScrollView {
                VStack(spacing: Layout.Space.l) {
                    identity
                    sideSelector(model)
                    amountField(model)
                    quotePanel(model)

                    if let issue = model.blockingIssue, model.amount > 0 || !model.amountText.isEmpty {
                        issueBanner(issue)
                    }

                    if !model.canTrade { connectPrompt }

                    RiskNotice(compact: true, ink: ink)
                }
                .padding(.horizontal, Layout.gutter)
                .padding(.bottom, Layout.Space.xl)
            }
            .scrollDismissesKeyboard(.interactively)

            actionBar(model)
        }
    }

    private var handle: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(Typography.subheadlineMedium)
                .foregroundStyle(Brand.inkSecondary)
            Spacer()
            Capsule()
                .fill(Brand.hairline)
                .frame(width: 44, height: 5)
            Spacer()
            // Balances the cancel button so the grabber stays centred.
            Text("Cancel")
                .font(Typography.subheadlineMedium)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, Layout.Space.m)
        .padding(.bottom, Layout.Space.s)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: Layout.Space.m) {
            HStack(spacing: Layout.Space.m) {
                MarketArt(
                    url: request.event.imageURL,
                    category: request.event.category,
                    fallbackText: request.event.displayTitle,
                    size: 52,
                    cornerRadius: 15
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(request.event.displayTitle)
                        .font(Typography.headline)
                        .foregroundStyle(ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if request.event.isMultiOutcome {
                        Text(request.market.displayTitle)
                            .font(Typography.caption)
                            .foregroundStyle(Brand.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
                Text(request.outcomeLabel)
                    .font(Typography.buttonSmall)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(outcomeTint))
                    .accessibilityLabel("Outcome: \(request.outcomeLabel)")
            }
            if let p = request.market.yesProbability {
                TugBar(probability: p, size: .card)
            }
        }
    }

    /// Side and order type.
    ///
    /// Pills rather than a system segmented control: buy versus sell is
    /// consequential enough to deserve a target you cannot miss.
    private func sideSelector(_ model: TradeViewModel) -> some View {
        @Bindable var model = model

        return VStack(spacing: Layout.Space.m) {
            HStack(spacing: Layout.Space.s) {
                sidePill("Buy", side: .buy, model: model)
                sidePill("Sell", side: .sell, model: model)
            }

            HStack(spacing: Layout.Space.s) {
                ForEach(TradeViewModel.Mode.allCases) { mode in
                    Button {
                        model.mode = mode
                        model.recalculate()
                        Haptics.selection(enabled: environment.settings.hapticsEnabled)
                    } label: {
                        Text(mode.rawValue)
                            .font(Typography.subheadlineMedium)
                            .foregroundStyle(model.mode == mode ? theme.onControl : ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(
                                Capsule().fill(
                                    model.mode == mode ? theme.control : Brand.cardSunken
                                )
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(model.mode == mode ? [.isSelected] : [])
                }
            }
        }
    }

    private func sidePill(
        _ title: String, side: OrderSide, model: TradeViewModel
    ) -> some View {
        let selected = model.side == side
        // Navy, not green and red: buy and sell are not Yes and No.
        let tint = Brand.ink

        return Button {
            model.side = side
            model.recalculate()
            Haptics.selection(enabled: environment.settings.hapticsEnabled)
        } label: {
            Text(title)
                .font(Typography.headline)
                .foregroundStyle(selected ? .white : ink)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Capsule().fill(selected ? tint : Brand.cardSunken))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Amount

    private func amountField(_ model: TradeViewModel) -> some View {
        @Bindable var model = model
        let isBuy = model.side == .buy

        return VStack(spacing: Layout.Space.m) {
            HStack {
                Text(isBuy ? "You spend" : "You sell")
                    .font(Typography.subheadlineMedium)
                    .foregroundStyle(Brand.inkSecondary)
                Spacer()
                Text(availabilityText(model))
                    .font(Typography.caption)
                    .foregroundStyle(Brand.inkSecondary)
            }

            if model.mode == .market {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    if isBuy {
                        Text("$")
                            .font(Typography.currencyLarge)
                            .foregroundStyle(Brand.inkTertiary)
                    }
                    TextField("0", text: $model.amountText)
                        .font(Typography.currencyLarge)
                        .foregroundStyle(ink)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .multilineTextAlignment(isBuy ? .leading : .trailing)
                        .onChange(of: model.amountText) { _, _ in model.recalculate() }
                    if !isBuy {
                        Text("shares")
                            .font(Typography.headline)
                            .foregroundStyle(Brand.inkTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: Layout.Space.s) {
                    ForEach(model.presets, id: \.self) { preset in
                        Button {
                            model.amountText = isBuy
                                ? String(Int(preset))
                                : String(Int((model.heldShares ?? 0) * preset / 100))
                            model.recalculate()
                            Haptics.selection(enabled: environment.settings.hapticsEnabled)
                        } label: {
                            Text(isBuy ? "$\(Int(preset))" : "\(Int(preset))%")
                                .font(Typography.subheadlineMedium)
                                .foregroundStyle(ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(Capsule().fill(Brand.cardSunken))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            } else {
                limitFields(model)
            }
        }
        .padding(Layout.Space.l)
        // A white card on a white sheet needs an edge as well as its shadow.
        .overlay(
            RoundedRectangle(cornerRadius: Layout.Radius.large, style: .continuous)
                .strokeBorder(Brand.hairline, lineWidth: 2)
        )
        .fieldPanel(theme, radius: Layout.Radius.large)
    }

    private func availabilityText(_ model: TradeViewModel) -> String {
        if model.side == .buy {
            return model.availableBalance.map { "\(Format.currency($0)) available" }
                ?? "Balance unavailable"
        }
        return model.heldShares.map { "\(Format.shares($0)) held" } ?? "No position"
    }

    private func limitFields(_ model: TradeViewModel) -> some View {
        @Bindable var model = model

        return VStack(spacing: Layout.Space.m) {
            HStack(spacing: Layout.Space.m) {
                labelledField("Price", suffix: "¢") {
                    TextField("0", text: $model.limitPriceText)
                        .keyboardType(.numberPad)
                        .onChange(of: model.limitPriceText) { _, _ in model.recalculate() }
                }
                labelledField("Shares", suffix: nil) {
                    TextField("0", text: $model.limitSharesText)
                        .keyboardType(.decimalPad)
                        .onChange(of: model.limitSharesText) { _, _ in model.recalculate() }
                }
            }
            HStack {
                Text("Tick \(Format.cents(request.market.tickSize)) · min \(Format.shares(request.market.minimumOrderSize)) shares")
                    .font(Typography.caption)
                    .foregroundStyle(Brand.inkTertiary)
                Spacer()
            }
        }
    }

    private func labelledField<Field: View>(
        _ label: String, suffix: String?, @ViewBuilder field: () -> Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(Typography.overline)
                .tracking(0.8)
                .foregroundStyle(Brand.inkTertiary)
            HStack(spacing: 3) {
                field()
                    .font(Typography.currency)
                    .foregroundStyle(ink)
                if let suffix {
                    Text(suffix)
                        .font(Typography.currency)
                        .foregroundStyle(Brand.inkTertiary)
                }
            }
            .padding(.horizontal, Layout.Space.m)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: Layout.Radius.small, style: .continuous)
                    .fill(Brand.cardSunken)
            )
        }
    }

    // MARK: Quote

    /// What the order actually does, directly under the amount.
    ///
    /// Shares and payout lead because they are what the trade is for. Fees
    /// and price impact are present but quiet — they matter, and hiding them
    /// behind a disclosure would be the dishonest choice.
    @ViewBuilder
    private func quotePanel(_ model: TradeViewModel) -> some View {
        if let order = model.prepared {
            VStack(spacing: Layout.Space.m) {
                HStack(alignment: .top, spacing: Layout.Space.m) {
                    quoteFigure(
                        model.side == .buy ? "You get" : "You receive",
                        model.side == .buy
                            ? "\(Format.shares(order.shares)) sh"
                            : Format.currency(order.netProceeds),
                        caption: order.isMarketOrder
                            ? "est. at \(Format.cents(order.price))"
                            : "at \(Format.cents(order.price))"
                    )
                    quoteFigure(
                        "If \(request.outcomeLabel), you get",
                        Format.currency(order.payoutIfWon),
                        caption: model.side == .buy
                            ? profitCaption(order) : nil
                    )
                }

                Rectangle().fill(Brand.hairline).frame(height: 2)

                VStack(spacing: 8) {
                    quoteRow(
                        model.side == .buy ? "Total cost" : "Proceeds",
                        Format.currency(
                            model.side == .buy ? order.totalCost : order.netProceeds
                        ),
                        emphasised: true
                    )
                    if order.fees.total > 0 {
                        quoteRow("Est. fees", Format.currency(order.fees.total))
                    }
                    if model.side == .buy, order.totalCost > 0 {
                        // Said plainly, beside the payout rather than in a
                        // footnote: what happens if the other side wins.
                        quoteRow(
                            "If \(otherLabel), you lose",
                            Format.currency(order.totalCost),
                            tint: Brand.no
                        )
                    }
                    if let quote = order.quote,
                       let slippage = quote.slippage, slippage > 0.005 {
                        quoteRow(
                            "Price impact",
                            Format.percentChange(slippage),
                            tint: slippage > 0.03 ? Palette.caution : nil
                        )
                    }
                }
            }
            .padding(Layout.Space.l)
            // The summary sits on the sunken inset, as a receipt does.
            .fieldPanel(theme, radius: Layout.Radius.large, strength: 0.07)
            .transition(.opacity)
        } else {
            // A placeholder of the same height, so the sheet does not jump
            // the moment a quote appears.
            VStack(spacing: Layout.Space.s) {
                Text(model.canTrade ? "Enter an amount to see the quote"
                                    : "Connect a wallet to trade")
                    .font(Typography.subheadline)
                    .foregroundStyle(Brand.inkTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .fieldPanel(theme, radius: Layout.Radius.large, strength: 0.07)
        }
    }

    private func profitCaption(_ order: TradingService.PreparedOrder) -> String? {
        let profit = order.payoutIfWon - order.totalCost
        guard order.totalCost > 0 else { return nil }
        return "\(Format.currency(profit, showSign: true)) profit"
    }

    private func quoteFigure(
        _ label: String, _ value: String, caption: String?, tint: Color? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(Typography.overline)
                .tracking(0.8)
                .foregroundStyle(Brand.inkTertiary)
            Text(value)
                .font(Typography.probability)
                .foregroundStyle(tint ?? ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(Typography.caption)
                    .foregroundStyle(Brand.inkTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quoteRow(
        _ label: String, _ value: String, tint: Color? = nil, emphasised: Bool = false
    ) -> some View {
        HStack {
            Text(label)
                .font(Typography.subheadline)
                .foregroundStyle(Brand.inkSecondary)
            Spacer()
            Text(value)
                .font(emphasised ? Typography.currency : Typography.tabularMedium)
                .foregroundStyle(tint ?? ink)
        }
    }

    // MARK: Supporting

    private func issueBanner(_ issue: OrderValidator.Issue) -> some View {
        HStack(alignment: .top, spacing: Layout.Space.s) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Palette.caution)
            Text(issue.message)
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

    /// Signed out, or signed in with a wallet that isn't trading-ready yet.
    private var promptTitle: String {
        let session = environment.session
        if session.isSettingUp { return "Setting up your wallet" }
        return session.account == nil ? "Sign in to trade" : "Your wallet isn't ready yet"
    }

    private var promptMessage: String {
        let session = environment.session
        if session.isSettingUp { return "One-time setup in progress. This takes under a minute." }
        if session.account != nil {
            return session.lastError ?? "Finish setup in Profile, then come back to trade."
        }
        return "Browsing needs no account. Placing orders does — a wallet is created for you."
    }

    private var connectPrompt: some View {
        VStack(spacing: Layout.Space.xs) {
            Text(promptTitle)
                .font(Typography.headline)
                .foregroundStyle(ink)
            Text(promptMessage)
                .font(Typography.caption)
                .foregroundStyle(Brand.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Layout.Space.l)
        .fieldPanel(theme, radius: Layout.Radius.large)
    }

    private func actionBar(_ model: TradeViewModel) -> some View {
        VStack(spacing: Layout.Space.s) {
            Button {
                amountFocused = false
                model.requestConfirmation()
            } label: {
                if model.phase == .submitting {
                    ProgressView().tint(.white)
                } else {
                    Text(reviewTitle(model))
                }
            }
            .buttonStyle(primaryStyle(model))
            .disabled(!model.isReady || model.phase == .submitting)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, Layout.Space.m)
        .padding(.bottom, Layout.Space.l)
        .background(
            LinearGradient(colors: [Brand.card.opacity(0), Brand.card, Brand.card],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    private func primaryStyle(_ model: TradeViewModel) -> ChunkyButtonStyle {
        model.side == .buy
            ? .chunky(outcomeTint, ink: .white, shadow: outcomeShadow)
            : .chunkyInk
    }

    private func reviewTitle(_ model: TradeViewModel) -> String {
        let verb = model.side == .buy ? "Buy" : "Sell"
        guard let order = model.prepared else { return "Review \(verb.lowercased())" }
        return model.side == .buy
            ? "Review · \(Format.currency(order.totalCost))"
            : "Review · \(Format.shares(order.shares)) shares"
    }

    // MARK: Confirmation

    private func confirmation(_ model: TradeViewModel) -> some View {
        VStack(spacing: 0) {
            handle

            ScrollView {
                VStack(spacing: Layout.Space.l) {
                    VStack(spacing: Layout.Space.xs) {
                        Text("Confirm order")
                            .font(Typography.title)
                            .foregroundStyle(ink)
                        Text(environment.session.isWalletApp
                             ? "You'll approve it in your wallet app, then Pulse sends it to Polymarket."
                             : "This is signed on device and sent to Polymarket.")
                            .font(Typography.footnote)
                            .foregroundStyle(Brand.inkSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, Layout.Space.m)

                    identity

                    if let prepared = model.prepared {
                        OrderSummaryCard(order: prepared, theme: theme, expanded: true)
                    }

                    RiskNotice(ink: ink)
                }
                .padding(.horizontal, Layout.gutter)
                .padding(.bottom, Layout.Space.xl)
            }

            VStack(spacing: Layout.Space.s) {
                Button {
                    Task { await model.submit() }
                } label: {
                    if model.phase == .submitting {
                        ProgressView().tint(.white)
                    } else {
                        Text(environment.session.isWalletApp ? "Approve in wallet" : "Sign & submit")
                    }
                }
                .buttonStyle(primaryStyle(model))
                .disabled(model.phase == .submitting)

                Button("Back") { model.cancelConfirmation() }
                    .buttonStyle(.pill(.quiet, tint: ink, fullWidth: true))
                    .disabled(model.phase == .submitting)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.top, Layout.Space.m)
            .padding(.bottom, Layout.Space.l)
        }
    }
}

// MARK: - Order summary

/// Renders a prepared order.
///
/// Every figure is labelled as exact or estimated. On a market order only
/// the amount spent is certain — shares and price move with the book — and
/// a confirmation screen that implies otherwise is lying about money.
struct OrderSummaryCard: View {
    let order: TradingService.PreparedOrder
    var theme: Palette.Theme
    var expanded: Bool = false

    private var ink: Color { theme.onField }

    var body: some View {
        VStack(spacing: Layout.Space.s) {
            row("Outcome", order.outcomeLabel, emphasised: true)
            row(
                order.isMarketOrder ? "Est. average price" : "Limit price",
                Format.cents(order.price)
            )
            row(
                order.isMarketOrder ? "Est. shares" : "Shares",
                Format.shares(order.shares)
            )

            divider

            row(
                order.side == .buy ? "Amount" : "Proceeds",
                Format.currency(order.notional)
            )

            if order.fees.total > 0 {
                row("Est. fees", Format.currency(order.fees.total))
            }

            row(
                order.side == .buy ? "Total cost" : "You receive",
                Format.currency(order.side == .buy ? order.totalCost : order.netProceeds),
                emphasised: true
            )

            divider

            row("If \(order.outcomeLabel), you get", Format.currency(order.payoutIfWon), tint: Brand.yes)

            if order.side == .buy, order.notional > 0 {
                let profit = order.payoutIfWon - order.totalCost
                row(
                    "Profit if right",
                    Format.currency(profit, showSign: true),
                    tint: profit >= 0 ? Brand.yes : Brand.no
                )
                row("If wrong, you lose", Format.currency(order.totalCost), tint: Brand.no)
            }

            if expanded {
                divider
                row("Order type", orderTypeDescription)

                if let quote = order.quote {
                    if let slippage = quote.slippage, slippage > 0.001 {
                        row(
                            "Price impact",
                            Format.percentChange(slippage),
                            tint: slippage > 0.03 ? Palette.caution : nil
                        )
                    }
                    if quote.isPartial {
                        row("Fill", "Partial — book is thin", tint: Palette.caution)
                    }
                }

                Text(footnote)
                    .font(Typography.caption)
                    .foregroundStyle(Brand.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Layout.Space.xs)
            }
        }
        .padding(Layout.Space.l)
        .fieldPanel(theme, radius: Layout.Radius.large, strength: 0.07)
    }

    private var divider: some View {
        Rectangle().fill(Brand.hairline).frame(height: 2)
    }

    private var orderTypeDescription: String {
        switch order.orderType {
        case .fak: "Market · fill and kill"
        case .fok: "Market · fill or kill"
        case .gtc: "Limit · good 'til cancelled"
        case .gtd: "Limit · good 'til date"
        }
    }

    private var footnote: String {
        order.isMarketOrder
            ? """
              Shares and price are estimated from the order book right now and \
              can move before the order fills. Every winning share settles at \
              $1. Fees are estimated; the exchange charges the final amount at \
              fill time.
              """
            : """
              This order rests on the book until it fills or you cancel it. \
              Every winning share settles at $1.
              """
    }

    private func row(
        _ label: String, _ value: String, tint: Color? = nil, emphasised: Bool = false
    ) -> some View {
        HStack {
            Text(label)
                .font(Typography.subheadline)
                .foregroundStyle(Brand.inkSecondary)
            Spacer()
            Text(value)
                .font(emphasised ? Typography.currency : Typography.tabularMedium)
                .foregroundStyle(tint ?? ink)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Result

/// The screen after submitting.
///
/// Success states what the exchange accepted, never what it will become.
/// Failure shows the exchange's own reason verbatim and offers the way back
/// — a dead end here means someone has to guess whether their money moved.
struct OrderResultView: View {
    enum Outcome {
        case success(orderId: String?)
        case failure(message: String)
    }

    let outcome: Outcome
    let summary: TradingService.PreparedOrder?
    let outcomeLabel: String
    var theme: Palette.Theme
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var ink: Color { theme.onField }
    private var isSuccess: Bool {
        if case .success = outcome { return true }
        return false
    }

    var body: some View {
        VStack(spacing: Layout.Space.l) {
            Spacer()

            // Pip reacts to what happened — the order, not the market.
            Pip(
                pose: isSuccess ? .yay : .oops,
                size: 170,
                shadow: Brand.cardShadow
            )
            .scaleEffect(appeared || reduceMotion ? 1 : 0.7)
            .opacity(appeared || reduceMotion ? 1 : 0)
            .animation(reduceMotion ? nil : Motion.expressive, value: appeared)

            VStack(spacing: Layout.Space.xs) {
                Text(isSuccess ? "Order submitted" : "Order not placed")
                    .font(Typography.title)
                    .foregroundStyle(ink)

                Text(message)
                    .font(Typography.callout)
                    .foregroundStyle(Brand.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isSuccess, let summary {
                VStack(spacing: Layout.Space.xs) {
                    Text("\(Format.shares(summary.shares)) \(outcomeLabel)")
                        .font(Typography.probability)
                        .foregroundStyle(ink)
                    Text("for \(Format.currency(summary.totalCost))")
                        .font(Typography.subheadline)
                        .foregroundStyle(Brand.inkSecondary)
                    Text("Pays \(Format.currency(summary.payoutIfWon)) if \(outcomeLabel) wins")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.yes)
                        .padding(.top, 2)
                }
                .padding(Layout.Space.l)
                .frame(maxWidth: .infinity)
                .fieldPanel(theme, radius: Layout.Radius.large, strength: 0.07)
            }

            Spacer()

            Button(isSuccess ? "Done" : "Try again", action: onDismiss)
                .buttonStyle(.chunkyInk)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.bottom, Layout.Space.l)
        .onAppear { appeared = true }
    }

    private var message: String {
        switch outcome {
        case .success(let orderId):
            orderId?.isEmpty == false
                ? "Polymarket accepted the order. Track it under Activity."
                : "Polymarket accepted the order."
        case .failure(let message):
            message
        }
    }
}
