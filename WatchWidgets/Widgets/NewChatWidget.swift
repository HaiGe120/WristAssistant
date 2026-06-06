import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget

struct NewChatWidget: Widget {
    let kind: String = "NewChatWidget"

    static var supportedFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline,
        ]
        #if os(watchOS)
        families.append(.accessoryCorner)
        #endif
        return families
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NewChatProvider()) { entry in
            NewChatEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("New Chat")
        .description("Start a new conversation with one tap from your watch face or Smart Stack.")
        .supportedFamilies(Self.supportedFamilies)
    }
}

// MARK: - Timeline

struct NewChatEntry: TimelineEntry {
    let date: Date
}

struct NewChatProvider: TimelineProvider {
    typealias Entry = NewChatEntry

    func placeholder(in context: Context) -> NewChatEntry { NewChatEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (NewChatEntry) -> Void) {
        completion(NewChatEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NewChatEntry>) -> Void) {
        let timeline = Timeline(entries: [NewChatEntry(date: .now)], policy: .never)
        completion(timeline)
    }
}

// MARK: - View

struct NewChatEntryView: View {
    let entry: NewChatEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        // Link wraps the whole view so a single tap on the complication /
        // Smart Stack tile routes to wristassistant://new-chat, which the
        // watch app handles via onOpenURL and shows the new-chat sheet.
        Link(destination: URL(string: "wristassistant://new-chat")!) {
            switch family {
            case .accessoryRectangular: rectangular
            case .accessoryCircular:     circular
            case .accessoryInline:       inline
            case .accessoryCorner:       corner
            default:                     rectangular
            }
        }
    }

    private var rectangular: some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.purple.opacity(0.25))
                Image(systemName: "plus.bubble.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.purple)
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text("New Chat")
                    .font(.headline)
                    .lineLimit(1)
                Text("Wrist Assistant")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var circular: some View {
        ZStack {
            Circle().strokeBorder(lineWidth: 1.5)
            Image(systemName: "plus.bubble.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.purple)
        }
    }

    private var inline: some View {
        Label("New Chat", systemImage: "plus.bubble.fill")
    }

    private var corner: some View {
        Image(systemName: "plus.bubble.fill")
            .font(.system(size: 14, weight: .semibold))
            .widgetAccentable()
    }
}
