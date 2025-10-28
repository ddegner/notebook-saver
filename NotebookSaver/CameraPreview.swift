import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var isSessionReady: Bool = false // Track if camera session is running

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView(session: session)
        view.isSessionReady = isSessionReady
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Update session ready state
        uiView.isSessionReady = isSessionReady
    }
}

// Custom UIView subclass that handles the preview layer setup and layout
class PreviewView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer
    
    var isSessionReady: Bool = false {
        didSet {
            // Only animate if value changed
            if oldValue != isSessionReady {
                updateLayerVisibility(animated: true)
            }
        }
    }
    
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
    
    private func updateLayerVisibility(animated: Bool) {
        // Placeholder removed – always show the preview layer
        previewLayer.opacity = 1.0
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
    CameraPreview(session: dummySession, isSessionReady: false)
        .edgesIgnoringSafeArea(.all) // Make preview full screen
}