import WidgetKit
import SwiftUI

// 1. Define the Timeline Entry (Minimal)
// Represents a moment in time for the widget's state.
struct SimpleEntry: TimelineEntry {
    let date: Date // Only date is needed for this static widget
}

// 2. Define the Timeline Provider (Minimal)
// Provides timeline entries to WidgetKit.
struct Provider: TimelineProvider {
    // Provides a placeholder view for the widget gallery.
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    // Provides a snapshot for transient situations (like the gallery).
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date())
        completion(entry)
    }

    // Provides the actual timeline for the widget.
    // For a static widget like this, we provide one entry that never expires.
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entry = SimpleEntry(date: Date())
        // Policy .never means WidgetKit won't ask for updates unless forced.
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

// 3. Define the Widget View
// This is the SwiftUI view displayed on the Lock Screen.
struct OpenAppWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    // Define the URL to open when the widget is tapped.
    private var appURL: URL? {
        URL(string: "notebooksaver://")
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                // For inline widget under the clock
                ViewThatFits {
                    // Try icon and text first
                    HStack(spacing: 4) {
                        Image(systemName: "cat.fill")
                            .font(.body)
                            .widgetAccentable()
                        Text("Capture")
                            .widgetAccentable()
                    }
                    // Fallback to just the icon
                    Image(systemName: "cat.fill")
                        .font(.headline)
                        .widgetAccentable()
                }

            case .accessoryCircular:
                // For circular widget on lock screen
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "cat.fill")
                        .font(.system(size: 30))
                        .widgetAccentable()
                }

            case .accessoryRectangular:
                // For rectangular widget on lock screen
                ZStack {
                    AccessoryWidgetBackground()
                    VStack {
                        HStack {
                            Image(systemName: "cat.fill")
                                .font(.body)
                            Text("Capture Note")
                                .font(.headline)
                        }
                    }
                    .padding(.horizontal, 4)
                }

            case .systemSmall:
                // Home screen small widget
                VStack {
                    Image(systemName: "cat.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                        .padding(.bottom, 4)

                    Text("Capture Note")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()

            case .systemMedium:
                // Home screen medium widget
                VStack {
                    Image(systemName: "cat.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                        .padding(.bottom, 5)

                    Text("Capture Note")
                        .font(.headline)
                        .padding(.bottom, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()

            default:
                Text("Unsupported widget family")
            }
        }
        .widgetURL(appURL)
    }
}

// 4. Define the Widget Configuration
struct OpenAppWidget: Widget {
    let kind: String = "OpenNotebookSaverWidget" // Unique identifier for this widget

    var body: some WidgetConfiguration {
        // StaticConfiguration is used when the widget doesn't need user configuration.
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            OpenAppWidgetEntryView(entry: entry)
                .widgetBackground(Color.clear) // Essential for Lock Screen transparency
        }
        .configurationDisplayName("Capture Note") // Changed text
        .description("Quickly open the Cat Scribe app.") // Description shown in the gallery
        // Lock screen widgets plus systemSmall and systemMedium to fix preview error
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
            .systemSmall,
            .systemMedium
        ])
    }
}

// 5. Preview Provider (Optional but helpful)
#Preview(as: .accessoryInline) {
    OpenAppWidget()
} timeline: {
    SimpleEntry(date: .now)
}

#Preview(as: .accessoryCircular) {
    OpenAppWidget()
} timeline: {
    SimpleEntry(date: .now)
}

#Preview(as: .accessoryRectangular) {
    OpenAppWidget()
} timeline: {
    SimpleEntry(date: .now)
}

#Preview(as: .systemSmall) {
    OpenAppWidget()
} timeline: {
    SimpleEntry(date: .now)
}

#Preview(as: .systemMedium) {
    OpenAppWidget()
} timeline: {
    SimpleEntry(date: .now)
}

// 6. Helper extension for widget background (handles API changes)
extension View {
    func widgetBackground(_ backgroundView: some View) -> some View {
        if #available(iOS 17.0, *) {
            // iOS 17+ way to set widget background
            return containerBackground(for: .widget) {
                backgroundView
            }
        } else {
            // Fallback for older iOS versions
            return background(backgroundView)
        }
    }
}
