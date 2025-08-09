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

                        // Determine if we should toggle settings based purely on drag distance and direction
                        let shouldToggle: Bool

                        if abs(value.translation.height) > dragThreshold {
                            if value.translation.height < 0 && !isShowingSettings {
                                shouldToggle = true
                            } else if value.translation.height > 0 && isShowingSettings {
                                shouldToggle = true
                            } else {
                                shouldToggle = false
                            }
                        } else {
                            shouldToggle = false
                        }

                        if shouldToggle {
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
        .ignoresSafeArea()
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
