import SwiftUI
import UniformTypeIdentifiers

struct ShareView: View {
    let imageData: Data
    @State private var extractedText: String = ""
    @State private var isProcessing = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isProcessing {
                ProgressView("Processing…")
            } else if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else {
                ScrollView {
                    Text(extractedText).textSelection(.enabled)
                }
                HStack {
                    Button("Copy") {
                        UIPasteboard.general.string = extractedText
                    }
                    Spacer()
                    ShareLink(item: extractedText) {
                        Text("Share")
                    }
                }
            }
        }
        .padding()
        .task {
            await process()
        }
    }

    private func process() async {
        defer { isProcessing = false }
        guard let image = UIImage(data: imageData) else {
            errorMessage = "Invalid image data"
            return
        }
        do {
            let text = try await NotebookSaverPipeline.processImage(image)
            extractedText = text
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}