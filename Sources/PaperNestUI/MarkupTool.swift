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
    case pen, highlighter, eraser, lasso
    /// Dragging out one of the Shapes tool's outlines. It saves ink, but as
    /// a whole shape on release rather than a freehand stroke, so it is not
    /// an `ink` tool here and the freehand canvases never see it.
    case shape

    /// The stroke this tool draws, or nil when it draws nothing.
    var ink: InkStroke.Tool? {
        switch self {
        case .pen: .pen
        case .highlighter: .highlighter
        case .eraser, .lasso, .shape: nil
        }
    }

    /// Nominal width in source points.
    ///
    /// **A highlighter is not a thick pen.** Both tools shared one row of
    /// widths — 1, 2 and 4 points — which is right for a pen on an A4 page
    /// and draws a hairline for a highlighter: a yellow line *on* the words
    /// rather than a band behind them. Its own scale starts where the pen's
    /// ends, and its middle step covers an 18-point line of text, which is
    /// the size a text box defaults to.
    func width(for weight: MarkupWeight) -> Double {
        switch self {
        case .pen:
            switch weight {
            case .thin: 1
            case .medium: 2
            case .thick: 4
            }
        case .highlighter:
            switch weight {
            case .thin: 12
            case .medium: 20
            case .thick: 30
            }
        case .eraser, .lasso, .shape: 0
        }
    }
}

/// How heavy a mark is, chosen once and read differently by each tool.
///
/// The row the user sees says Thin, Medium and Thick rather than a number,
/// so what those mean can differ per tool without the control changing. It
/// also means switching from a thick highlighter to the pen does not leave a
/// 30-point pen armed.
enum MarkupWeight: String, Hashable, CaseIterable {
    case thin, medium, thick
}
