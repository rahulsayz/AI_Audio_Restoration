import SwiftUI
import UniformTypeIdentifiers

public struct RestorationView: View {
    @ObservedObject var viewModel: RestorationViewModel
    @State private var isDragging: Bool = false
    
    public init(viewModel: RestorationViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ZStack {
            // Elegant ambient organic soundwave background
            SoundwaveBackground()
            
            VStack(spacing: 24) {
                // Header Brand Section
                headerSection
                
                // Content Card Area
                mainContentSection
                
                // Active Operations / Progress / Action Button Section
                actionsSection
                
                // Custom User-Facing Error Notification Banner
                if let errorMessage = viewModel.errorMessage {
                    errorBanner(message: errorMessage)
                }
            }
            .padding(40)
            .frame(width: 800, height: 600)
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Subviews
    
    private var headerSection: some View {
        VStack(spacing: 6) {
            Text("SANGEET AI")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .tracking(6)
                .foregroundStyle(
                    LinearGradient(
                        colors: [RestorationTheme.saffron, .white],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            
            Text("Preserving the timbral signatures of Indian music")
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundStyle(RestorationTheme.subtleText)
        }
    }
    
    private var mainContentSection: some View {
        Group {
            if viewModel.loadedFileURL == nil {
                dropZoneArea
            } else {
                fileDetailsCard
            }
        }
    }
    
    private var dropZoneArea: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(isDragging ? RestorationTheme.neonTeal : RestorationTheme.saffron)
                .animation(.easeInOut(duration: 0.3), value: isDragging)
            
            VStack(spacing: 8) {
                Text("Drop your old recording here")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("Supports WAV, FLAC, MP3, and M4A formats")
                    .font(.system(size: 12))
                    .foregroundStyle(RestorationTheme.subtleText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isDragging ? RestorationTheme.neonTeal.opacity(0.04) : Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isDragging ? RestorationTheme.neonTeal : RestorationTheme.glassBorder,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [8, 6])
                )
        )
        .breathingGlow(isActive: isDragging, color: RestorationTheme.neonTeal)
        .animation(.easeInOut(duration: 0.25), value: isDragging)
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    Task { @MainActor in
                        viewModel.loadFile(url: url)
                    }
                }
            }
            return true
        }
    }
    
    private var fileDetailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Image(systemName: "doc.richtext.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(RestorationTheme.saffron)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.filename)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text("Audio File Ready")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(RestorationTheme.neonTeal)
                }
                
                Spacer()
                
                Button(action: { viewModel.clearFile() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Remove file")
            }
            
            Divider()
                .background(RestorationTheme.glassBorder)
            
            HStack(spacing: 32) {
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .foregroundStyle(RestorationTheme.subtleText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DURATION")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(RestorationTheme.subtleText)
                        Text(viewModel.durationString)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundStyle(RestorationTheme.subtleText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SAMPLE RATE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(RestorationTheme.subtleText)
                        Text(viewModel.sampleRateString)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }
                
                Spacer()
            }
        }
        .glassCard()
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    private var actionsSection: some View {
        VStack(spacing: 16) {
            if viewModel.loadedFileURL != nil {
                if viewModel.isProcessing {
                    processingStateView
                } else if viewModel.restorationComplete {
                    completionStateView
                } else {
                    idleStateView
                }
            } else {
                Text("Select or drop a degraded audio file above to begin")
                    .font(.system(size: 12))
                    .foregroundStyle(RestorationTheme.subtleText)
            }
        }
        .frame(height: 100)
    }
    
    private var idleStateView: some View {
        Button(action: {
            withAnimation {
                viewModel.startRestoration()
            }
        }) {
            Text("Restore Audio")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black)
                .frame(width: 200, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(RestorationTheme.saffron)
                )
                .shadow(color: RestorationTheme.saffron.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
    
    private var processingStateView: some View {
        VStack(spacing: 12) {
            HStack {
                Text(viewModel.currentStage)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(RestorationTheme.neonTeal)
                
                Spacer()
                
                Text(String(format: "%.0f%%", viewModel.progress * 100.0))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .frame(width: 450)
            
            // Neon glowing progress bar
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 8)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [RestorationTheme.neonTeal, Color.blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 450 * CGFloat(viewModel.progress), height: 8)
                    .shadow(color: RestorationTheme.neonTeal.opacity(0.5), radius: 4, x: 0, y: 0)
            }
            .frame(width: 450)
            
            Button(action: { viewModel.cancelRestoration() }) {
                Text("Cancel")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
    }
    
    private var completionStateView: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(RestorationTheme.neonTeal)
                
                Text("Restoration successfully completed!")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
            }
            
            Button(action: { viewModel.showInFinder() }) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                    Text("Show in Finder")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(RestorationTheme.neonTeal)
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Restoration Issue")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.12))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - SwiftUI Previews

#Preview("Empty State") {
    let mockVM = RestorationViewModel()
    return RestorationView(viewModel: mockVM)
}

#Preview("Loaded State") {
    let mockVM = RestorationViewModel()
    mockVM.loadFile(url: URL(fileURLWithPath: "/Users/mock/Downloads/lata_mangeshkar_1952.mp3"))
    return RestorationView(viewModel: mockVM)
}

#Preview("Processing State") {
    let mockVM = RestorationViewModel()
    mockVM.loadFile(url: URL(fileURLWithPath: "/Users/mock/Downloads/lata_mangeshkar_1952.mp3"))
    // Direct state injection for previewing processing
    let vm = mockVM
    Task { @MainActor in
        // Set processing values on preview viewModel
        vm.startRestoration()
    }
    return RestorationView(viewModel: mockVM)
}
