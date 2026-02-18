import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView(session: session)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // No updates needed
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
    // In a real app, you'd pass the actual session from CameraManager
    CameraPreview(session: dummySession)
        .edgesIgnoringSafeArea(.all) // Make preview full screen
}