import SwiftUI
import UniformTypeIdentifiers

/// Lightweight share extension view.
/// Saves the shared image to the App Group container, shows a brief
/// confirmation, then calls `onSaved` so ShareViewController can open
/// Cat Scribe and dismiss the extension with no blocking wait.
struct ShareView: View {
    let extensionContext: NSExtensionContext?
    var onSaved: (() -> Void)?

    @State private var phase: Phase = .loading

    private enum Phase: Equatable { case loading, saved, failed(String) }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            switch phase {
            case .loading:
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.4)
                    Text("Saving to Cat Scribe…")
                        .foregroundStyle(.secondary)
                }
            case .saved:
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("Opening Cat Scribe…")
                        .foregroundStyle(.secondary)
                }
                .transition(.scale.combined(with: .opacity))
            case .failed(let message):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    Button("Cancel") {
                        extensionContext?.cancelRequest(withError: ShareError.noImage)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: phase == .saved)
        .task { await launch() }
    }

    // MARK: - Launch

    private func launch() async {
        do {
            let image = try await loadImage()
            try saveToAppGroup(image)
            withAnimation { phase = .saved }
            // Brief pause so the checkmark is visible, then hand off to ShareViewController
            try? await Task.sleep(for: .milliseconds(450))
            onSaved?()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Load image from extension context

    /// Loads the first image attachment from the extension context.
    /// Stays on @MainActor so NSItemProvider (non-Sendable) never crosses
    /// an isolation boundary (SE-0420 / Swift 6).
    private func loadImage() async throws -> UIImage {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = extensionItem.attachments, !providers.isEmpty else {
            throw ShareError.noImage
        }

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { continue }
            let typeIdentifier = UTType.image.identifier
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                _ = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: ShareError.invalidImageData)
                    }
                }
            }
            guard let uiImage = UIImage(data: data) else { throw ShareError.invalidImageData }
            return uiImage
        }

        throw ShareError.noImage
    }

    // MARK: - Save to App Group

    private func saveToAppGroup(_ image: UIImage) throws {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedDefaults.appGroupId
        ) else {
            throw ShareError.appGroupUnavailable
        }

        let destination = container.appendingPathComponent("pendingSharedImage.jpg")
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            throw ShareError.invalidImageData
        }
        try data.write(to: destination, options: .atomic)
        SharedDefaults.suite.set(destination.path, forKey: "pendingSharedImagePath")
        SharedDefaults.suite.synchronize()
    }
}

// MARK: - Errors

private enum ShareError: LocalizedError {
    case noImage
    case invalidImageData
    case appGroupUnavailable

    var errorDescription: String? {
        switch self {
        case .noImage:
            return "No image was found in the shared content."
        case .invalidImageData:
            return "The shared image could not be read."
        case .appGroupUnavailable:
            return "Could not access the shared app container."
        }
    }
}
