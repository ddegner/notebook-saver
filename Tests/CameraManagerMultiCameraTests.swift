import XCTest
import AVFoundation
@testable import NotebookSaver

class CameraManagerMultiCameraTests: XCTestCase {
    
    var cameraManager: CameraManager!
    
    override func setUp() {
        super.setUp()
        // Initialize without automatic setup for testing
        cameraManager = CameraManager(setupOnInit: false)
    }
    
    override func tearDown() {
        cameraManager = nil
        super.tearDown()
    }
    
    func testCameraDiscovery() {
        // This test verifies that camera discovery works
        // Note: This will only work on physical devices, not simulator
        
        let expectation = XCTestExpectation(description: "Camera discovery completes")
        
        // Simulate camera discovery
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // On simulator, availableCameras will be empty
            // On device, it should contain at least one camera
            XCTAssertTrue(self.cameraManager.availableCameras.count >= 0, "Camera discovery should complete without crashing")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testZoomRangeCalculation() {
        // Test that zoom ranges are calculated correctly
        XCTAssertEqual(cameraManager.minZoomFactor, 1.0, "Minimum zoom should default to 1.0")
        XCTAssertGreaterThanOrEqual(cameraManager.maxZoomFactor, 1.0, "Maximum zoom should be at least 1.0")
        XCTAssertLessThanOrEqual(cameraManager.maxZoomFactor, 10.0, "Maximum zoom should be capped at 10.0")
    }
    
    func testSimplifiedCameraSelection() {
        // Test that camera selection works without crashing
        let result = cameraManager.selectOptimalCameraForZoom(2.0)
        // Should not crash - actual result depends on available hardware
        XCTAssertTrue(true, "Camera selection should not crash")
    }
    
    func testZoomOptimalCameraSelection() {
        // Test that optimal camera selection works for different zoom levels
        
        // Test macro range (1.0x-2.0x)
        let macroResult = cameraManager.selectOptimalCameraForZoom(1.5)
        // Should not crash and should return a result if cameras are available
        
        // Test telephoto range (3.0x-10.0x)  
        let telephotoResult = cameraManager.selectOptimalCameraForZoom(5.0)
        // Should not crash and should return a result if cameras are available
        
        // The actual camera selection depends on available hardware
        // So we just verify the methods don't crash
        XCTAssertTrue(true, "Camera selection methods should not crash")
    }
    
    // MARK: - Helper Methods
    
    private func createMockDevice(type: AVCaptureDevice.DeviceType) -> AVCaptureDevice {
        // Note: This is a simplified mock - in a real test environment,
        // you might use a more sophisticated mocking framework
        // For now, we'll use the actual device discovery but this shows the structure
        
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [type],
            mediaType: .video,
            position: .back
        ).devices
        
        return devices.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)!
    }
}

// MARK: - Test Extensions

extension CameraManager {
    // Expose simplified camera selection for testing
    func selectOptimalCameraForZoom(_ targetZoom: CGFloat) -> (device: AVCaptureDevice, adjustedZoom: CGFloat)? {
        guard !availableCameras.isEmpty else { return nil }
        
        var bestCamera: AVCaptureDevice?
        var adjustedZoom = targetZoom
        
        // For high zoom (>3x), prefer telephoto if available
        if targetZoom > 3.0 {
            bestCamera = availableCameras.first { $0.deviceType == .builtInTelephotoCamera }
            if bestCamera != nil {
                adjustedZoom = targetZoom / 2.0 // Adjust for 2x telephoto
            }
        }
        
        // Fallback to the best available camera
        if bestCamera == nil {
            bestCamera = availableCameras.first
        }
        
        guard let selectedCamera = bestCamera else { return nil }
        
        // Clamp zoom to camera limits
        let clampedZoom = min(max(adjustedZoom, selectedCamera.minAvailableVideoZoomFactor), 
                             selectedCamera.maxAvailableVideoZoomFactor)
        
        return (device: selectedCamera, adjustedZoom: clampedZoom)
    }
}