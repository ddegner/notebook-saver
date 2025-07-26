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
        // No dynamic properties needed for this basic activity
    }

    // No fixed properties needed for this basic activity
}

struct NotebookSaverWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NotebookSaverWidgetsAttributes.self) { context in
            // Lock screen/banner UI
            VStack {
                Text("Cat Scribe Active")
            }
            .activityBackgroundTint(Color("WidgetBackground"))
            .activitySystemActionForegroundColor(Color.primary)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    // Example: Leading icon or info
                    // Image(systemName: "timer")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // Example: Trailing status or info
                    // Text("Status")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Cat Scribe is active") // App-specific and non-placeholder
                    // Optionally add more content like a button to open the app
                    // Button("Open App") { /* Intent to open app */ }
                }
            } compactLeading: {
                Image(systemName: "cat.fill") // App icon
            } compactTrailing: {
                Text("Active") // Concise status
            } minimal: {
                Image(systemName: "cat.fill") // App icon, non-placeholder
            }
            // No widgetURL or keylineTint needed for this basic configuration
        }
    }
}

extension NotebookSaverWidgetsAttributes {
    fileprivate static var preview: NotebookSaverWidgetsAttributes {
        NotebookSaverWidgetsAttributes() // Updated preview
    }
}

extension NotebookSaverWidgetsAttributes.ContentState {
    fileprivate static var smiley: NotebookSaverWidgetsAttributes.ContentState {
        NotebookSaverWidgetsAttributes.ContentState() // Updated preview
     }

     fileprivate static var starEyes: NotebookSaverWidgetsAttributes.ContentState {
         NotebookSaverWidgetsAttributes.ContentState() // Updated preview
     }
}

#Preview("Notification", as: .content, using: NotebookSaverWidgetsAttributes.preview) {
   NotebookSaverWidgetsLiveActivity()
} contentStates: {
    NotebookSaverWidgetsAttributes.ContentState.smiley
    NotebookSaverWidgetsAttributes.ContentState.starEyes
}
