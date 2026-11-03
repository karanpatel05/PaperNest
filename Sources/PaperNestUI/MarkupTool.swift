import PaperNestCore

// The editor's drawing-mode state, in its own file rather than inside the
// macOS-only canvas: only the Mac canvas acts on it, but `DocumentView`
// holds it on both platforms, and guarding a stored property means guarding
// every call site that passes it along.
/// What a drag on the drawing canvas is doing.
///
/// Deliberately **not** `InkStroke.Tool`, which is persisted: an eraser is a
/// mode, not a kind of mark, and putting it in the stored enum would invite a
/// stroke that claims to be one.
enum MacMarkupTool: String, Hashable, CaseIterable {
    case pen, highlighter, eraser

    /// The stroke this tool draws, or nil when it draws nothing.
    var ink: InkStroke.Tool? {
        switch self {
        case .pen: .pen
        case .highlighter: .highlighter
        case .eraser: nil
        }
    }
}
