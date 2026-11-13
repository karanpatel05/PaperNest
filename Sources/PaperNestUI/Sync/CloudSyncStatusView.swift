import PaperNestCore
import PaperNestSync
import SwiftUI

extension SyncStatus {
    var title: String {
        switch self {
        case .savedLocally: L10n.syncStatusSavedLocally
        case .waiting: L10n.syncStatusWaiting
        case .syncing: L10n.syncStatusSyncing
        case .upToDate: L10n.syncStatusUpToDate
        case .offline: L10n.syncStatusOffline
        case .cloudUnavailable: L10n.syncStatusCloudUnavailable
        case .conflict: L10n.syncStatusConflict
        case .needsAttention: L10n.syncStatusNeedsAttention
        }
    }

    var symbol: String {
        switch self {
        case .savedLocally: "internaldrive"
        case .waiting: "icloud.and.arrow.up"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .upToDate: "checkmark.icloud"
        case .offline: "icloud.slash"
        case .cloudUnavailable: "xmark.icloud"
        case .conflict: "exclamationmark.triangle"
        case .needsAttention: "exclamationmark.icloud"
        }
    }

    var tint: Color {
        switch self {
        case .savedLocally, .offline: Theme.secondaryText
        case .waiting, .syncing, .upToDate: Theme.accent
        case .cloudUnavailable, .conflict, .needsAttention: .orange
        }
    }
}

/// The small sync status shown on the home screen and in the editor.
///
/// It draws nothing in a build that has no iCloud container: a status for a
/// feature that cannot run would be decoration. Everything it shows is read
/// from the controller, which reads it from the outbox and the engine.
struct CloudSyncStatusView: View {
    enum Style {
        /// Icon and words, for the home screen.
        case labeled
        /// Icon only, for the editor's toolbar, where the title needs the room.
        case compact
    }

    let session: LibrarySession
    var style: Style = .labeled

    var body: some View {
        if let sync = session.sync, sync.availability != .notConfigured {
            let status = sync.status
            Group {
                switch style {
                case .labeled:
                    Label {
                        Text(status.title)
                    } icon: {
                        Image(systemName: status.symbol)
                    }
                    .font(.caption.weight(.medium))
                case .compact:
                    Image(systemName: status.symbol)
                        .font(.subheadline)
                        .help(status.title)
                }
            }
            .foregroundStyle(status.tint)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.syncSettingsTitle)
            .accessibilityValue(status.title)
            .accessibilityIdentifier("sync-status")
        }
    }
}

/// Marks a document whose pages are in iCloud and not on this device.
struct DocumentCloudBadge: View {
    var isDownloading = false

    var body: some View {
        Group {
            if isDownloading {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "icloud.and.arrow.down").font(.caption)
            }
        }
        .foregroundStyle(Theme.accent)
        .accessibilityLabel(L10n.syncItemCloudOnly)
        .accessibilityIdentifier("item-cloud-only")
    }
}

extension CloudSyncController {
    /// Opening a document that is only in iCloud is asking for it.
    func downloadIfNeeded(_ item: ItemID) async {
        guard cloudOnlyItems.contains(item), !downloading.contains(item) else { return }
        await download(item)
    }
}
