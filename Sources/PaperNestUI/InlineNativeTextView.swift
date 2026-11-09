import PaperNestCore
import SwiftUI

#if os(iOS)
import UIKit

struct InlineNativeTextView: UIViewRepresentable {
    let session: InlineTextSession
    let box: TextBox
    let focusRequest: Int
    let onChange: (String) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = true
        view.delegate = context.coordinator
        view.accessibilityIdentifier = "inline-text-editor"
        view.accessibilityLabel = L10n.textBoxText
        view.keyboardDismissMode = .none
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        session.commitNative = { [weak view, weak session] in
            guard let view, let session else { return }
            view.unmarkText()
            session.change { $0.text = view.text }
            view.resignFirstResponder()
        }
        guard view.markedTextRange == nil else { return }
        let selection = view.selectedRange
        if view.text != box.text { view.text = box.text }
        view.font = UIFont(name: box.postScriptFontName, size: box.fontSize)
        view.textColor = UIColor(red: box.color.red, green: box.color.green, blue: box.color.blue, alpha: box.color.alpha)
        view.textAlignment = box.alignment == .center ? .center : box.alignment == .trailing ? .right : .left
        view.selectedRange = NSRange(location: min(selection.location, view.text.utf16.count), length: min(selection.length, max(0, view.text.utf16.count - selection.location)))
        if context.coordinator.focus != focusRequest {
            context.coordinator.focus = focusRequest
            DispatchQueue.main.async { [weak view] in view?.becomeFirstResponder() }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: InlineNativeTextView
        var focus = -1
        init(_ parent: InlineNativeTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            if textView.markedTextRange == nil { parent.onChange(textView.text) }
        }
    }
}
#else
import AppKit

struct InlineNativeTextView: NSViewRepresentable {
    let session: InlineTextSession
    let box: TextBox
    let focusRequest: Int
    let onChange: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        let view = NSTextView()
        view.drawsBackground = false
        view.isRichText = false
        view.allowsUndo = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.delegate = context.coordinator
        view.setAccessibilityIdentifier("inline-text-editor")
        view.setAccessibilityLabel(L10n.textBoxText)
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        session.commitNative = { [weak view, weak session] in
            guard let view, let session else { return }
            view.unmarkText()
            session.change { $0.text = view.string }
            view.window?.makeFirstResponder(nil)
        }
        guard !view.hasMarkedText() else { return }
        let selection = view.selectedRange()
        if view.string != box.text { view.string = box.text }
        let style = NSMutableParagraphStyle()
        style.alignment = box.alignment == .center ? .center : box.alignment == .trailing ? .right : .left
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: box.postScriptFontName, size: box.fontSize) ?? NSFont.systemFont(ofSize: box.fontSize),
            .foregroundColor: NSColor(red: box.color.red, green: box.color.green, blue: box.color.blue, alpha: box.color.alpha),
            .paragraphStyle: style
        ]
        view.textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: view.string.utf16.count))
        view.typingAttributes = attributes
        view.setSelectedRange(NSRange(location: min(selection.location, view.string.utf16.count), length: min(selection.length, max(0, view.string.utf16.count - selection.location))))
        if context.coordinator.focus != focusRequest {
            context.coordinator.focus = focusRequest
            DispatchQueue.main.async { [weak view] in
                guard let view else { return }
                view.window?.makeFirstResponder(view)
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InlineNativeTextView
        var focus = -1
        init(_ parent: InlineNativeTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView, !view.hasMarkedText() else { return }
            parent.onChange(view.string)
        }
    }
}
#endif
