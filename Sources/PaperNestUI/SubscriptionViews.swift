import StoreKit
import SwiftUI

struct ProPaywallView: View {
    @Bindable var store: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedID: String?

    private var selected: Product? { store.products.first { $0.id == selectedID } ?? store.products.first { store.eligibleTrialIDs.contains($0.id) } ?? store.products.first }
    private var trial: Bool { selected.map { store.eligibleTrialIDs.contains($0.id) } ?? false }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if !typeSize.isAccessibilitySize { ProPaperIllustration().accessibilityHidden(true) }
                    VStack(spacing: 8) {
                        Text(L10n.proHeadline).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        Text(L10n.proSubtitle).foregroundStyle(.secondary)
                    }.multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: 16) {
                        benefit(L10n.proNotebooks, "books.vertical")
                        benefit(L10n.proOCR, "text.viewfinder")
                        benefit(L10n.proExport, "doc.text")
                        benefit(L10n.proPDF, "doc.on.doc")
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(20).modifier(PremiumCard())
                    if store.isLoading && store.products.isEmpty {
                        ProgressView(L10n.proLoading)
                    } else if store.products.isEmpty {
                        Text(L10n.proUnavailable).foregroundStyle(.secondary)
                        Button(L10n.proRetry) { Task { await store.refresh() } }
                    } else {
                        let planLayout = typeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(spacing: 12))
                            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                        planLayout {
                            ForEach(store.products, id: \.id) { product in plan(product) }
                        }
                    }
                    VStack(spacing: 12) {
                        if let product = selected {
                            Text(trial ? L10n.proTrialBilling(product.billingLabel) : product.billingLabel)
                                .font(.headline).multilineTextAlignment(.center)
                            Text(L10n.proRenewalTerms).font(.footnote).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            Button {
                                Task { await store.purchase(product); if store.hasProAccess { dismiss() } }
                            } label: {
                                Text(trial ? L10n.proTrialCTA : L10n.proSubscribe)
                                    .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                            }.buttonStyle(.borderedProminent)
                                .disabled(store.isBusy || store.isLoading || !store.configuration.canPurchase || store.hasProAccess)
                                .accessibilityIdentifier("pro-purchase")
                        }
                        if !store.configuration.canPurchase {
                            Text(L10n.proLegalUnavailable).font(.footnote).foregroundStyle(.secondary)
                        }
                        if store.isBusy { ProgressView(L10n.proLoading) }
                        if let message = store.message { Text(message).font(.callout).accessibilityIdentifier("pro-message") }
                        Button(L10n.proContinueFree) { dismiss() }.frame(minHeight: 44)
                            .accessibilityIdentifier("pro-continue-free")
                        Text(L10n.proFreeDetail).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    SubscriptionLinks(store: store)
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .background(Theme.libraryBackground)
            .navigationTitle(L10n.proTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.proClose, systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("pro-close")
                }
            }
        }
        .tint(Theme.accent)
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 560, minHeight: 560, idealHeight: 740)
        #endif
        .task { await store.start() }
        .onChange(of: store.hasProAccess) { _, access in if access { dismiss() } }
        .accessibilityIdentifier("pro-paywall")
    }

    @ViewBuilder private func benefit(_ text: String, _ symbol: String) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).font(.title3).foregroundStyle(Theme.accent).accessibilityHidden(true)
                Text(text).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: {
                Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 28)
            }
        }
    }
    private func plan(_ product: Product) -> some View {
        let isSelected = selected?.id == product.id
        return Button { selectedID = product.id } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 6) {
                    Text(product.isAnnual ? L10n.proYearly : L10n.proMonthly).font(.headline)
                    Text(product.billingLabel).font(.subheadline).foregroundStyle(.secondary)
                }.fixedSize(horizontal: false, vertical: true)
            }.padding(18).frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
                .background(isSelected ? Theme.selection : Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(isSelected ? Theme.accent : Theme.separator, lineWidth: isSelected ? 2 : 1))
        }.buttonStyle(.plain).accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier(product.isAnnual ? "pro-plan-yearly" : "pro-plan-monthly")
    }
}

struct ProfileView: View {
    let session: LibrarySession
    @Bindable var store: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPaywall = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "person")
                        .font(.system(size: 34, weight: .light)).foregroundStyle(Theme.accent)
                        .frame(width: 84, height: 84).background(Theme.selection, in: Circle())
                        .frame(maxWidth: .infinity).accessibilityHidden(true)
                    TimelineView(.periodic(from: .now, by: 60)) { context in subscriptionCard(at: context.date) }
                    Button { showSettings = true } label: {
                        Label(L10n.settingsTitle, systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading).padding(18)
                    }.buttonStyle(.plain).modifier(PremiumCard()).accessibilityIdentifier("profile-settings")
                    SubscriptionLinks(store: store, showsManagement: [.free, .expired].contains(store.state.displayKind(at: .now)))
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.background(Theme.libraryBackground)
                .navigationTitle(L10n.profile)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.done) { dismiss() }.accessibilityIdentifier("profile-done")
                    }
                }
        }
        .tint(Theme.accent)
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 560, minHeight: 520, idealHeight: 700)
        #endif
        .sheet(isPresented: $showPaywall) { ProPaywallView(store: store) }
        .sheet(isPresented: $showSettings) { SettingsView(session: session) }
        .task { await store.start() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.refresh() } } }
    }

    private func subscriptionCard(at now: Date) -> some View {
        let state = store.state
        let kind = state.displayKind(at: now)
        return VStack(alignment: .leading, spacing: 16) {
            Label { Text(L10n.proTitle) } icon: { BrandMark.image(size: 24) }
                .font(.title2.bold()).foregroundStyle(Theme.accent)
            if !store.hasLoaded { ProgressView(L10n.proLoading) }
            else if !store.lastRefreshSucceeded && state.productID == nil {
                Text(L10n.proLoadError)
                Button(L10n.proRetry) { Task { await store.refresh() } }
            } else {
                Text(kind.title).font(.title3.bold()).accessibilityIdentifier("profile-subscription-state")
                    .accessibilityValue(kind.rawValue)
                if let product = store.products.first(where: { $0.id == state.productID }) {
                    Text(product.isAnnual ? L10n.proYearly : L10n.proMonthly).foregroundStyle(.secondary)
                }
                if state.hasAccess(at: now), [.trial, .canceled].contains(kind),
                   let date = state.trialEnd ?? (kind == .trial ? state.accessUntil : nil), date > now {
                    Text(L10n.proTrialEnds(date.formatted(date: .abbreviated, time: .omitted), state.remainingDays(at: now).formatted()))
                }
                if (kind == .canceled || kind == .billingIssue), let date = state.accessUntil, date > now {
                    Text(L10n.proAccessEnds(date.formatted(date: .abbreviated, time: .omitted)))
                } else if kind == .active, let date = state.renewalDate {
                    Text(L10n.proRenews(date.formatted(date: .abbreviated, time: .omitted)))
                }
                if kind == .free || kind == .expired {
                    Button(L10n.proUpgrade) { showPaywall = true }.buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("profile-upgrade")
                } else { ManageSubscriptionButton() }
            }
            Text(L10n.proContentSafe).font(.footnote).foregroundStyle(.secondary)
            if let message = store.message { Text(message).font(.callout) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(24).modifier(PremiumCard())
    }
}

private struct SubscriptionLinks: View {
    @Bindable var store: SubscriptionStore
    var showsManagement = true
    var body: some View {
        VStack(spacing: 12) {
            Button(L10n.proRestore) { Task { await store.restore() } }
                .disabled(store.isBusy).frame(minHeight: 44).accessibilityIdentifier("pro-restore")
            if showsManagement { ManageSubscriptionButton() }
            if let url = store.configuration.termsURL { Link(L10n.proTerms, destination: url).frame(minHeight: 44) }
            if let url = store.configuration.privacyURL { Link(L10n.proPrivacy, destination: url).frame(minHeight: 44) }
            if let url = store.configuration.supportURL { Link(L10n.proSupport, destination: url).frame(minHeight: 44) }
        }.font(.callout).frame(maxWidth: .infinity)
    }
}

private struct ManageSubscriptionButton: View {
    // Apple’s account subscription management route works on iOS and macOS.
    var body: some View {
        Link(L10n.proManage, destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
            .frame(minHeight: 44).accessibilityIdentifier("pro-manage")
    }
}

private struct ProPaperIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(Theme.selection).frame(width: 120, height: 145).rotationEffect(.degrees(-12)).offset(x: -22, y: 5)
            VStack(alignment: .leading, spacing: 13) {
                BrandMark.image(size: 28).foregroundStyle(Theme.accent)
                ForEach(0..<3) { index in Capsule().fill(Theme.separator).frame(width: index == 2 ? 46 : 80, height: 4) }
            }.padding(24).frame(width: 130, height: 150).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                .rotationEffect(.degrees(5)).shadow(color: Theme.paperShadow, radius: 10, y: 6)
        }.frame(height: 175)
    }
}

private extension Product {
    var isAnnual: Bool { subscription?.subscriptionPeriod.unit == .year }
    var billingLabel: String { isAnnual ? L10n.proYearPrice(displayPrice) : L10n.proMonthPrice(displayPrice) }
}
private extension ProSubscriptionState.Kind {
    var title: String {
        switch self {
        case .free: L10n.proFree
        case .trial: L10n.proTrial
        case .active: L10n.proActive
        case .canceled: L10n.proCanceled
        case .expired: L10n.proExpired
        case .billingIssue: L10n.proBillingIssue
        }
    }
}
