#if canImport(StoreKitTest)
import Foundation
import XCTest
import StoreKit
import StoreKitTest
import Testing
@testable import PaperNestUI

/// Apple’s local StoreKit environment, never a production entitlement override.
private final class SubscriptionTestBundle: NSObject {}

@Suite(.serialized) @MainActor struct SubscriptionStoreKitTests {
    @Test func trialCancellationExpiryAndRefundUseVerifiedStoreKitState() async throws {
        let fixture = try #require(Bundle(for: SubscriptionTestBundle.self).url(forResource: "PaperNest", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: fixture)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        defer { session.clearTransactions() }
        let ids = ["test.papernest.pro.monthly", "test.papernest.pro.yearly"]
        let store = SubscriptionStore(configuration: .init(productIDs: ids,
            privacyURL: URL(string: "https://legal.invalid/privacy"), termsURL: URL(string: "https://legal.invalid/terms")))
        await store.start()
        #expect(store.products.count == 2)
        #expect(store.state.kind == .free)
        #expect(store.eligibleTrialIDs == Set(ids))
        let monthly = try #require(store.products.first { $0.id == ids[0] })
        await store.purchase(monthly)
        #expect(store.hasProAccess)
        #expect(store.state.kind == .trial)
        #expect(store.state.remainingDays() == 7)
        await store.refresh()
        #expect(store.eligibleTrialIDs.isEmpty)
        let transaction = try #require(session.allTransactions().filter { $0.productIdentifier == ids[0] }.max { $0.purchaseDate < $1.purchaseDate })
        try session.disableAutoRenewForTransaction(identifier: transaction.identifier)
        #expect(session.allTransactions().first { $0.identifier == transaction.identifier }?.autoRenewingEnabled == false)
        await settle(store) { $0.state.kind == .canceled }
        if store.state.kind != .canceled {
            for status in try await monthly.subscription!.status {
                if case .verified(let renewal) = status.renewalInfo {
                    print("TEST queried renewal: autoRenew=\(renewal.willAutoRenew), signed=\(renewal.signedDate), state=\(status.state.rawValue)")
                }
            }
            print("TEST refresh success=\(store.lastRefreshSucceeded), message=\(store.message ?? "none")")
        }
        #expect(store.state.kind == .canceled)
        #expect(store.hasProAccess)
        try session.expireSubscription(productIdentifier: ids[0])
        await settle(store) { !$0.hasProAccess && $0.state.kind == .expired }
        if store.hasProAccess {
            for status in try await monthly.subscription!.status {
                if case .verified(let t) = status.transaction {
                    print("TEST expiry status=\(status.state.rawValue), expiration=\(String(describing: t.expirationDate)), id=\(t.id)")
                }
            }
        }
        #expect(!store.hasProAccess)
        #expect(store.state.kind == .expired)
        _ = try await session.buyProduct(identifier: ids[1])
        await settle(store) { $0.hasProAccess && $0.state.productID == ids[1] }
        #expect(store.hasProAccess)
        let latest = try #require(session.allTransactions().last)
        try session.refundTransaction(identifier: latest.identifier)
        await settle(store) { !$0.hasProAccess }
        #expect(!store.hasProAccess)
    }
    private func settle(_ store: SubscriptionStore, until ready: (SubscriptionStore) -> Bool) async {
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            await store.refresh()
            if ready(store) { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    @Test func failedPendingAndRestoredPurchases() async throws {
        let fixture = try #require(Bundle(for: SubscriptionTestBundle.self).url(forResource: "PaperNest", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: fixture)
        session.resetToDefaultState(); session.clearTransactions(); session.disableDialogs = true
        defer { session.clearTransactions() }
        let id = "test.papernest.pro.monthly"
        let store = SubscriptionStore(configuration: .init(productIDs: [id],
            privacyURL: URL(string: "https://legal.invalid/privacy"), termsURL: URL(string: "https://legal.invalid/terms")))
        await store.start()
        let product = try #require(store.products.first)
        // The runtime maps injected userCancelled to unknown ASD error 907.
        // Normal PurchaseResult.userCancelled is covered by SubscriptionStateTests.
        try await session.setSimulatedError(.generic(.unknown), forAPI: .purchase)
        await store.purchase(product)
        #expect(store.message == L10n.proPurchaseError)
        #expect(!store.hasProAccess)
        try await session.setSimulatedError(nil, forAPI: .purchase)
        session.askToBuyEnabled = true
        await store.purchase(product)
        #expect(store.message == L10n.proPending)
        #expect(!store.hasProAccess)
        let transaction = try #require(session.allTransactions().first)
        try session.approveAskToBuyTransaction(identifier: transaction.identifier)
        // Pro is granted by Transaction/Status.updates, without another purchase.
        let deadline = Date().addingTimeInterval(45)
        while !store.hasProAccess && Date() < deadline { try await Task.sleep(for: .milliseconds(250)) }
        #expect(store.hasProAccess)
        await store.restore()
        #expect(store.hasProAccess)
        #expect(store.message == L10n.proRestored)
    }

    @Test(arguments: [false, true])
    func billingRetryOnlyGrantsAccessDuringGrace(_ grace: Bool) async throws {
        let fixture = try #require(Bundle(for: SubscriptionTestBundle.self).url(forResource: "PaperNest", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: fixture)
        session.resetToDefaultState(); session.clearTransactions(); session.disableDialogs = true
        session.shouldEnterBillingRetryOnRenewal = true
        session.billingGracePeriodIsEnabled = grace
        session.timeRate = .realTime
        defer { session.resetToDefaultState(); session.clearTransactions() }
        let id = "test.papernest.pro.monthly"
        let store = SubscriptionStore(configuration: .init(productIDs: [id]))
        _ = try await session.buyProduct(identifier: id)
        await store.start()
        try session.forceRenewalOfSubscription(productIdentifier: id)
        await settle(store) { $0.state.kind == .billingIssue }
        #expect(store.state.kind == .billingIssue)
        #expect(store.hasProAccess == grace)
    }

}
#endif
