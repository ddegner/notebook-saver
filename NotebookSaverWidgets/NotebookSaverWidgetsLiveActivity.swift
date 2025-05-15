//
//  NotebookSaverWidgetsLiveActivity.swift
//  NotebookSaverWidgets
//
//  Created by David Degner on 5/2/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct NotebookSaverWidgetsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct NotebookSaverWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NotebookSaverWidgetsAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension NotebookSaverWidgetsAttributes {
    fileprivate static var preview: NotebookSaverWidgetsAttributes {
        NotebookSaverWidgetsAttributes(name: "World")
    }
}

extension NotebookSaverWidgetsAttributes.ContentState {
    fileprivate static var smiley: NotebookSaverWidgetsAttributes.ContentState {
        NotebookSaverWidgetsAttributes.ContentState(emoji: "😀")
     }

     fileprivate static var starEyes: NotebookSaverWidgetsAttributes.ContentState {
         NotebookSaverWidgetsAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: NotebookSaverWidgetsAttributes.preview) {
   NotebookSaverWidgetsLiveActivity()
} contentStates: {
    NotebookSaverWidgetsAttributes.ContentState.smiley
    NotebookSaverWidgetsAttributes.ContentState.starEyes
}
