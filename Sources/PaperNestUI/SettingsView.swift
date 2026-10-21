import Foundation
import Observation
import PaperNestCore
import PaperNestExport
import PaperNestStore
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Storage figures and the export-all backup for the Settings screen.
@MainActor @Observable
final class SettingsModel {
    enum BackupPhase {
        case idle
        case exporting(ExportProgress)
        case ready(ExportOutput)
        case failed
    }

    let session: LibrarySession
    private(set) var usage: LibraryStore.StorageUsage?
    private(set) var backup: BackupPhase = .idle
    private var backupTask: Task<Void, Never>?

    init(session: LibrarySession) {
        self.session = session
    }

    func refresh() async {
        usage = try? await session.environment?.store.storageUsage()
    }

    /// Exports every document (not Recently Deleted) as a PDF into one ZIP.
    func startBackup() {
        guard let env = session.environment, case .idle = backup else { return }
        let date = Date().formatted(.iso8601.year().month().day())
        let archiveName = L10n.backupArchiveName(date)
        backup = .exporting(ExportProgress(completedPages: 0, totalPages: usage?.pages ?? 0))
        backupTask = Task {
            do {
                var items: [LibraryExportItem] = []
                for summary in try await env.store.items(in: .all) {
                    items.append(LibraryExportItem(name: summary.item.name, pages: try await env.store.pages(of: summary.id)))
                }
                let output = try await env.exporter.exportLibrary(items, archiveName: archiveName) { progress in
                    Task { @MainActor in
                        if case .exporting = self.backup { self.backup = .exporting(progress) }
                    }
                }
                if Task.isCancelled {
                    output.removeTemporaryFiles()
                } else {
                    backup = .ready(output)
                }
            } catch is CancellationError {
                backup = .idle
            } catch {
                backup = .failed
            }
        }
    }

    func cancelBackup() {
        backupTask?.cancel()
        backup = .idle
    }

    /// Removes the temporary archive once it has been saved or shared.
    func finishBackup() {
        if case .ready(let output) = backup { output.removeTemporaryFiles() }
        backup = .idle
    }
}

/// App settings. iPhone and iPad present it as a sheet from the library;
/// the Mac shows it in the standard Settings window (⌘,). Sync and Pro
/// sections arrive with milestones M2 and M5; until then nothing here
/// pretends to offer them.
public struct SettingsView: View {
    @State private var model: SettingsModel
    @State private var isShowingSaver = false
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.openURL) private var openURL
    #endif

    public init(session: LibrarySession) {
        _model = State(initialValue: SettingsModel(session: session))
    }

    public var body: some View {
        #if os(iOS)
        NavigationStack {
            form
                .navigationTitle(L10n.settingsTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.done) { dismiss() }
                    }
                }
        }
        #else
        form
            .frame(width: 480)
            .fixedSize(horizontal: false, vertical: true)
        #endif
    }

    private var form: some View {
        Form {
            Section {
                LabeledContent(L10n.settingsDocuments, value: model.usage.map { $0.documents.formatted() } ?? "—")
                LabeledContent(L10n.pages, value: model.usage.map { $0.pages.formatted() } ?? "—")
                LabeledContent(L10n.settingsSpaceUsed,
                               value: model.usage.map { ByteCountFormatter.string(fromByteCount: $0.bytes, countStyle: .file) } ?? "—")
            } header: {
                Text(L10n.settingsStorage)
            } footer: {
                Text(L10n.settingsStorageFooter(days: RetentionPolicy.recentlyDeletedDays))
            }

            Section {
                backupRow
            } footer: {
                Text(L10n.settingsExportAllFooter)
            }

            Section {
                LabeledContent(L10n.settingsLanguage, value: Self.currentLanguageName)
                #if os(iOS)
                Button(L10n.settingsChangeLanguage) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                #endif
            } footer: {
                #if os(macOS)
                Text(L10n.settingsLanguageMac)
                #endif
            }

            Section(L10n.settingsAbout) {
                LabeledContent(L10n.settingsVersion, value: Self.version)
                Text(L10n.settingsPrivacy)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // Refresh whenever the library changes (the Mac window stays open).
        .task(id: model.session.changeToken) { await model.refresh() }
        .onDisappear { model.cancelBackup() }
        .modifier(SaveExportedFiles(isPresented: $isShowingSaver, output: readyOutput, format: .pdf) {
            model.finishBackup()
        })
    }

    @ViewBuilder
    private var backupRow: some View {
        switch model.backup {
        case .idle:
            Button(L10n.settingsExportAll) { model.startBackup() }
                .disabled((model.usage?.documents ?? 0) == 0)
        case .exporting(let progress):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress.fraction) {
                    Text(L10n.exportProgress(min(progress.completedPages + 1, max(progress.totalPages, 1)), max(progress.totalPages, 1)))
                        .font(.caption)
                }
                Button(L10n.cancel, role: .cancel) { model.cancelBackup() }
            }
        case .ready(let output):
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.exportReady(ByteCountFormatter.string(fromByteCount: output.totalByteCount, countStyle: .file)))
                HStack {
                    ShareLink(items: output.files) {
                        Label(L10n.exportShare, systemImage: "square.and.arrow.up")
                    }
                    Spacer()
                    Button(L10n.exportSave) { isShowingSaver = true }
                    Button(L10n.done) { model.finishBackup() }
                }
                .buttonStyle(.borderless)
            }
        case .failed:
            HStack {
                Text(L10n.exportFailed).foregroundStyle(.red)
                Spacer()
                Button(L10n.ok) { model.finishBackup() }
            }
        }
    }

    private var readyOutput: ExportOutput? {
        if case .ready(let output) = model.backup { return output }
        return nil
    }

    /// The language the app is showing, named in that language.
    private static var currentLanguageName: String {
        let code = ResourceBundle.ui.preferredLocalizations.first ?? "en"
        let name = Locale(identifier: code).localizedString(forLanguageCode: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
