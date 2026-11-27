import SwiftUI
import PulseCore

/// The order entry sheet.
///
/// Designed so that what a person confirms is exactly what gets signed: the
/// summary rows are rendered from the same `PreparedOrder` that submission
/// sends. Nothing is estimated twice, and nothing is recomputed between
/// confirmation and signing.
struct TradeSheet: View {
    let request: TradeRequest

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var model: TradeViewModel?
    @FocusState private var amountFocused: Bool

    private var tint: Color { request.isYes ? Palette.yes : Palette.no }
    private var surface: Color { request.isYes ? Palette.yesSurface : Palette.noSurface }

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(ScreenBackground())
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
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

    private var navigationTitle: String {
        guard let model else { return "Trade" }
        return "\(model.side == .buy ? "Buy" : "Sell") \(request.outcomeLabel)"
    }

    @ViewBuilder
    private func content(_ model: TradeViewModel) -> some View {
        switch model.phase {
        case .succeeded(let orderId):
            OrderResultView(
                outcome: .success(orderId: orderId),
                summary: model.prepared,
                outcomeLabel: request.outcomeLabel
            ) { dismiss() }
                .onAppear { Haptics.success(enabled: environment.settings.hapticsEnabled) }

        case .failed(let message):
            OrderResultView(
                outcome: .failure(message: message),
                summary: model.prepared,
                outcomeLabel: request.outcomeLabel
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
            ScrollView {
                VStack(spacing: Layout.Space.l) {
                    marketHeader

                    Picker("Side", selection: $model.side) {
                        Text("Buy").tag(OrderSide.buy)
                        Text("Sell").tag(OrderSide.sell)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: model.side) { _, _ in model.recalculate() }

                    Picker("Order type", selection: $model.mode) {
                        ForEach(TradeViewModel.Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: model.mode) { _, _ in model.recalculate() }

                    if model.mode == .market {
                        marketOrderFields(model)
                    } else {
                        limitOrderFields(model)
                    }

                    if let prepared = model.prepared {
                        OrderSummaryCard(order: prepared, tint: tint)
                    }

                    if let issue = model.blockingIssue, !model.amountText.isEmpty {
                        issueBanner(issue)
                    }

                    if !model.canTrade {
                        connectPrompt
                    }

                    RiskNotice(compact: true)
                }
                .padding(Layout.gutter)
                .padding(.bottom, Layout.Space.xl)
            }
            .scrollDismissesKeyboard(.interactively)

            actionBar(model)
        }
    }

    private var marketHeader: some View {
        HStack(spacing: Layout.Space.m) {
            MarketImage(
                url: request.event.imageURL,
                theme: Palette.theme(for: request.event.id),
                fallbackText: request.event.displayTitle,
                size: 44
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(request.event.displayTitle)
                    .font(Typography.subheadlineMedium)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                if request.event.isMultiOutcome {
                    Text(request.market.displayTitle)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Spacer()
            Text(request.outcomeLabel)
                .font(Typography.captionMedium)
                .foregroundStyle(tint)
                .padding(.horizontal, Layout.Space.s)
                .padding(.vertical, 4)
                .background(Capsule().fill(surface))
        }
        .padding(Layout.Space.m)
        .cardSurface()
    }

    private func marketOrderFields(_ model: TradeViewModel) -> some View {
        @Bindable var model = model
        let isBuy = model.side == .buy

        return VStack(alignment: .leading, spacing: Layout.Space.m) {
            HStack {
                Text(isBuy ? "Amount to spend" : "Shares to sell")
                    .font(Typography.subheadlineMedium)
                    .foregroundStyle(Palette.ink)
                Spacer()
                if isBuy {
                    Text(
                        model.availableBalance.map { "\(Format.currency($0)) available" }
                            ?? "Balance unavailable"
                    )
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkSecondary)
                } else if let held = model.heldShares {
                    Text("\(Format.shares(held)) held")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }

            HStack(spacing: Layout.Space.xs) {
                if isBuy {
                    Text("$").font(Typography.currencyLarge).foregroundStyle(Palette.inkTertiary)
                }
                TextField("0", text: $model.amountText)
                    .font(Typography.currencyLarge)
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .onChange(of: model.amountText) { _, _ in model.recalculate() }
                if !isBuy {
                    Text("shares").font(Typography.headline).foregroundStyle(Palette.inkTertiary)
                }
            }
            .padding(Layout.Space.m)
            .background(
                RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
                    .fill(Palette.surfaceRaised)
            )

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
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(Capsule().fill(Palette.surfaceRaised))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Layout.Space.l)
        .cardSurface(radius: Layout.Radius.large)
    }

    private func limitOrderFields(_ model: TradeViewModel) -> some View {
        @Bindable var model = model

        return VStack(alignment: .leading, spacing: Layout.Space.m) {
            VStack(alignment: .leading, spacing: Layout.Space.xs) {
                Text("Limit price")
                    .font(Typography.subheadlineMedium)
                    .foregroundStyle(Palette.ink)
                HStack {
                    TextField("0", text: $model.limitPriceText)
                        .font(Typography.currency)
                        .keyboardType(.numberPad)
                        .onChange(of: model.limitPriceText) { _, _ in model.recalculate() }
                    Text("¢").foregroundStyle(Palette.inkTertiary)
                }
                .padding(Layout.Space.m)
                .background(
                    RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
                        .fill(Palette.surfaceRaised)
                )
                Text("Tick size \(Format.cents(request.market.tickSize))")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
            }

            VStack(alignment: .leading, spacing: Layout.Space.xs) {
                Text("Shares")
                    .font(Typography.subheadlineMedium)
                    .foregroundStyle(Palette.ink)
                TextField("0", text: $model.limitSharesText)
                    .font(Typography.currency)
                    .keyboardType(.decimalPad)
                    .onChange(of: model.limitSharesText) { _, _ in model.recalculate() }
                    .padding(Layout.Space.m)
                    .background(
                        RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
                            .fill(Palette.surfaceRaised)
                    )
                Text("Minimum \(Format.shares(request.market.minimumOrderSize)) shares")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
        .padding(Layout.Space.l)
        .cardSurface(radius: Layout.Radius.large)
    }

    private func issueBanner(_ issue: OrderValidator.Issue) -> some View {
        HStack(alignment: .top, spacing: Layout.Space.s) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Palette.caution)
            Text(issue.message)
                .font(Typography.footnote)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Layout.Space.m)
        .background(
            RoundedRectangle(cornerRadius: Layout.Radius.medium, style: .continuous)
                .fill(Palette.caution.opacity(0.12))
        )
    }

    private var connectPrompt: some View {
        VStack(spacing: Layout.Space.s) {
            Text("Connect a wallet to trade")
                .font(Typography.headline)
                .foregroundStyle(Palette.ink)
            Text("Browsing works without one. Placing orders needs a Polymarket-funded wallet.")
                .font(Typography.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Layout.Space.l)
        .cardSurface(radius: Layout.Radius.large)
    }

    private func actionBar(_ model: TradeViewModel) -> some View {
        VStack(spacing: Layout.Space.s) {
            Button {
                amountFocused = false
                model.requestConfirmation()
            } label: {
                if model.phase == .submitting {
                    ProgressView().tint(Palette.canvas)
                } else {
                    Text(model.side == .buy ? "Review buy" : "Review sell")
                }
            }
            .buttonStyle(.pill(.primary, tint: tint, onTint: .white, fullWidth: true))
            .disabled(!model.isReady || model.phase == .submitting)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.vertical, Layout.Space.m)
        .background(.bar)
    }

    // MARK: Confirmation

    private func confirmation(_ model: TradeViewModel) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Layout.Space.l) {
                    VStack(spacing: Layout.Space.xs) {
                        Text("Confirm order")
                            .font(Typography.title2)
                            .foregroundStyle(Palette.ink)
                        Text("Review before signing. This is submitted to Polymarket.")
                            .font(Typography.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, Layout.Space.l)

                    marketHeader

                    if let prepared = model.prepared {
                        OrderSummaryCard(order: prepared, tint: tint, expanded: true)
                    }

                    RiskNotice()
                }
                .padding(Layout.gutter)
            }

            VStack(spacing: Layout.Space.s) {
                Button {
                    Task { await model.submit() }
                } label: {
                    if model.phase == .submitting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Sign & submit")
                    }
                }
                .buttonStyle(.pill(.primary, tint: tint, onTint: .white, fullWidth: true))
                .disabled(model.phase == .submitting)

                Button("Back") { model.cancelConfirmation() }
                    .buttonStyle(.pill(.quiet, tint: Palette.inkSecondary, fullWidth: true))
                    .disabled(model.phase == .submitting)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.vertical, Layout.Space.m)
            .background(.bar)
        }
    }
}

// MARK: - Order summary

/// Renders a prepared order. Every figure is labelled as either exact or
/// estimated, because on a market order only the spend is certain.
struct OrderSummaryCard: View {
    let order: TradingService.PreparedOrder
    var tint: Color = Palette.ink
    var expanded: Bool = false

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

            Divider().background(Palette.separator)

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

            Divider().background(Palette.separator)

            row("Payout if correct", Format.currency(order.payoutIfWon), tint: Palette.up)

            if order.side == .buy, order.notional > 0 {
                let profit = order.payoutIfWon - order.totalCost
                row(
                    "Profit if correct",
                    Format.currency(profit, showSign: true),
                    tint: profit >= 0 ? Palette.up : Palette.down
                )
            }

            if expanded {
                Divider().background(Palette.separator)
                row("Order type", orderTypeDescription)

                if let quote = order.quote {
                    if let slippage = quote.slippage, slippage > 0.001 {
                        row("Price impact", Format.percentChange(slippage), tint: Palette.caution)
                    }
                    if quote.isPartial {
                        row("Fill", "Partial — book is thin", tint: Palette.caution)
                    }
                }

                Text(footnote)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Layout.Space.xs)
            }
        }
        .padding(Layout.Space.l)
        .cardSurface(radius: Layout.Radius.large)
    }

    private var orderTypeDescription: String {
        switch order.orderType {
        case .fak: "Market (fill and kill)"
        case .fok: "Market (fill or kill)"
        case .gtc: "Limit (good 'til cancelled)"
        case .gtd: "Limit (good 'til date)"
        }
    }

    private var footnote: String {
        order.isMarketOrder
            ? """
              Shares and price are estimated from the order book right now and \
              can change before the order fills. Every winning share settles at \
              $1. Fees are estimated; the exchange charges the final amount at \
              fill time.
              """
            : """
              This order rests on the book until it fills or you cancel it. \
              Every winning share settles at $1.
              """
    }

    private func row(
        _ label: String,
        _ value: String,
        tint: Color = Palette.ink,
        emphasised: Bool = false
    ) -> some View {
        HStack {
            Text(label)
                .font(Typography.subheadline)
                .foregroundStyle(Palette.inkSecondary)
            Spacer()
            Text(value)
                .font(emphasised ? Typography.currency : Typography.subheadlineMedium.monospacedDigit())
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Result

struct OrderResultView: View {
    enum Outcome {
        case success(orderId: String?)
        case failure(message: String)
    }

    let outcome: Outcome
    let summary: TradingService.PreparedOrder?
    let outcomeLabel: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: Layout.Space.l) {
            Spacer()

            Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(isSuccess ? Palette.up : Palette.danger)

            VStack(spacing: Layout.Space.xs) {
                Text(isSuccess ? "Order submitted" : "Order not placed")
                    .font(Typography.title2)
                    .foregroundStyle(Palette.ink)

                Text(message)
                    .font(Typography.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isSuccess, let summary {
                VStack(spacing: Layout.Space.xs) {
                    Text("\(Format.shares(summary.shares)) \(outcomeLabel) shares")
                        .font(Typography.headline)
                        .foregroundStyle(Palette.ink)
                    Text("for \(Format.currency(summary.totalCost))")
                        .font(Typography.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(Layout.Space.l)
                .cardSurface(radius: Layout.Radius.large)
            }

            Spacer()

            Button(isSuccess ? "Done" : "Try again", action: onDismiss)
                .buttonStyle(.pill(.primary, fullWidth: true))
        }
        .padding(Layout.gutter)
    }

    private var isSuccess: Bool {
        if case .success = outcome { return true }
        return false
    }

    private var message: String {
        switch outcome {
        case .success(let orderId):
            if let orderId, !orderId.isEmpty {
                return "Polymarket accepted the order. Track it under Activity."
            }
            return "Polymarket accepted the order."
        case .failure(let message):
            return message
        }
    }
}
