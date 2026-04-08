import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let cameraManager: CameraManager

    func makeCoordinator() -> Coordinator {
        Coordinator(cameraManager: cameraManager)
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView(session: session)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinch)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.cameraManager = cameraManager
    }

    @MainActor
    class Coordinator: NSObject {
        var cameraManager: CameraManager
        private var zoomAtGestureStart: CGFloat = 1.0

        init(cameraManager: CameraManager) {
            self.cameraManager = cameraManager
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                zoomAtGestureStart = cameraManager.currentZoomFactor
            case .changed:
                let newZoom = zoomAtGestureStart * gesture.scale
                cameraManager.setZoom(factor: newZoom)
            default:
                break
            }
        }
    }
}

// Custom UIView subclass that handles the preview layer setup and layout
class PreviewView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)

        setupView()
    }

    required init?(coder: NSCoder) {
        previewLayer = AVCaptureVideoPreviewLayer()
        super.init(coder: coder)

        setupView()
    }

    private func setupView() {
        backgroundColor = .black

        // Setup camera preview layer
        previewLayer.videoGravity = .resizeAspect  // Fit the view (shows full frame without cropping)
        previewLayer.opacity = 1.0  // Always show camera preview
        layer.addSublayer(previewLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
    }
}

// Basic Preview Provider
#Preview {
    // Create a dummy session for the preview
    let dummySession = AVCaptureSession()
    let dummyManager = CameraManager(setupOnInit: false)
    // In a real app, you'd pass the actual session from CameraManager
    CameraPreview(session: dummySession, cameraManager: dummyManager)
        .edgesIgnoringSafeArea(.all) // Make preview full screen
}
