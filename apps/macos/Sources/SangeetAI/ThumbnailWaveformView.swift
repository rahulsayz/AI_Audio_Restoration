import SwiftUI

public struct ThumbnailWaveformView: View {
    let amplitudes: [Float]
    let color: Color
    
    public init(amplitudes: [Float], color: Color = RestorationTheme.saffron) {
        self.amplitudes = amplitudes
        self.color = color
    }
    
    public var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<amplitudes.count, id: \.self) { index in
                let val = CGFloat(amplitudes[index])
                // Render a neat vertical bar of minimum height 2 and scaled max height 24
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.85), color.opacity(0.3)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2, height: max(3, val * 24))
            }
        }
        .frame(height: 24)
    }
}
