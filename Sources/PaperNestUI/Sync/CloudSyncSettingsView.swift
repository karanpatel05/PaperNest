import PaperNestCore
import PaperNestSync
import SwiftUI

/// Settings → iCloud Sync. Sections for a `Form`.
///
/// Three things here look alike and are not: turning sync off (stops syncing
/// on this device, deletes nothing), removing a download (frees this
/// device's copy of something iCloud holds) and deleting iCloud data
/// (removes iCloud's copies, deletes nothing on any device). Each is its own
/// control, and the only destructive one asks first.
struct CloudSyncSettingsSections: View {
    let session: LibrarySession
    @State private var isConfirmingAccount = false
    @State private var isConfirmingCloudDelete = false
    @State private var isSyncing = false
    @State private var errorMessage: String?

    var body: some View {
        if let sync = session.sync {
            if sync.availability == .notConfigured {
                Section {
                    Text(L10n.syncSettingsNotConfigured)
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("sync-not-configured")
                } header: {
                    Text(L10n.syncSettingsTitle)
                }
            } else {
                main(sync)
                if !sync.conflicts.isEmpty { conflicts(sync) }
                if sync.isEnabled || sync.failure == .cloudDataDeleted { troubleshooting(sync) }
            }
        }
    }

    @ViewBuilder
    private func main(_ sync: CloudSyncController) -> some View {
        Section {
            Toggle(L10n.syncSettingsToggle, isOn: Binding(
                get: { sync.isEnabled },
                set: { wanted in setEnabled(wanted, sync) }))
                .disabled(sync.isChangingState || (!sync.isEnabled && sync.availability != .ready))
                .accessibilityIdentifier("sync-toggle")

            LabeledContent(L10n.syncSettingsAccount, value: accountText(sync.availability))

            if sync.availability == .accountChanged {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.syncAccountChangedTitle).font(.app(.subheadline).weight(.semibold))
                    Text(L10n.syncAccountChangedMessage).font(.app(.footnote)).foregroundStyle(.secondary)
                    HStack {
                        Button(L10n.syncAccountUseCurrent) { isConfirmingAccount = true }
                        Spacer()
                        Button(L10n.syncAccountStop) { resolve(.stopSyncing, sync) }
                    }
                    .buttonStyle(.borderless)
                }
                .accessibilityIdentifier("sync-account-changed")
            }

            if sync.isEnabled {
                LabeledContent(L10n.syncSettingsStatus) {
                    CloudSyncStatusView(session: session)
                }
                LabeledContent(L10n.syncSettingsLastSynced,
                               value: sync.lastSynced.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? L10n.syncSettingsNever)
                LabeledContent(L10n.syncSettingsPending, value: sync.counts.pendingChanges.formatted())
                if sync.counts.pendingUploads > 0 {
                    LabeledContent(L10n.syncSettingsPendingUploads, value: sync.counts.pendingUploads.formatted())
                }
                if sync.counts.pendingDownloads > 0 {
                    LabeledContent(L10n.syncSettingsPendingDownloads, value: sync.counts.pendingDownloads.formatted())
                }
                Button {
                    isSyncing = true
                    Task {
                        await sync.syncNow()
                        isSyncing = false
                    }
                } label: {
                    HStack {
                        Text(L10n.syncSettingsSyncNow)
                        if isSyncing { Spacer(); ProgressView().controlSize(.small) }
                    }
                }
                .disabled(isSyncing || sync.availability != .ready)
                .accessibilityIdentifier("sync-now")
            }

            if let issue = issueText(sync) {
                Label {
                    Text(issue).font(.app(.footnote))
                } icon: {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                .accessibilityIdentifier("sync-issue")
            }
            if let errorMessage {
                Text(errorMessage).font(.app(.footnote)).foregroundStyle(.red)
            }
        } header: {
            Text(L10n.syncSettingsTitle)
        } footer: {
            Text(L10n.syncSettingsFooter)
        }
        .confirmationDialog(L10n.syncAccountChangedTitle, isPresented: $isConfirmingAccount, titleVisibility: .visible) {
            Button(L10n.syncAccountUseCurrent) { resolve(.syncWithCurrentAccount, sync) }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.syncAccountUseCurrentConfirm)
        }

        if sync.isEnabled {
            Section {
                Toggle(L10n.syncSettingsOnDemand, isOn: Binding(
                    get: { sync.downloadsOnDemand },
                    set: { wanted in Task { await sync.setDownloadsOnDemand(wanted) } }))
                    .accessibilityIdentifier("sync-on-demand")
            } footer: {
                Text(L10n.syncSettingsOnDemandFooter)
            }
        }
    }

    private func conflicts(_ sync: CloudSyncController) -> some View {
        Section(L10n.syncConflictTitle) {
            ForEach(sync.conflicts) { conflict in
                VStack(alignment: .leading, spacing: 8) {
                    let name = conflict.itemName ?? L10n.syncConflictSomeDocument
                    Text(conflict.kind == .pageVersion ? L10n.syncConflictPage(name) : L10n.syncConflictObject(name))
                        .font(.app(.footnote))
                    HStack {
                        Button(L10n.syncConflictKeepBoth) {
                            Task { await sync.resolveConflict(conflict.id, keepingCopy: true) }
                        }
                        Spacer()
                        Button(L10n.syncConflictRemoveCopy, role: .destructive) {
                            Task { await sync.resolveConflict(conflict.id, keepingCopy: false) }
                        }
                    }
                    .buttonStyle(.borderless)
                }
                .accessibilityIdentifier("sync-conflict")
            }
        }
    }

    private func troubleshooting(_ sync: CloudSyncController) -> some View {
        Section {
            Text(L10n.syncTroubleText).font(.app(.footnote)).foregroundStyle(.secondary)
            if sync.isEnabled {
                Button(L10n.syncDeleteCloud, role: .destructive) { isConfirmingCloudDelete = true }
                    .disabled(sync.isChangingState || sync.availability != .ready)
                    .accessibilityIdentifier("sync-delete-cloud")
            }
        } header: {
            Text(L10n.syncTroubleTitle)
        }
        .confirmationDialog(L10n.syncDeleteCloudTitle, isPresented: $isConfirmingCloudDelete, titleVisibility: .visible) {
            Button(L10n.syncDeleteCloudConfirm, role: .destructive) {
                Task {
                    do { try await sync.deleteCloudData() } catch { errorMessage = L10n.syncActionFailed }
                }
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.syncDeleteCloudMessage)
        }
    }

    private func setEnabled(_ wanted: Bool, _ sync: CloudSyncController) {
        errorMessage = nil
        Task {
            // Attaching this library to a different iCloud account is never
            // done on the strength of a switch alone.
            if wanted, await sync.enablingWouldSwitchAccounts() {
                isConfirmingAccount = true
                return
            }
            do { try await sync.setEnabled(wanted) } catch { errorMessage = L10n.syncEnableFailed }
        }
    }

    private func resolve(_ choice: CloudSyncController.AccountChoice, _ sync: CloudSyncController) {
        errorMessage = nil
        Task {
            do { try await sync.resolveAccountChange(choice) } catch { errorMessage = L10n.syncEnableFailed }
        }
    }

    private func accountText(_ availability: CloudSyncController.Availability) -> String {
        switch availability {
        case .ready: L10n.syncAccountReady
        case .checking: L10n.syncAccountChecking
        case .noAccount: L10n.syncAccountNoAccount
        case .restricted: L10n.syncAccountRestricted
        case .temporarilyUnavailable: L10n.syncAccountTemporarilyUnavailable
        case .accountChanged: L10n.syncAccountChangedTitle
        case .unknown, .notConfigured: L10n.syncAccountUnknown
        }
    }

    private func issueText(_ sync: CloudSyncController) -> String? {
        switch sync.failure {
        case .quotaExceeded: return L10n.syncIssueQuota
        case .cloudDataDeleted: return L10n.syncIssueCloudDeleted
        case .other: return L10n.syncIssueGeneral
        case nil: break
        }
        if sync.needsNewerApp { return L10n.syncIssueNewerApp }
        if sync.isEnabled, sync.counts.failedChanges > 0 { return L10n.syncIssueGeneral }
        return nil
    }
}
