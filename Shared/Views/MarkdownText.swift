import SwiftUI

struct MarkdownText: View {
    let raw: String
    var enablesSelection: Bool = false

    var body: some View {
        rendered
    }

    @ViewBuilder
    private var rendered: some View {
        if raw.isEmpty {
            Text("...")
        } else if let attributed = Self.parse(raw, syntax: .full) {
            selectable(Text(attributed))
        } else if let attributed = Self.parse(raw, syntax: .inlineOnlyPreservingWhitespace) {
            selectable(Text(attributed))
        } else {
            selectable(Text(raw))
        }
    }

    private static func parse(
        _ raw: String,
        syntax: AttributedString.MarkdownParsingOptions.InterpretedSyntax
    ) -> AttributedString? {
        try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: syntax, failurePolicy: .returnPartiallyParsedIfPossible)
        )
    }

    @ViewBuilder
    private func selectable(_ text: Text) -> some View {
        if enablesSelection {
            #if os(iOS)
            text.textSelection(.enabled)
            #else
            text
            #endif
        } else {
            text
        }
    }
}
