import PaperNestCore
import PaperNestStore
import SwiftUI

/// The app's main window: a sidebar of library scopes and a navigation
/// stack from the library grid into documents. Adapts from iPhone (stacked)
/// to iPad and Mac (side by side).
public struct RootView: View {
    @State private var model: LibraryModel

    public init(session: LibrarySession) {
        _model = State(initialValue: LibraryModel(session: session))
    }

    public var body: some View {
        Group {
            switch model.session.state {
            case .loading:
                ProgressView(L10n.loadingLibrary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let title, let message):
                ContentUnavailableView(title, systemImage: "exclamationmark.triangle", description: Text(message))
            case .ready:
                splitView
            }
        }
        .environment(model.session)
        .tint(Theme.accent)
        .task { await model.session.bootstrap() }
    }

    private var splitView: some View {
        NavigationSplitView {
            List(selection: $model.sidebarSelection) {
                Section(L10n.sidebarLibrary) {
                    Label(L10n.allDocuments, systemImage: "doc.on.doc").tag(LibraryStore.Scope.all)
                    Label(L10n.favorites, systemImage: "star").tag(LibraryStore.Scope.favorites)
                    Label(L10n.recentlyDeleted, systemImage: "trash").tag(LibraryStore.Scope.recentlyDeleted)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            #if os(macOS)
            .navigationTitle(Brand.displayName)
            #endif
        } detail: {
            NavigationStack(path: $model.path) {
                LibraryView(model: model)
                    .navigationDestination(for: ItemID.self) { id in
                        DocumentView(itemID: id, session: model.session)
                    }
            }
        }
        .focusedSceneValue(\.libraryModel, model)
        #if DEBUG
        .task { await openDebugItemIfRequested() }
        #endif
    }

    #if DEBUG
    /// Dev/screenshot hook, debug builds only: `-PaperNestDebugOpenItem <name>`
    /// opens that document as if it had been tapped.
    private func openDebugItemIfRequested() async {
        guard let name = UserDefaults.standard.string(forKey: "PaperNestDebugOpenItem"),
              let store = model.session.environment?.store,
              let match = try? await store.items(in: .all).first(where: { $0.item.name == name })
        else { return }
        model.path = [match.id]
    }
    #endif
}

struct LibraryModelKey: FocusedValueKey {
    typealias Value = LibraryModel
}

struct DocumentCommandsKey: FocusedValueKey {
    typealias Value = DocumentCommandContext
}

/// What the Page menu needs from the focused document window.
struct DocumentCommandContext {
    let model: DocumentModel
    let undoManager: UndoManager?
    let showExport: () -> Void
    let showAddPages: () -> Void
    let showCrop: () -> Void
}

extension FocusedValues {
    var libraryModel: LibraryModel? {
        get { self[LibraryModelKey.self] }
        set { self[LibraryModelKey.self] = newValue }
    }

    var documentCommands: DocumentCommandContext? {
        get { self[DocumentCommandsKey.self] }
        set { self[DocumentCommandsKey.self] = newValue }
    }
}
