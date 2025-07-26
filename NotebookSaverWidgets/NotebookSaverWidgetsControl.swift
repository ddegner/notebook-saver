//
//  NotebookSaverWidgetsControl.swift
//  NotebookSaverWidgets
//
//  Created by David Degner on 5/2/25.
//

import AppIntents
import SwiftUI
import WidgetKit

// Intent to open the main application
struct OpenCatScribeIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Cat Scribe"
    static var openAppWhenRun: Bool = true // Indicates the app should open

    func perform() async throws -> some IntentResult {
        // The system handles opening the app when openAppWhenRun is true.
        return .result()
    }
}

struct NotebookSaverWidgetsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.daviddegner.NotebookSaver.OpenCatScribeControlWidget", // Updated kind
            provider: Provider()
        ) { _ in // The value from the provider is not used by the button
            ControlWidgetButton(action: OpenCatScribeIntent()) {
                Label("Open Cat Scribe", systemImage: "cat.fill") // Using app-relevant icon
            }
        }
        .displayName("Open Cat Scribe") // Updated display name
        .description("Quickly open the Cat Scribe app.") // Updated description
    }
}

extension NotebookSaverWidgetsControl {
    // Provider now returns a static value as the button does not consume dynamic state.
    struct Provider: ControlValueProvider {
        var previewValue: Bool {
            false // Static preview value
        }

        func currentValue() async throws -> Bool {
            // This value is not directly used by the ControlWidgetButton's appearance
            // but is required by StaticControlConfiguration.
            return false 
        }
    }
}
