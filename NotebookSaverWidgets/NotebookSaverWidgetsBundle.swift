import WidgetKit
import SwiftUI

@main
struct NotebookSaverWidgetsBundle: WidgetBundle {
    var body: some Widget {
        OpenAppWidget() // Register our quick open widget
        // You can add other widgets here later if needed
    }
}
