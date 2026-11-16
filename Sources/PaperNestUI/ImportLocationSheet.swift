import PaperNestCore
import SwiftUI

/// A destination is chosen before any imported item is written.
struct ImportLocationSheet: View {
    @Bindable var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var location: Location = .home
    @State private var folderName = ""

    private enum Location: Hashable {
        case home, folder(FolderID), newFolder
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker(L10n.importLocationTitle, selection: $location) {
                    Text(L10n.importLocationHome).tag(Location.home)
                    ForEach(model.folders) { folder in
                        Text(folder.name).tag(Location.folder(folder.id))
                    }
                    Text(L10n.newFolder).tag(Location.newFolder)
                }
                .pickerStyle(.inline)
                .accessibilityIdentifier("import-location-picker")
                if location == .newFolder {
                    TextField(L10n.renamePlaceholder, text: $folderName)
                        .accessibilityIdentifier("import-location-new-folder")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(EditorChrome.secondaryBackground)
            // The inline picker supplies the wrapping heading. A duplicate
            // large navigation title truncates in French and accessibility sizes.
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                        .accessibilityIdentifier("import-location-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.importLocationSave) {
                        switch location {
                        case .home: model.importLocationChoice = .home
                        case .folder(let id): model.importLocationChoice = .folder(id)
                        case .newFolder: model.importLocationChoice = .newFolder(folderName.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        dismiss()
                    }
                    .disabled(location == .newFolder && folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("import-location-save")
                }
            }
        }
        .toolPanelAppearance()
        #if os(macOS)
        .frame(minWidth: 400, idealWidth: 460, minHeight: 360, idealHeight: 440)
        #endif
        .onAppear {
            if let id = model.currentFolderID { location = .folder(id) }
        }
    }
}
