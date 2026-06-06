//  ComposerView.swift
//  Simple inline reply box. A regular SwiftUI TextField with a
//  send button next to it, all in a single HStack at the bottom of
//  the chat. No floating pill, no auto-hide, no scroll sentinel —
//  the basic shape that worked before the iMessage redesign.

import SwiftUI
import os.log

private let composerLog = Logger(subsystem: "com.wristassistant.app.watchkitapp", category: "ComposerView")

struct ComposerView: View {
    @Binding var text: String
    let isStreaming: Bool
    let canSend: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Reply", text: $text)
                .font(.caption)
                .lineLimit(1)
                .disabled(isStreaming)
                .onSubmit { onSend() }

            Button {
                composerLog.info("send tapped (canSend=\(self.canSend, privacy: .public), isStreaming=\(self.isStreaming, privacy: .public))")
                onSend()
            } label: {
                Image(systemName: isStreaming ? "stop.fill" : "paperplane.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.white)
                    .background(isStreaming ? Color.red : (canSend ? Color.accentColor : Color.gray))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isStreaming && !canSend)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.15))
    }
}
