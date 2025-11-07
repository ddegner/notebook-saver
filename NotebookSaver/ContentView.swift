import SwiftUI
import AVFoundation // For AudioServicesPlaySystemSound

struct ContentView: View {
    @State private var isShowingSettings = false
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
                    .offset(y: (isShowingSettings ? -(geometry.size.height - 80) : 0) + dragOffset)
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

                        // Animate the state changes together
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if shouldToggle {
                                isShowingSettings.toggle()
                            }
                            // Always snap back to the discrete position
                            dragOffset = 0
                        }
                    }
            )
            .animation(.easeInOut(duration: 0.2), value: isShowingSettings)
            .onChange(of: isShowingSettings) { _, _ in
                // Haptic feedback and sound when animation completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    let impact = UIImpactFeedbackGenerator(style: .rigid)
                    impact.prepare()
                    impact.impactOccurred(intensity: 1.0)
                    play(.positionClick)
                }
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
