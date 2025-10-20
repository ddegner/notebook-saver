import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var isSessionReady: Bool = false // Track if camera session is running
    var onPinchZoom: ((CGFloat) -> Void)? = nil // Callback for zoom gestures

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView(session: session)
        view.isSessionReady = isSessionReady
        view.onPinchZoom = onPinchZoom
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Update session ready state
        uiView.isSessionReady = isSessionReady
        uiView.onPinchZoom = onPinchZoom
    }
}

// Custom UIView subclass that handles the preview layer setup and layout
class PreviewView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer
    private var pinchGesture: UIPinchGestureRecognizer?
    
    var isSessionReady: Bool = false {
        didSet {
            // Only animate if value changed
            if oldValue != isSessionReady {
                updateLayerVisibility(animated: true)
            }
        }
    }
    
    var onPinchZoom: ((CGFloat) -> Void)? {
        didSet {
            setupPinchGesture()
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
        
        // Setup pinch gesture
        setupPinchGesture()
    }
    
    private func setupPinchGesture() {
        // Remove existing gesture if any
        if let existing = pinchGesture {
            removeGestureRecognizer(existing)
        }
        
        // Add new gesture if callback is set
        if onPinchZoom != nil {
            let gesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            addGestureRecognizer(gesture)
            pinchGesture = gesture
        }
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let onPinchZoom = onPinchZoom else { return }
        
        if gesture.state == .changed {
            onPinchZoom(gesture.scale)
            gesture.scale = 1.0 // Reset for next change
        } else if gesture.state == .began {
            // Light haptic feedback on zoom start
            let feedback = UIImpactFeedbackGenerator(style: .light)
            feedback.impactOccurred(intensity: 0.5)
        }
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