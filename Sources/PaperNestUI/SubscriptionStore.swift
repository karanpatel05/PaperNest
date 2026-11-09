import Foundation
import Observation
import PaperNestStore
import StoreKit

/// Public release inputs. Empty configuration is intentional: never invent a
/// product, a price, or a legal destination when App Store setup is incomplete.
struct SubscriptionConfiguration: Sendable {
    var productIDs: [String]
    var privacyURL: URL? = nil
    var termsURL: URL? = nil
    var supportURL: URL? = nil
    var canPurchase: Bool { !productIDs.isEmpty && privacyURL != nil && termsURL != nil }

    static var bundled: Self {
        let url = ResourceBundle.ui.url(forResource: "Subscriptions", withExtension: "plist")
        let values = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } as? [String: Any] ?? [:]
        func link(_ key: String) -> URL? {
            guard let text = values[key] as? String, let url = URL(string: text),
                  url.scheme == "https", let host = url.host, !host.isEmpty,
                  !host.contains("example.") else { return nil }
            return url
        }
        return Self(productIDs: (values["ProductIDs"] as? [String] ?? []).filter { !$0.isEmpty },
                    privacyURL: link("PrivacyURL"), termsURL: link("TermsURL"), supportURL: link("SupportURL"))
    }
}

struct ProSubscriptionState: Equatable, Sendable {
    enum Kind: String, Sendable { case free, trial, active, canceled, expired, billingIssue }
    var kind: Kind = .free
    var productID: String? = nil
    var accessUntil: Date? = nil
    var renewalDate: Date? = nil
    var trialEnd: Date? = nil

    func hasAccess(at date: Date = .now) -> Bool {
        guard kind != .free && kind != .expired, let accessUntil else { return false }
        return accessUntil > date
    }
    func displayKind(at date: Date = .now) -> Kind {
        if [.active, .trial, .canceled].contains(kind), !hasAccess(at: date) { return .expired }
        return kind
    }
    func remainingDays(at date: Date = .now) -> Int {
        max(0, Int(ceil(((trialEnd ?? accessUntil)?.timeIntervalSince(date) ?? 0) / 86_400)))
    }
}

@MainActor @Observable
final class SubscriptionStore {
    static let shared = SubscriptionStore()
    let configuration: SubscriptionConfiguration
    private(set) var products: [Product] = []
    private(set) var eligibleTrialIDs: Set<String> = []
    private(set) var state = ProSubscriptionState()
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    private(set) var isBusy = false
    private(set) var lastRefreshSucceeded = false
    @ObservationIgnored private var notebookMutationInProgress = false
    @ObservationIgnored private var notebookWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var refreshRequested = false
    @ObservationIgnored private var refreshWaiters: [CheckedContinuation<Void, Never>] = []
    var message: String?
    @ObservationIgnored private var updateTask: Task<Void, Never>?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(configuration: SubscriptionConfiguration = .bundled) { self.configuration = configuration }
    deinit { updateTask?.cancel(); statusTask?.cancel(); refreshTask?.cancel() }

    var hasProAccess: Bool { state.hasAccess() }
    /// The existing pre-commercial build remains usable before product setup.
    /// Once IDs are supplied, only verified StoreKit access permits Pro work.
    var allowsPremiumOperations: Bool { configuration.productIDs.isEmpty || hasProAccess }

    func requirePremiumOperation() throws {
        guard allowsPremiumOperations else { throw ProAccessError.required }
    }


    /// Serializes quota checks and writes across windows sharing this service.
    func withNotebookAllowance<T>(in library: LibraryStore, additional: Int,
                                  operation: () async throws -> T) async throws -> T {
        if notebookMutationInProgress {
            await withCheckedContinuation { notebookWaiters.append($0) }
        } else { notebookMutationInProgress = true }
        defer {
            if notebookWaiters.isEmpty { notebookMutationInProgress = false }
            else { notebookWaiters.removeFirst().resume() }
        }
        try Task.checkCancellation()
        if !allowsPremiumOperations && additional > 0 {
            let count = try await library.items(in: .all).filter { $0.item.kind == .notebook }.count
            guard count + additional <= 3 else { throw ProAccessError.required }
        }
        return try await operation()
    }

    func start() async {
        if updateTask == nil {
            updateTask = Task { [weak self] in
                for await result in Transaction.updates {
                    guard !Task.isCancelled else { return }
                    guard let self else { return }
                    if case .verified(let transaction) = result,
                       self.configuration.productIDs.contains(transaction.productID) {
                        await self.refresh()
                        await transaction.finish()
                    }
                }
            }
            statusTask = Task { [weak self] in
                for await _ in Product.SubscriptionInfo.Status.updates {
                    guard !Task.isCancelled else { return }
                    await self?.refresh()
                }
            }
            refreshTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    await self?.refresh()
                }
            }
        }
        await refresh()
    }

    /// Join an in-flight request and force a fresh pass before releasing callers.
    /// A purchase that arrives while products are loading cannot be discarded.
    func refresh() async {
        if isLoading {
            refreshRequested = true
            await withCheckedContinuation { refreshWaiters.append($0) }
            return
        }
        isLoading = true
        repeat {
            refreshRequested = false
            await refreshSnapshot()
        } while refreshRequested
        isLoading = false
        hasLoaded = true
        let waiters = refreshWaiters
        refreshWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    private func refreshSnapshot() async {
        lastRefreshSucceeded = false
        let ids = configuration.productIDs
        guard !ids.isEmpty else { state = .init(); lastRefreshSucceeded = true; return }
        var candidates: [ProSubscriptionState] = []
        // Verified current entitlements work even if fetching storefront products fails.
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, ids.contains(t.productID), !t.isUpgraded,
               t.revocationDate == nil, let end = t.expirationDate {
                if end > .now {
                    candidates.append(.init(kind: isTrial(t) ? .trial : .active,
                                            productID: t.productID, accessUntil: end, trialEnd: isTrial(t) ? end : nil))
                } else if state.kind == .billingIssue, state.productID == t.productID, state.hasAccess() {
                    // StoreKit still reports this verified current entitlement.
                    // Retain its previously verified grace deadline if storefront
                    // loading fails; a successful status query below supersedes it.
                    candidates.append(state)
                }
            }
        }
        do {
            products = try await Product.products(for: ids).filter { product in
                guard product.type == .autoRenewable, let period = product.subscription?.subscriptionPeriod else { return false }
                return period.value == 1 && (period.unit == .month || period.unit == .year)
            }.sorted { $0.subscription!.subscriptionPeriod.unit == .month && $1.subscription!.subscriptionPeriod.unit == .year }
            var eligibility = Set<String>()
            var checkedGroups = Set<String>()
            for product in products {
                guard let subscription = product.subscription else { continue }
                if Self.hasSevenDayTrial(product), await subscription.isEligibleForIntroOffer {
                    eligibility.insert(product.id)
                }
                guard checkedGroups.insert(subscription.subscriptionGroupID).inserted else { continue }
                let statuses = try await subscription.status
                for status in statuses {
                    guard case .verified(let t) = status.transaction,
                          case .verified(let renewal) = status.renewalInfo,
                          ids.contains(t.productID), !t.isUpgraded else { continue }
                    candidates.removeAll { $0.productID == t.productID }
                    let kind: ProSubscriptionState.Kind
                    var accessUntil: Date?
                    switch status.state {
                    case .subscribed where t.revocationDate == nil:
                        kind = !renewal.willAutoRenew ? .canceled : (isTrial(t) ? .trial : .active)
                        accessUntil = t.expirationDate
                    case .inGracePeriod where t.revocationDate == nil:
                        kind = .billingIssue; accessUntil = renewal.gracePeriodExpirationDate
                    case .inBillingRetryPeriod: kind = .billingIssue
                    default: kind = .expired
                    }
                    candidates.append(.init(kind: kind, productID: t.productID, accessUntil: accessUntil,
                                            renewalDate: renewal.willAutoRenew ? renewal.renewalDate : nil,
                                            trialEnd: isTrial(t) ? t.expirationDate : nil))
                }
            }
            eligibleTrialIDs = eligibility
            lastRefreshSucceeded = products.count == Set(ids).count
            if message == L10n.proLoadError { message = nil }
        } catch {
            eligibleTrialIDs = []
            message = L10n.proLoadError
        }
        // Historical transactions distinguish a lapsed subscriber from a new user.
        if candidates.isEmpty {
            for id in ids {
                if case .verified(let t) = await Transaction.latest(for: id), !t.isUpgraded {
                    candidates.append(.init(kind: .expired, productID: id, accessUntil: t.expirationDate))
                }
            }
        }
        state = candidates.sorted { a, b in
            if a.hasAccess() != b.hasAccess() { return a.hasAccess() }
            return (a.accessUntil ?? .distantPast) > (b.accessUntil ?? .distantPast)
        }.first ?? .init()
    }

    static func hasSevenDayTrial(_ product: Product) -> Bool {
        guard let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial,
              offer.periodCount == 1 else { return false }
        return (offer.period.unit == .day && offer.period.value == 7)
            || (offer.period.unit == .week && offer.period.value == 1)
    }

    private func isTrial(_ transaction: Transaction) -> Bool {
        if #available(iOS 17.2, macOS 14.2, *) {
            return transaction.offer?.type == .introductory && transaction.offer?.paymentMode == .freeTrial
        } else {
            return transaction.offerType == .introductory && transaction.offerPaymentModeStringRepresentation == "FREE_TRIAL"
        }
    }

    func purchase(_ product: Product) async {
        guard !isBusy, configuration.canPurchase, configuration.productIDs.contains(product.id) else { return }
        isBusy = true; message = nil
        defer { isBusy = false }
        do {
            await handlePurchaseResult(try await product.purchase())
        } catch StoreKitError.userCancelled {
            // Dismissing Apple’s purchase flow is not an error.
        } catch { message = L10n.proPurchaseError }
    }

    func handlePurchaseResult(_ result: Product.PurchaseResult) async {
        switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { message = L10n.proVerificationError; return }
                await refresh()
                await transaction.finish()
            case .pending: message = L10n.proPending
            case .userCancelled: break
            @unknown default: message = L10n.proPurchaseError
            }
    }

    func restore() async {
        guard !isBusy else { return }
        guard !configuration.productIDs.isEmpty else { message = L10n.proUnavailable; return }
        isBusy = true; message = nil
        defer { isBusy = false }
        do {
            try await AppStore.sync()
            await refresh()
            message = hasProAccess ? L10n.proRestored : (lastRefreshSucceeded ? L10n.proNothingToRestore : L10n.proLoadError)
        } catch StoreKitError.userCancelled {
        } catch { message = L10n.proRestoreError }
    }
}

enum ProAccessError: LocalizedError {
    case required
    var errorDescription: String? { L10n.proRequired }
}
