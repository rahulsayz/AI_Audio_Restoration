import SwiftUI

struct StackedWaveformView: View {
    let originalAmplitudes: [Float]
    let restoredAmplitudes: [Float]
    let progress: Double
    let isOriginalActive: Bool
    let restoredColor: Color
    let onSeek: (Double) -> Void
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Stacked Waveforms Container
                VStack(spacing: 8) {
                    // Original (Top)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
                            )
                        
                        HStack(spacing: 4) {
                            Text("ORIGINAL")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.gray.opacity(isOriginalActive ? 0.8 : 0.4))
                                .padding(.leading, 8)
                            Spacer()
                        }
                        
                        waveformBars(amplitudes: originalAmplitudes, color: Color.gray, height: 44, active: isOriginalActive)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: 44)
                    
                    // Restored (Bottom)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
                            )
                        
                        HStack(spacing: 4) {
                            Text("RESTORED")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(restoredColor.opacity(!isOriginalActive ? 0.8 : 0.4))
                                .padding(.leading, 8)
                            Spacer()
                        }
                        
                        waveformBars(amplitudes: restoredAmplitudes, color: restoredColor, height: 44, active: !isOriginalActive)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: 44)
                }
                
                // Synchronized Vertical Playhead Line
                Rectangle()
                    .fill(LinearGradient(
                        colors: [RestorationTheme.saffron, Color.orange],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .offset(x: geo.size.width * CGFloat(progress))
                    .shadow(color: RestorationTheme.saffron.opacity(0.8), radius: 4)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let seekTarget = Double(max(0, min(value.location.x / geo.size.width, 1)))
                        onSeek(seekTarget)
                    }
            )
        }
        .frame(height: 96)
    }
    
    private func waveformBars(amplitudes: [Float], color: Color, height: CGFloat, active: Bool) -> some View {
        HStack(spacing: 2) {
            Spacer()
            ForEach(0..<amplitudes.count, id: \.self) { index in
                let val = CGFloat(amplitudes[index])
                let opacity = active ? 0.85 : 0.2
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(opacity), color.opacity(opacity * 0.4)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: max(4, val * (height - 12)))
            }
            Spacer()
        }
    }
}
