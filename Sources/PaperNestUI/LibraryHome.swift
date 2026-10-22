import PaperNestCore
import PaperNestStore
import SwiftUI

/// The iPhone home, shown above the library scopes and folders in the
/// sidebar column (see `iphone-scan-library.png`): Scan and Import, then
/// a row of the newest documents.
struct LibraryHomeSections: View {
    @Bindable var model: LibraryModel

    var body: some View {
        // In a header, not a row: buttons in a List row lose their styles
        // (Scan showed enabled without a camera) and can fire together.
        Section {
        } header: {
            CaptureActions(model: model)
                .textCase(nil)
                .padding(.bottom, 4)
        }
        if !model.recentItems.isEmpty {
            // Also a header: list rows clip to rounded corners, which cut
            // into the first card's date line.
            Section {
            } header: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L10n.homeRecent)
                        Spacer()
                        Button(L10n.homeSeeAll) { model.sidebarSelection = .all }
                            .font(.subheadline)
                            .accessibilityIdentifier("home-see-all")
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(model.recentItems) { summary in
                                Button { model.open(summary.id) } label: {
                                    ItemCell(summary: summary, showsDeletionDate: false, layout: .grid, reservesMenuSpace: false,
                                             tileBackground: Theme.surface)
                                        .frame(width: 128)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollClipDisabled()
                    .foregroundStyle(Color.primary)   // headers default to secondary text
                    .accessibilityIdentifier("home-recent")
                }
                .textCase(nil)
            }
        }
    }
}
