import Foundation
import Testing
import StoreKit
import PaperNestStore
import PaperNestCore
@testable import PaperNestUI

@Suite struct SubscriptionStateTests {
    @Test func accessExpiresWithoutDeletingAnything() {
        let end = Date(timeIntervalSince1970: 100)
        let state = ProSubscriptionState(kind: .canceled, productID: "monthly", accessUntil: end, renewalDate: nil)
        #expect(state.hasAccess(at: end.addingTimeInterval(-1)))
        #expect(!state.hasAccess(at: end))
        #expect(state.displayKind(at: end) == .expired)
    }
    @Test func billingRetryHasNoAccessWithoutGraceDate() {
        let state = ProSubscriptionState(kind: .billingIssue, productID: "monthly", accessUntil: nil, renewalDate: nil)
        #expect(!state.hasAccess(at: .now))
        let grace = ProSubscriptionState(kind: .billingIssue, productID: "monthly", accessUntil: .distantFuture, renewalDate: nil)
        #expect(grace.hasAccess(at: .now))
    }
    @Test func trialDaysRoundUpAndNeverGoNegative() {
        let state = ProSubscriptionState(kind: .trial, productID: "monthly", accessUntil: Date(timeIntervalSince1970: 100), renewalDate: nil)
        #expect(state.remainingDays(at: Date(timeIntervalSince1970: 99)) == 1)
        #expect(state.remainingDays(at: Date(timeIntervalSince1970: 101)) == 0)
    }
    @Test func missingLegalConfigurationBlocksCheckout() {
        let configuration = SubscriptionConfiguration(productIDs: ["monthly", "annual"])
        #expect(!configuration.canPurchase)
    }
    @Test @MainActor func concurrentNotebookCreationRespectsFreeQuota() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let library = try LibraryStore(directory: url)
        for index in 0..<2 {
            _ = try await library.createItem(kind: .notebook, name: "Existing \(index)", pages: [], assets: [])
        }
        let service = SubscriptionStore(configuration: .init(productIDs: ["configured-monthly"]))
        let create: @MainActor () async -> Bool = {
            do {
                _ = try await service.withNotebookAllowance(in: library, additional: 1) {
                    try await library.createItem(kind: .notebook, name: "New", pages: [], assets: [])
                }
                return true
            } catch { return false }
        }
        async let first = create()
        async let second = create()
        let results = await [first, second]
        #expect(results.filter { $0 }.count == 1)
        #expect(try await library.items(in: .all).count == 3)
        #expect(!service.hasProAccess)
        await #expect(throws: ProAccessError.self) {
            try await service.withNotebookAllowance(in: library, additional: 2) { () }
        }
    }

    @Test @MainActor func cancellationAndPendingNeverGrantAccess() async {
        let service = SubscriptionStore(configuration: .init(productIDs: ["configured-monthly"]))
        await service.handlePurchaseResult(.userCancelled)
        #expect(service.message == nil)
        #expect(!service.hasProAccess)
        await service.handlePurchaseResult(.pending)
        #expect(service.message == L10n.proPending)
        #expect(!service.hasProAccess)
    }

}
