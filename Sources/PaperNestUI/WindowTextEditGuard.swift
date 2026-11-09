#if os(macOS)
import AppKit
import SwiftUI

/// Only weak references to each window's transient editor guard.
@MainActor public enum PaperNestPendingEdits {
    private final class Entry {
        weak var value: DocumentEditingGuard?
        init(_ value: DocumentEditingGuard) { self.value = value }
    }
    private static var entries: [Entry] = []
    private static var isFinishing = false
    static func register(_ value: DocumentEditingGuard) {
        entries.removeAll { $0.value == nil }
        if !entries.contains(where: { $0.value === value }) { entries.append(Entry(value)) }
    }
    static func unregister(_ value: DocumentEditingGuard) {
        entries.removeAll { $0.value == nil || $0.value === value }
    }
    public static func finishAll() async -> Bool {
        guard !isFinishing else { return false }
        let guards = entries.compactMap(\.value)
        guard !guards.contains(where: { $0.isClosing }) else { return false }
        isFinishing = true
        for guardState in guards { _ = guardState.beginClosing() }
        defer {
            guards.forEach { $0.endClosing() }
            isFinishing = false
        }
        let identities = Set(guards.map(ObjectIdentifier.init))
        for guardState in guards {
            guard await guardState.prepareWhileClosing() else { return false }
        }
        // A newly registered window has not participated in this quit audit.
        return Set(entries.compactMap(\.value).map(ObjectIdentifier.init)) == identities
    }
}

struct WindowTextEditGuard: NSViewRepresentable {
    let guardState: DocumentEditingGuard
    func makeCoordinator() -> Coordinator { Coordinator(guardState) }
    func makeNSView(context: Context) -> NSView {
        PaperNestPendingEdits.register(guardState)
        return NSView()
    }
    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window, window.delegate !== coordinator else { return }
            coordinator.window = window
            coordinator.original = window.delegate
            window.delegate = coordinator
        }
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        PaperNestPendingEdits.unregister(coordinator.guardState)
        if let window = coordinator.window, window.delegate === coordinator { window.delegate = coordinator.original }
    }
    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        let guardState: DocumentEditingGuard
        // Objective-C forwarding methods are nonisolated; weak loading is runtime-managed.
        nonisolated(unsafe) weak var original: NSWindowDelegate?
        weak var window: NSWindow?
        private var closing = false
        private var checking = false
        init(_ guardState: DocumentEditingGuard) { self.guardState = guardState }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if closing || (guardState.finish == nil && guardState.finishWindow == nil) {
                return original?.windowShouldClose?(sender) ?? true
            }
            guard !checking else { return false }
            checking = true
            Task {
                defer { checking = false }
                guard await guardState.prepareToCloseWindow() else { return }
                closing = true
                sender.performClose(nil)
                closing = false
            }
            return false
        }
        nonisolated override func responds(to selector: Selector!) -> Bool {
            if super.responds(to: selector) { return true }
            return original?.responds(to: selector) ?? false
        }
        nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
            original
        }
    }
}
#endif
