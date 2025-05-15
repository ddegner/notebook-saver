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
    private let placeholderLayer = CAGradientLayer()
    
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
        previewLayer.opacity = 0  // Start invisible until camera is ready
        layer.addSublayer(previewLayer)
        
        // Setup placeholder gradient (subtle dark gradient that looks like camera UI)
        placeholderLayer.colors = [
            UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0).cgColor,
            UIColor.black.cgColor
        ]
        placeholderLayer.locations = [0.0, 1.0]
        placeholderLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        placeholderLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        layer.addSublayer(placeholderLayer)
        
        // Initial visibility state
        updateLayerVisibility(animated: false)
    }
    
    private func updateLayerVisibility(animated: Bool) {
        if animated {
            let duration: CFTimeInterval = 0.3
            
            let previewAnimation = CABasicAnimation(keyPath: "opacity")
            previewAnimation.fromValue = previewLayer.opacity
            previewAnimation.toValue = isSessionReady ? 1.0 : 0.0
            previewAnimation.duration = duration
            previewLayer.add(previewAnimation, forKey: "opacity")
            
            let placeholderAnimation = CABasicAnimation(keyPath: "opacity")
            placeholderAnimation.fromValue = placeholderLayer.opacity
            placeholderAnimation.toValue = isSessionReady ? 0.0 : 1.0
            placeholderAnimation.duration = duration
            placeholderLayer.add(placeholderAnimation, forKey: "opacity")
        }
        
        // Update final values
        previewLayer.opacity = isSessionReady ? 1.0 : 0.0
        placeholderLayer.opacity = isSessionReady ? 0.0 : 1.0
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        placeholderLayer.frame = bounds
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