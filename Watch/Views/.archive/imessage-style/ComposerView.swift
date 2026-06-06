import SwiftUI
import os.log

private let composerLog = Logger(subsystem: "com.wristassistant.app.watchkitapp", category: "ComposerView")

/// Tag for the composer TextField. The parent ChatView drives the
/// `@FocusState` binding with this same tag value, so the focus
/// can be raised imperatively from the parent's `.onAppear` when the
/// chat view appears.
enum ComposerField: Hashable { case reply }

/// Floating reply box used by the watch chat view — modeled on the
/// Apple Watch iMessage reply field:
///
///   ┌──────────────────────────────────────────┐
///   │  🎤  Reply                       ( ➤ )   │
///   └──────────────────────────────────────────┘
///
/// - A dictation microphone glyph on the **left** signals the user
///   can tap the field to start dictation. Tapping the glyph is the
///   same as tapping the field — both focus the TextField and raise
///   the watchOS keyboard / dictation UI.
/// - A `TextField` with placeholder "Reply" runs across the middle.
/// - A small filled circle with an up-arrow appears on the **right**
///   only when there is text to send (or while streaming, in which
///   case it switches to a red ⏹). The circle mirrors the iOS
///   "send button" the user asked for previously, but is now compact
///   and integrated into the pill rather than being a separate row
///   control.
/// - The whole pill is `~30pt` tall with a 14pt corner radius and
///   `.thinMaterial` background, matching the iMessage reply field
///   on watchOS.
///
/// Tapping **anywhere** on the pill focuses the TextField, so even if
/// the programmatic auto-focus on "New chat" doesn't pop the
/// keyboard, a single tap on the reply bar is enough.
struct ComposerView: View {
    @Binding var text: String
    let isStreaming: Bool
    let canSend: Bool
    let onSend: () -> Void
    /// Focus binding from the parent so the watchOS keyboard can be
    /// raised automatically when the user lands in a chat (e.g. via
    /// "New chat"). The parent sets the focus to `.reply` from its
    /// `.onAppear` after a short delay.
    var focusBinding: FocusState<ComposerField?>.Binding

    /// Renders the send / stop action as a solid filled circle so
    /// it reads as a clear "circle button on the side" — the pattern
    /// the user asked for. Stops use red, the regular send uses
    /// accent. The circle is always exactly 20×20pt so the row
    /// height is stable.
    private var sendCircle: some View {
        Button {
            composerLog.info("sendCircle tapped (canSend=\(self.canSend, privacy: .public), isStreaming=\(self.isStreaming, privacy: .public))")
            onSend()
        } label: {
            Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(sendCircleColor))
        }
        .buttonStyle(.plain)
        .disabled(!isStreaming && !canSend)
    }

    /// Dictation / stop glyph on the left of the pill. Tapping it
    /// either focuses the TextField (and raises the watchOS dictation
    /// UI) or, if a stream is in flight, calls `onSend` to cancel it.
    private var micGlyph: some View {
        Button {
            if isStreaming {
                onSend()
            } else {
                focusBinding.wrappedValue = .reply
            }
        } label: {
            Image(systemName: isStreaming ? "stop.fill" : "mic.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isStreaming ? .red : .secondary)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        // The HStack is forced to fill the parent's width so the
        // TextField in the middle gets a well-defined space and the
        // send circle stays inside the visible pill. Without
        // `.frame(maxWidth: .infinity)` here, the HStack's intrinsic
        // content size dominates and the send circle gets pushed
        // beyond the right edge on narrow screens.
        HStack(spacing: 4) {
            micGlyph

            TextField("Reply", text: $text)
                .font(.caption)
                .lineLimit(1)
                .disabled(isStreaming)
                .focused(focusBinding, equals: .reply)
                .frame(maxWidth: .infinity)
                .onSubmit {
                    composerLog.info("TextField onSubmit")
                    onSend()
                }
                .onAppear {
                    composerLog.info("TextField onAppear — focus is .reply? \(self.focusBinding.wrappedValue == .reply, privacy: .public)")
                }

            // Circle button only when there's something to act on:
            // a draft, or an in-flight stream to cancel. Stays
            // out of the way otherwise so the row is the minimum
            // possible height.
            if !text.isEmpty || isStreaming {
                sendCircle
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        // Tap-anywhere-to-focus backup. If programmatic focus
        // failed (which can happen on the watchOS simulator during
        // NavigationStack push), the user can tap the pill — which
        // is *user-initiated* focus and is guaranteed to work.
        .contentShape(Rectangle())
        .onTapGesture {
            if focusBinding.wrappedValue != .reply {
                composerLog.info("pill tap → focus")
                focusBinding.wrappedValue = .reply
            }
        }
    }

    private var sendCircleColor: Color {
        if isStreaming { return .red }
        return canSend ? .accentColor : .secondary
    }
}
