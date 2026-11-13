import PaperNestCore
import PaperNestSync
import SwiftUI

/// The iCloud card at the foot of the sidebar on iPad and Mac.
///
/// It says only what the sync controller says. A build made without an
/// iCloud container has nothing to sync with, and the card says that rather
/// than showing a status it cannot have.
struct CloudSyncCard: View {
    let session: LibrarySession
    /// Opens the sync settings.
    let action: () -> Void

    private var configured: CloudSyncController? {
        guard let sync = session.sync, sync.availability != .notConfigured else { return nil }
        return sync
    }

    private var statusTitle: String { configured?.status.title ?? L10n.homeSyncNotSetUp }
    private var statusSymbol: String { configured?.status.symbol ?? "icloud.slash" }
    private var statusTint: Color { configured?.status.tint ?? Theme.secondaryText }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: statusSymbol).font(.title3).foregroundStyle(statusTint)
                    .frame(minWidth: 28).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.syncSettingsTitle).font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.navy)
                    Text(statusTitle).font(.caption2).foregroundStyle(statusTint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText).accessibilityHidden(true)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border, lineWidth: 1) }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.syncSettingsTitle)
        .accessibilityValue(statusTitle)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("sidebar-sync")
    }
}
