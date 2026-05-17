import SwiftUI

struct SpectrumVisualizerView: View {
    let spectrum: [Float]
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            // Spectrum Title / Label
            HStack {
                Text("REAL-TIME FFT FREQUENCY SPECTRUM")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(2.5)
                    .foregroundStyle(Color.gray.opacity(0.8))
                Spacer()
                Text("20 Hz — 20 kHz (Log)")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.gray.opacity(0.5))
            }
            .padding(.horizontal, 4)
            
            // Bars Container
            HStack(alignment: .bottom, spacing: 3) {
                Spacer()
                ForEach(0..<spectrum.count, id: \.self) { index in
                    let val = CGFloat(spectrum[index])
                    
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.4)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 4, height: max(3, val * 52))
                        .shadow(color: color.opacity(val * 0.4), radius: 2)
                }
                Spacer()
            }
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.04), lineWidth: 1)
                    )
            )
        }
    }
}
