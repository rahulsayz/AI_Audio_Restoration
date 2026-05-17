import SwiftUI
import UniformTypeIdentifiers
import AudioEngine

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
        VStack(spacing: 16) {
            if viewModel.loadedFileURL == nil {
                dropZoneArea
            } else {
                fileDetailsCard
                
                analysisSection
            }
        }
    }
    
    private var analysisSection: some View {
        Group {
            if viewModel.isAnalyzing {
                // Pulse loading view
                HStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                    Text("Analyzing audio characteristics...")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(RestorationTheme.subtleText)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .glassCard()
                .transition(.opacity)
            } else if let result = viewModel.analysisResult {
                // Analysis results card
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("AUDIO ANALYSIS")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(3)
                            .foregroundStyle(RestorationTheme.saffron)
                        
                        Spacer()
                        
                        // Noise floor SNR
                        Text(String(format: "%.1f dB SNR", result.features.snrEstimateDb))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(RestorationTheme.neonTeal)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RestorationTheme.neonTeal.opacity(0.1))
                            .cornerRadius(4)
                    }
                    
                    // Badges row
                    HStack(spacing: 8) {
                        let badges = getBadges(features: result.features)
                        if badges.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundStyle(RestorationTheme.neonTeal)
                                Text("Clean Signal (No hum, clicks, or clipping)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(RestorationTheme.neonTeal)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(RestorationTheme.neonTeal.opacity(0.06))
                            .cornerRadius(6)
                        } else {
                            ForEach(badges, id: \.text) { badge in
                                HStack(spacing: 4) {
                                    Image(systemName: badge.icon)
                                    Text(badge.text)
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(badge.color)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(badge.color.opacity(0.08))
                                .cornerRadius(6)
                            }
                        }
                    }
                    
                    Divider()
                        .background(RestorationTheme.glassBorder)
                    
                    // Suggested recipe
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ROUTER RECIPE")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(RestorationTheme.subtleText)
                        
                        if result.suggestedRecipe.stages.isEmpty {
                            Text("Bypass all stages")
                                .font(.system(size: 12))
                                .foregroundStyle(RestorationTheme.subtleText)
                        } else {
                            HStack(spacing: 10) {
                                ForEach(result.suggestedRecipe.stages, id: \.stageName) { stage in
                                    HStack(spacing: 6) {
                                        Image(systemName: "slider.horizontal.3")
                                            .font(.system(size: 10))
                                            .foregroundStyle(RestorationTheme.saffron)
                                        
                                        Text(stage.stageName.replacingOccurrences(of: "_", with: " ").capitalized)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.white)
                                        
                                        Text(String(format: "%.0f%%", stage.strength * 100.0))
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundStyle(RestorationTheme.neonTeal)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.03))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(RestorationTheme.glassBorder, lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
                .glassCard()
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                EmptyView()
            }
        }
    }
    
    // Helper to resolve detected issues badges dynamically based on features
    private struct BadgeData {
        let text: String
        let icon: String
        let color: Color
    }
    
    private func getBadges(features: SangeetV1AudioFeatures) -> [BadgeData] {
        var badges: [BadgeData] = []
        
        if features.hum50HzPresent {
            badges.append(BadgeData(text: "50Hz Hum", icon: "exclamationmark.shield.fill", color: .orange))
        }
        if features.hum60HzPresent {
            badges.append(BadgeData(text: "60Hz Hum", icon: "exclamationmark.shield.fill", color: .orange))
        }
        if features.clippingRate > 0.001 {
            badges.append(BadgeData(text: String(format: "Clipping (%.1f%%)", features.clippingRate * 100.0), icon: "waveform.path.ecg", color: .red))
        }
        if features.clickRatePerS > 0.5 {
            badges.append(BadgeData(text: String(format: "Clicks (%.1f/s)", features.clickRatePerS), icon: "sparkles", color: .orange))
        }
        if features.hfRolloffHz < 6000.0 {
            badges.append(BadgeData(text: String(format: "HF Rolloff (%.1f kHz)", features.hfRolloffHz / 1000.0), icon: "arrow.down.right.and.arrow.up.left", color: .yellow))
        }
        
        // Take at most 3 to prevent UI layout overflow
        return Array(badges.prefix(3))
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
