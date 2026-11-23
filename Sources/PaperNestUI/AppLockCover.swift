#if os(iOS)
import PaperNestCore
import SwiftUI
import UIKit

extension View {
    /// Hides the library behind the app lock in this window. Two layers:
    /// a cover drawn with the window's own content, so even the first frame
    /// after launch shows nothing; and a window of the lock's own above
    /// everything the scene shows — sheets, full-screen views and alerts
    /// included — which takes the touches, the keyboard and VoiceOver.
    /// iPad windows opened while locked get theirs as they open.
    public func appLocked(_ lock: AppLock) -> some View {
        modifier(AppLockModifier(lock: lock))
    }
}

private struct AppLockModifier: ViewModifier {
    let lock: AppLock

    func body(content: Content) -> some View {
        content
            .accessibilityHidden(lock.hidesLibrary)
            .overlay {
                if lock.hidesLibrary {
                    // Only the backdrop: the scene window above holds the
                    // lock screen that is read and tapped. This copy is what
                    // covers the first frame, before that window is up.
                    AppLockScreen(lock: lock, isBackdrop: true)
                }
            }
            .background { AppLockSceneWindow(lock: lock, isShown: lock.hidesLibrary) }
            .environment(lock)
    }
}

/// Puts the lock's own window into the scene this view is in, above alert
/// level, and shows or hides it.
private struct AppLockSceneWindow: UIViewRepresentable {
    let lock: AppLock
    let isShown: Bool

    func makeCoordinator() -> Coordinator { Coordinator(lock: lock) }

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        probe.coordinator = context.coordinator
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        context.coordinator.show(isShown, in: probe.window?.windowScene)
    }

    static func dismantleUIView(_ probe: Probe, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    final class Probe: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.sceneChanged(window?.windowScene)
        }
    }

    @MainActor final class Coordinator {
        private let lock: AppLock
        private var cover: UIWindow?
        private var isShown = false

        init(lock: AppLock) { self.lock = lock }

        func sceneChanged(_ scene: UIWindowScene?) {
            guard let scene else { return }
            if cover?.windowScene !== scene {
                tearDown()
                install(in: scene)
            }
            apply()
        }

        func show(_ shown: Bool, in scene: UIWindowScene?) {
            isShown = shown
            if cover == nil, let scene { install(in: scene) }
            apply()
        }

        private func install(in scene: UIWindowScene) {
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            let host = UIHostingController(rootView: AppLockScreen(lock: lock))
            host.view.backgroundColor = .clear
            // VoiceOver stays here and never reads what is underneath.
            host.view.accessibilityViewIsModal = true
            window.rootViewController = host
            window.isHidden = true
            cover = window
        }

        private func apply() {
            guard let cover else { return }
            if isShown {
                // Key, so a hardware keyboard cannot type into a field below.
                if cover.isHidden || !cover.isKeyWindow { cover.makeKeyAndVisible() }
            } else if !cover.isHidden {
                cover.isHidden = true
                cover.windowScene?.windows
                    .first { $0 !== cover && !$0.isHidden && $0.windowLevel == .normal }?
                    .makeKey()
            }
        }

        func tearDown() {
            cover?.isHidden = true
            cover = nil
        }
    }
}

/// What shows while the library is hidden: the lock with its Unlock button,
/// or only the mark while PaperNest is not in front.
struct AppLockScreen: View {
    let lock: AppLock
    /// The paper and the mark only: nothing to read or tap.
    var isBackdrop = false

    var body: some View {
        if isBackdrop {
            ZStack {
                Theme.libraryBackground.ignoresSafeArea()
                BrandMark.image(size: 64)
            }
            .accessibilityHidden(true)
        } else {
            screen
        }
    }

    private var screen: some View {
        ZStack {
            Theme.libraryBackground.ignoresSafeArea()
            VStack(spacing: 18) {
                BrandMark.image(size: 64)
                    .accessibilityHidden(true)
                if lock.isLocked {
                    Text(L10n.appLockLocked)
                        .font(.app(.title2).weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if lock.lastAttemptFailed && !lock.isAuthenticating {
                        Text(L10n.appLockStillLocked)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("app-lock-failed")
                    }
                    Button { Task { await lock.unlock() } } label: {
                        Label(L10n.appLockUnlock, systemImage: Self.symbol(lock.availability.biometry))
                            .font(.app(.headline))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 28)
                            .frame(minWidth: 180, minHeight: 50)
                            .background(EditorChrome.selection, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(lock.isAuthenticating)
                    .accessibilityIdentifier("app-lock-unlock")
                }
            }
            .padding(24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(lock.isLocked ? "app-lock-screen" : "app-lock-cover")
    }

    static func symbol(_ biometry: AppLockBiometry?) -> String {
        switch biometry {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .passcode, nil: "lock.fill"
        }
    }
}

/// Settings → Privacy: the lock's switch and how soon it asks again. Inline
/// option rows rather than a pop-up, which cuts French and Spanish short.
struct AppLockSettingsSection: View {
    let lock: AppLock
    /// The last attempt to turn the lock on or off was not confirmed.
    @State private var unchanged = false

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { lock.policy.isEnabled },
                set: { wanted in Task { unchanged = !(await lock.setEnabled(wanted)) } })) {
                    Text(title).fixedSize(horizontal: false, vertical: true)
                }
                .disabled(lock.availability == .cannotAsk || lock.isAuthenticating)
                .accessibilityIdentifier("settings-app-lock")
            if unchanged {
                Text(L10n.appLockUnchanged)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings-app-lock-unchanged")
            }
        } header: {
            Text(L10n.appLockSection)
        } footer: {
            Text(lock.availability == .cannotAsk ? L10n.appLockUnavailable : L10n.appLockFooter)
                .accessibilityIdentifier("settings-app-lock-footer")
        }
        if lock.policy.isEnabled {
            Section(L10n.appLockGraceHeader) {
                ForEach(AppLockPolicy.Grace.allCases, id: \.self) { grace in
                    let chosen = lock.policy.grace == grace
                    Button { lock.setGrace(grace) } label: {
                        HStack {
                            Text(Self.title(grace)).foregroundStyle(Color.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 12)
                            if chosen {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("settings-app-lock-grace-\(grace.rawValue)")
                    .accessibilityValue(chosen ? L10n.selectionOn : L10n.selectionOff)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
        }
    }

    private var title: String {
        switch lock.availability.biometry {
        case .faceID: L10n.appLockRequireFaceID
        case .touchID: L10n.appLockRequireTouchID
        case .opticID: L10n.appLockRequireOpticID
        case .passcode, nil: L10n.appLockRequirePasscode
        }
    }

    static func title(_ grace: AppLockPolicy.Grace) -> String {
        switch grace {
        case .immediately: L10n.appLockGraceImmediately
        case .oneMinute: L10n.appLockGraceOneMinute
        case .fiveMinutes: L10n.appLockGraceFiveMinutes
        case .fifteenMinutes: L10n.appLockGraceFifteenMinutes
        }
    }
}
#endif
