import SwiftUI
import AVFoundation // For AudioServicesPlaySystemSound

struct ContentView: View {
    @State private var isShowingSettings = false
    @State private var cameraOffset: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Settings View - stays in place as background
                SettingsView()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color.white)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 16,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 16
                        )
                    )
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
                    .padding(.top, 80) // Add padding so tabs are visible when camera slides up
                
                // Camera View - slides up and down
                CameraView(isShowingSettings: $isShowingSettings)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .offset(y: cameraOffset + dragOffset)
                    .shadow(color: .black.opacity(0.30), radius: 12, x: 0, y: 6)
            }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        let translation = value.translation.height
                        
                        // Only allow dragging in the correct direction with limited range
                        if !isShowingSettings && translation < 0 {
                            // In camera view, only allow upward drag (negative translation)
                            // Limit the drag to prevent going beyond the target position
                            let maxUpwardDrag = -(geometry.size.height - 80)
                            dragOffset = max(translation, maxUpwardDrag)
                        } else if isShowingSettings && translation > 0 {
                            // In settings view, only allow downward drag (positive translation)
                            // Limit the drag to prevent going beyond the original position
                            let maxDownwardDrag = geometry.size.height - 80
                            dragOffset = min(translation, maxDownwardDrag)
                        } else {
                            // No movement in wrong direction
                            dragOffset = 0
                        }
                    }
                    .onEnded { value in
                        let dragThreshold: CGFloat = 80
                        let velocityThreshold: CGFloat = 800
                        
                        // Use the actual drag gesture velocity
                        let velocity = value.velocity.height
                        
                        // Determine if we should toggle settings based on drag distance and velocity
                        let shouldToggle: Bool
                        
                        if abs(value.translation.height) > dragThreshold {
                            // If drag distance is significant, use direction to determine toggle
                            if value.translation.height < 0 && !isShowingSettings {
                                // Swipe up when in camera view -> show settings
                                shouldToggle = true
                            } else if value.translation.height > 0 && isShowingSettings {
                                // Swipe down when in settings view -> show camera
                                shouldToggle = true
                            } else {
                                shouldToggle = false
                            }
                        } else if abs(velocity) > velocityThreshold {
                            // If velocity is high, use velocity direction
                            if velocity < 0 && !isShowingSettings {
                                // Fast swipe up when in camera view -> show settings
                                shouldToggle = true
                            } else if velocity > 0 && isShowingSettings {
                                // Fast swipe down when in settings view -> show camera
                                shouldToggle = true
                            } else {
                                shouldToggle = false
                            }
                        } else {
                            shouldToggle = false
                        }
                        
                        if shouldToggle {
                            // Toggle the settings state
                            isShowingSettings.toggle()
                        }
                        
                        // Always snap back to the discrete position
                        withAnimation(.easeInOut(duration: 0.1)) {
                            dragOffset = 0
                        }
                    }
            )
            .onAppear {
                // Initialize camera offset - camera starts at full screen (0), slides up to show settings
                cameraOffset = isShowingSettings ? -geometry.size.height + 80 : 0
            }
            .onChange(of: isShowingSettings) { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    // When showing settings, slide camera up so only the chevron (bottom 80pts) is visible
                    cameraOffset = newValue ? -geometry.size.height + 80 : 0
                    // Reset dragOffset as part of the same animation
                    dragOffset = 0
                }
                
                // Faster haptic feedback and sound - reduced delay for quicker response
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    // Lighter haptic feedback when camera stops moving
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred(intensity: 0.7)
                    
                    // Play softer click sound when camera reaches its final position
                    playPositionClickSound()
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
    
    // MARK: - Sound Functions
    private func playPositionClickSound() {
        // Play a softer click sound when camera reaches top or bottom position
        // Using system sound 1104 (softer, more click-like sound)
        AudioServicesPlaySystemSound(1104)
    }
}

#Preview {
    ContentView()
}
