import Foundation
import Observation
import PaperNestCore
import PaperNestExport
import PaperNestRender
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
                var entries: [LibraryExportEntry] = []
                for summary in try await env.store.items(in: .all) {
                    if let payload = summary.file {
                        // A backup that quietly dropped the user's files
                        // would not be a backup. The original is resolved
                        // through the record's own kind, because an assumed
                        // kind names a file that was never written and fails
                        // the entire backup over one shared original.
                        entries.append(.file(name: summary.item.name, originalFilename: payload.originalFilename,
                                             url: try await env.store.originalURL(for: payload.assetID)))
                    } else {
                        entries.append(.document(LibraryExportItem(name: summary.item.name,
                                                                   pages: try await env.store.pages(of: summary.id))))
                    }
                }
                let output = try await env.exporter.exportArchive(entries, archiveName: archiveName) { progress in
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
/// the Mac shows it in the standard Settings window (⌘,). iCloud Sync shows
/// its real state, including "not available in this build"; the Pro section
/// arrives with milestone M5 and nothing here pretends to offer it.
public struct SettingsView: View {
    @State private var model: SettingsModel
    @State private var isShowingSaver = false
    @AppStorage(RecognitionLanguagePreference.key) private var recognitionLanguageCodes = ""
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.openURL) private var openURL
    /// Present wherever the library is behind the app lock (iPhone, iPad).
    @Environment(AppLock.self) private var appLock: AppLock?
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
            // The Mac's Settings window is a scene of its own, outside RootView.
            .modifier(AppTypography())
        #endif
    }

    /// Which languages text recognition reads in.
    ///
    /// Only what this device's Vision actually supports is offered — the set
    /// differs by OS version, and a row that cannot work is a promise that
    /// cannot be kept. A choice already stored that this device cannot read
    /// is still called out, because it may have been made on another Mac.
    @ViewBuilder private var recognitionLanguages: some View {
        let available = TextRecognizer.availableLanguages()
        let chosen = RecognitionLanguagePreference.codes(from: recognitionLanguageCodes)
        Section {
            // Vision reads close to thirty languages, and on macOS this Form
            // sizes itself to its content — a row each made the Settings
            // window 1834 points tall, well past any screen. The list gets a
            // height of its own and scrolls inside it.
            let rows = ForEach(available, id: \.self) { code in
                Toggle(isOn: Binding(
                    get: { chosen.contains(code) },
                    set: { wanted in
                        var next = chosen.filter { $0 != code }
                        if wanted { next.append(code) }
                        recognitionLanguageCodes = RecognitionLanguagePreference.stored(from: next)
                    })) {
                        Text(RecognitionLanguagePreference.name(of: code))
                    }
                    .accessibilityIdentifier("recognition-language-\(code)")
            }
            #if os(macOS)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) { rows }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 4)
            }
            .frame(height: 190)
            #else
            rows
            #endif
            let unavailable = chosen.filter { !available.contains($0) }
            if !unavailable.isEmpty {
                Text(L10n.settingsRecognitionUnavailable(
                    unavailable.map(RecognitionLanguagePreference.name(of:))
                        .formatted(.list(type: .and))))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("recognition-language-unavailable")
            }
        } header: {
            Text(L10n.settingsRecognitionLanguages).foregroundStyle(Color.primary)
        } footer: {
            Text(L10n.settingsRecognitionLanguagesFooter).foregroundStyle(Color.primary)
        }
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

            #if os(iOS)
            if let appLock { AppLockSettingsSection(lock: appLock) }
            #endif

            CloudSyncSettingsSections(session: model.session)

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

            recognitionLanguages

            Section(L10n.settingsAbout) {
                LabeledContent(L10n.settingsVersion, value: Self.version)
                Text(L10n.settingsPrivacy)
                    .font(.app(.footnote))
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
                        .font(.app(.caption))
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
