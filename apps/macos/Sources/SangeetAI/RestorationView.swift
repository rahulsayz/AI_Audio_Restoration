import SwiftUI
import UniformTypeIdentifiers
import AudioEngine

public struct RestorationView: View {
    @ObservedObject var viewModel: RestorationViewModel
    @State private var isDragging: Bool = false
    #if BETA
    @State private var showFeedbackSheet: Bool = false
    #endif
    
    public init(viewModel: RestorationViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ZStack {
            // Elegant ambient organic soundwave background
            SoundwaveBackground()
            
            HStack(spacing: 0) {
                // Left Panel: Scrollable Project Library Sidebar
                sidebarSection
                
                // Vertical Glass Divider
                Rectangle()
                    .fill(RestorationTheme.glassBorder)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                
                // Right Panel: Main Restoration Workflow
                VStack(spacing: 20) {
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
                .padding(.horizontal, 30)
                .padding(.vertical, 24)
                .frame(width: 540, height: 600)
            }
            .frame(width: 800, height: 600)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.loadLibrary()
        }
        #if BETA
        .sheet(isPresented: $showFeedbackSheet) {
            FeedbackWidgetView(viewModel: viewModel)
        }
        #endif
    }
    
    // MARK: - Subviews
    
    private var headerSection: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
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
                
                #if BETA
                Text("BETA")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RestorationTheme.saffron)
                    .cornerRadius(4)
                    .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 3 }
                #endif
            }
            
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
                
                if viewModel.restorationComplete {
                    ComparePlayerView(viewModel: viewModel)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    analysisSection
                }
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
        .frame(height: 120)
    }
    
    private var idleStateView: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Text("Mastering Preset:")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(RestorationTheme.subtleText)
                
                Picker("Preset Selection", selection: $viewModel.selectedPreset) {
                    Text("Streaming (-14 LUFS)").tag(MasteringChain.Preset.streaming)
                    Text("Remaster (-9 LUFS)").tag(MasteringChain.Preset.remaster)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
            }
            
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
        VStack(spacing: 12) {
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
            
            if let lufs = viewModel.measuredLUFS, let tp = viewModel.measuredTruePeak {
                HStack(spacing: 20) {
                    HStack(spacing: 6) {
                        Text("LOUDNESS:")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(RestorationTheme.subtleText)
                        Text(String(format: "%.1f LUFS", lufs))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(RestorationTheme.neonTeal)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(RestorationTheme.glassBorder, lineWidth: 1)
                    )
                    
                    HStack(spacing: 6) {
                        Text("TRUE PEAK:")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(RestorationTheme.subtleText)
                        Text(String(format: "%.2f dBTP", tp))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(tp > -1.05 ? RestorationTheme.neonTeal : .yellow)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(RestorationTheme.glassBorder, lineWidth: 1)
                    )
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
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
    
    // MARK: - Sidebar List Views
    
    private var sidebarSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header Title
            VStack(alignment: .leading, spacing: 4) {
                Text("PROJECT LIBRARY")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(RestorationTheme.saffron)
                
                Text("Past Restorations")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(RestorationTheme.subtleText)
            }
            .padding(.top, 24)
            .padding(.horizontal, 16)
            
            Divider()
                .background(RestorationTheme.glassBorder)
                .padding(.horizontal, 16)
            
            VStack {
                if viewModel.libraryEntries.isEmpty {
                    // Sleek Empty State
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.minus")
                            .font(.system(size: 28))
                            .foregroundStyle(RestorationTheme.subtleText)
                        Text("No past restorations yet")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(RestorationTheme.subtleText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 60)
                } else {
                    // Scrollable restoration history
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(viewModel.libraryEntries, id: \.id) { entry in
                                libraryRow(entry: entry)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 24)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            
            #if BETA
            Divider()
                .background(RestorationTheme.glassBorder)
                .padding(.horizontal, 16)
            
            Button(action: { showFeedbackSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 13))
                    Text("Feedback")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(RestorationTheme.saffron)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RestorationTheme.saffron.opacity(0.08))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(RestorationTheme.saffron.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            #endif
        }
        .frame(width: 260, height: 600, alignment: .topLeading)
        .background(
            Color.black.opacity(0.15)
                .ignoresSafeArea()
        )
    }
    
    private func libraryRow(entry: LibraryEntry) -> some View {
        let isSelected = viewModel.selectedEntryID == entry.id
        let originalURL = URL(fileURLWithPath: entry.originalPath)
        let fileExists = FileManager.default.fileExists(atPath: originalURL.path)
        let isOrphaned = !fileExists
        
        return Button(action: {
            if !isOrphaned {
                withAnimation {
                    viewModel.selectEntry(entry)
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    // Left Column: Metadata
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.filename)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isOrphaned ? RestorationTheme.subtleText : .white)
                            .lineLimit(1)
                        
                        HStack(spacing: 8) {
                            Text(entry.durationString)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(RestorationTheme.subtleText)
                            
                            Circle()
                                .fill(RestorationTheme.subtleText.opacity(0.5))
                                .frame(width: 3, height: 3)
                            
                            Text(formatDate(entry.restorationDate))
                                .font(.system(size: 10))
                                .foregroundStyle(RestorationTheme.subtleText)
                        }
                    }
                    
                    Spacer()
                    
                    // Right Column: Delete
                    Button(action: {
                        withAnimation {
                            viewModel.deleteEntry(id: entry.id)
                        }
                    }) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.red.opacity(0.7))
                            .padding(6)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete past restoration entry")
                }
                
                // Soundwave thumbnail
                HStack {
                    if let amplitudes = try? JSONDecoder().decode([Float].self, from: entry.waveformPointsData) {
                        ThumbnailWaveformView(
                            amplitudes: amplitudes,
                            color: entry.preset == "streaming" ? RestorationTheme.neonTeal : RestorationTheme.saffron
                        )
                        .opacity(isOrphaned ? 0.3 : 1.0)
                    }
                    
                    Spacer()
                    
                    // Preset Badge
                    Text(entry.preset.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(entry.preset == "streaming" ? RestorationTheme.neonTeal : RestorationTheme.saffron)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            (entry.preset == "streaming" ? RestorationTheme.neonTeal : RestorationTheme.saffron).opacity(0.08)
                        )
                        .cornerRadius(3)
                }
                
                // Missing warning
                if isOrphaned {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                        Text("File Moved / Not Found")
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.orange.opacity(0.8))
                    .padding(.top, 2)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white.opacity(0.04) : Color.white.opacity(0.01))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? RestorationTheme.saffron.opacity(0.3) : RestorationTheme.glassBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isOrphaned)
        .opacity(isOrphaned ? 0.6 : 1.0)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM, HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - SwiftUI Previews

#if DEBUG
#Preview("Empty State") {
    RestorationView(viewModel: RestorationViewModel())
}

#Preview("Loaded State") {
    RestorationView(viewModel: RestorationViewModel.makeLoadedPreviewMock())
}

#Preview("Processing State") {
    RestorationView(viewModel: RestorationViewModel.makeProcessingPreviewMock())
}
#endif

// MARK: - Beta Feedback Implementations
#if BETA

// MARK: - FeedbackQueueManager
public final class FeedbackQueueManager: ObservableObject {
    public static let shared = FeedbackQueueManager()
    
    private let queueURL: URL
    private var syncTimer: Timer?
    private var isProcessing = false
    private let queue = DispatchQueue(label: "ai.sangeet.feedback.queue", qos: .background)
    
    public struct PendingFeedback: Codable, Identifiable {
        public let id: UUID
        public let name: String
        public let email: String
        public let category: String
        public let subject: String
        public let message: String
        public let timestamp: String
        public let includeDiagnostics: Bool
        public let macosVersion: String
        public let macModel: String
        public let totalRam: String
        
        // Attachment details
        public let attachMedia: Bool
        public let audioFilePath: String?
        public let yamlString: String?
        
        public var retryCount: Int
    }
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.queueURL = appSupport.appendingPathComponent("SangeetAI").appendingPathComponent("feedback_queue")
        
        do {
            try FileManager.default.createDirectory(at: queueURL, withIntermediateDirectories: true)
        } catch {
            print("[FeedbackQueueManager] Failed to create queue folder: \(error.localizedDescription)")
        }
        
        // Start initial processing sweep with a brief startup delay to keep app launch instant
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.processQueue()
            self?.startBackgroundSync()
        }
    }
    
    /// Persists a failed submission as a JSON file to disk for retry
    public func queueFailedSubmission(
        name: String,
        email: String,
        category: String,
        subject: String,
        message: String,
        includeDiagnostics: Bool,
        macosVersion: String,
        macModel: String,
        totalRam: String,
        attachMedia: Bool,
        audioFilePath: String?,
        yamlString: String?
    ) {
        let feedback = PendingFeedback(
            id: UUID(),
            name: name,
            email: email,
            category: category,
            subject: subject,
            message: message,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            includeDiagnostics: includeDiagnostics,
            macosVersion: macosVersion,
            macModel: macModel,
            totalRam: totalRam,
            attachMedia: attachMedia,
            audioFilePath: audioFilePath,
            yamlString: yamlString,
            retryCount: 0
        )
        
        queue.async { [weak self] in
            guard let self = self else { return }
            let fileURL = self.queueURL.appendingPathComponent("feedback_\(feedback.id).json")
            do {
                let data = try JSONEncoder().encode(feedback)
                try data.write(to: fileURL, options: .atomic)
                print("[FeedbackQueueManager] Saved pending feedback to local queue: \(fileURL.lastPathComponent)")
                
                // Immediately attempt processing in case network just recovered
                DispatchQueue.main.async {
                    self.processQueue()
                }
            } catch {
                print("[FeedbackQueueManager] Failed to persist pending feedback: \(error.localizedDescription)")
            }
        }
    }
    
    /// Scans the local directory and attempts to dispatch all queued feedback submissions
    public func processQueue() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Mutex guard to prevent overlapping sweeps
            guard !self.isProcessing else { return }
            self.isProcessing = true
            defer { self.isProcessing = false }
            
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(at: self.queueURL, includingPropertiesForKeys: nil)
                let jsonURLs = fileURLs.filter { $0.pathExtension.lowercased() == "json" }
                
                if jsonURLs.isEmpty { return }
                print("[FeedbackQueueManager] Found \(jsonURLs.count) pending feedback forms in queue. Processing...")
                
                for fileURL in jsonURLs {
                    guard let data = try? Data(contentsOf: fileURL),
                          var feedback = try? JSONDecoder().decode(PendingFeedback.self, from: data) else {
                        // Purge corrupted JSONs instantly
                        try? FileManager.default.removeItem(at: fileURL)
                        continue
                    }
                    
                    if feedback.retryCount >= 5 {
                        print("[FeedbackQueueManager] Maximum retries (5) reached for feedback \(feedback.id). Discarding to avoid spam.")
                        try? FileManager.default.removeItem(at: fileURL)
                        continue
                    }
                    
                    let success = self.dispatchMultipartSync(feedback)
                    if success {
                        print("[FeedbackQueueManager] Dispatch succeeded for feedback \(feedback.id). Removing from queue.")
                        try? FileManager.default.removeItem(at: fileURL)
                    } else {
                        feedback.retryCount += 1
                        if let reencoded = try? JSONEncoder().encode(feedback) {
                            try? reencoded.write(to: fileURL, options: .atomic)
                        }
                        print("[FeedbackQueueManager] Dispatch failed for feedback \(feedback.id). Retried \(feedback.retryCount)/5.")
                        // Stop processing downstream items on network error to conserve battery and CPU
                        break
                    }
                }
            } catch {
                print("[FeedbackQueueManager] Error processing feedback queue: \(error.localizedDescription)")
            }
        }
    }
    
    private func startBackgroundSync() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.syncTimer?.invalidate()
            self.syncTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
                self?.processQueue()
            }
        }
    }
    
    /// Direct synchronous dispatch with a semaphore block inside background thread
    private func dispatchMultipartSync(_ feedback: PendingFeedback) -> Bool {
        guard let request = createMultipartRequest(feedback: feedback) else { return false }
        
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                print("[FeedbackQueueManager] Sync connection error: \(error.localizedDescription)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else { return }
            
            if (200...299).contains(httpResponse.statusCode) {
                success = true
            } else {
                print("[FeedbackQueueManager] Sync server returned status code: \(httpResponse.statusCode)")
            }
        }
        
        task.resume()
        _ = semaphore.wait(timeout: .now() + 60.0) // wait up to 60 seconds
        return success
    }
    
    private func createMultipartRequest(feedback: PendingFeedback) -> URLRequest? {
        guard let url = URL(string: "https://feedback.sangeet.app/api/submit") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        func appendField(_ name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        appendField("name", value: feedback.name)
        appendField("email", value: feedback.email)
        appendField("category", value: feedback.category)
        appendField("subject", value: feedback.subject)
        appendField("message", value: feedback.message)
        appendField("timestamp", value: feedback.timestamp)
        
        if feedback.includeDiagnostics {
            appendField("macos_version", value: feedback.macosVersion)
            appendField("mac_model", value: feedback.macModel)
            appendField("total_ram", value: feedback.totalRam)
            appendField("app_version", value: "1.0.0 Beta (Build 1)")
        }
        
        // YAML Attachment
        if let yaml = feedback.yamlString, !yaml.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"yaml\"; filename=\"analysis.yaml\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: text/yaml\r\n\r\n".data(using: .utf8)!)
            body.append("\(yaml)\r\n".data(using: .utf8)!)
        }
        
        // Audio Attachment
        if feedback.attachMedia, let audioPath = feedback.audioFilePath, !audioPath.isEmpty {
            let audioURL = URL(fileURLWithPath: audioPath)
            if FileManager.default.fileExists(atPath: audioURL.path) {
                do {
                    let audioData = try Data(contentsOf: audioURL)
                    let filename = audioURL.lastPathComponent
                    let mimeType = getMimeType(for: audioURL)
                    
                    // Cap upload at 15MB to protect cellular connections & network timeouts
                    if audioData.count <= 15 * 1024 * 1024 {
                        body.append("--\(boundary)\r\n".data(using: .utf8)!)
                        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
                        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
                        body.append(audioData)
                        body.append("\r\n".data(using: .utf8)!)
                    } else {
                        print("[FeedbackQueueManager] Audio file is over 15MB (\(audioData.count) bytes). Skipping attachment.")
                    }
                } catch {
                    print("[FeedbackQueueManager] Failed to read audio bytes: \(error.localizedDescription)")
                }
            }
        }
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        return request
    }
    
    private func getMimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "wav": return "audio/wav"
        case "flac": return "audio/x-flac"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - FeedbackWidgetView
public struct FeedbackWidgetView: View {
    @ObservedObject var viewModel: RestorationViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var category: FeedbackType = .bug
    @State private var message: String = ""
    @State private var attachDetails: Bool = false
    
    @State private var isSubmitting: Bool = false
    @State private var statusMessage: String? = nil
    @State private var isSuccessState: Bool = false
    
    enum FeedbackType: String, CaseIterable, Identifiable {
        case bug = "bug"
        case feature = "feature request"
        case audioQuality = "quality issue"
        case general = "general"
        
        var id: String { self.rawValue }
        var displayName: String {
            switch self {
            case .bug: return "Bug Report"
            case .feature: return "Feature Request"
            case .audioQuality: return "Audio Quality Issue"
            case .general: return "General Feedback"
            }
        }
        
        var icon: String {
            switch self {
            case .bug: return "ladybug.fill"
            case .feature: return "sparkles"
            case .audioQuality: return "waveform.badge.exclamationmark"
            case .general: return "bubble.left.and.bubble.right.fill"
            }
        }
    }
    
    public init(viewModel: RestorationViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Elegant titlebar header
            HStack {
                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("BETA FEEDBACK")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(RestorationTheme.saffron)
                
                Spacer()
                
                if isSubmitting {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 44, height: 20)
                } else {
                    Button(action: submitFeedback) {
                        Text("Send")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(canSubmit ? RestorationTheme.saffron : Color.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.2))
            
            Divider()
                .background(RestorationTheme.glassBorder)
            
            if isSuccessState {
                successStateView
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // Personal credentials Section
                        VStack(spacing: 12) {
                            HStack {
                                Text("Name")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(RestorationTheme.subtleText)
                                    .frame(width: 80, alignment: .leading)
                                TextField("Your full name", text: $name)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                            }
                            
                            Divider()
                                .background(RestorationTheme.glassBorder)
                            
                            HStack {
                                Text("Email")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(RestorationTheme.subtleText)
                                    .frame(width: 80, alignment: .leading)
                                TextField("your.email@example.com", text: $email)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(RestorationTheme.glassBorder, lineWidth: 1)
                        )
                        
                        // Type selector section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("WHAT KIND OF FEEDBACK IS THIS?")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(1.5)
                                .foregroundStyle(RestorationTheme.subtleText)
                            
                            HStack(spacing: 8) {
                                ForEach(FeedbackType.allCases) { type in
                                    Button(action: {
                                        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.7)) {
                                            category = type
                                        }
                                    }) {
                                        VStack(spacing: 6) {
                                            Image(systemName: type.icon)
                                                .font(.system(size: 14))
                                            Text(type.displayName)
                                                .font(.system(size: 9, weight: .bold))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(category == type ? RestorationTheme.saffron.opacity(0.15) : Color.white.opacity(0.02))
                                        .foregroundStyle(category == type ? RestorationTheme.saffron : .white.opacity(0.8))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(category == type ? RestorationTheme.saffron.opacity(0.4) : RestorationTheme.glassBorder, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        // Message field section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("WHAT'S ON YOUR MIND?")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(1.5)
                                .foregroundStyle(RestorationTheme.subtleText)
                            
                            ZStack(alignment: .topLeading) {
                                if message.isEmpty {
                                    Text("Tell us how Sangeet preserves vocal nasality, sympathetic string rings, or microtonals...")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary.opacity(0.5))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 12)
                                }
                                
                                TextEditor(text: $message)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .frame(minHeight: 100)
                                    .cornerRadius(6)
                            }
                            .background(Color.white.opacity(0.01))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(RestorationTheme.glassBorder, lineWidth: 1)
                            )
                        }
                        
                        // Attachment section
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: $attachDetails) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Attach last restoration audio + analysis YAML")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white)
                                    
                                    Text("Attaching your last restored audio file and its analysis recipe helps our engineers pinpoint model artifacts, though uploads may take longer.")
                                        .font(.system(size: 10))
                                        .foregroundColor(RestorationTheme.subtleText)
                                        .lineLimit(nil)
                                }
                                .padding(.leading, 4)
                            }
                            .toggleStyle(.checkbox)
                            .disabled(lastRestorationURL == nil)
                            .opacity(lastRestorationURL == nil ? 0.5 : 1.0)
                            
                            if lastRestorationURL == nil {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 10))
                                    Text("No active restoration completed yet to attach.")
                                        .font(.system(size: 10))
                                }
                                .foregroundStyle(RestorationTheme.saffron)
                                .padding(.leading, 24)
                            }
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.02))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(RestorationTheme.glassBorder, lineWidth: 1)
                        )
                        
                        if let status = statusMessage {
                            HStack(spacing: 8) {
                                Image(systemName: isSuccessState ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(isSuccessState ? RestorationTheme.neonTeal : RestorationTheme.saffron)
                                Text(status)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(nil)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isSuccessState ? RestorationTheme.neonTeal.opacity(0.08) : RestorationTheme.saffron.opacity(0.08))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isSuccessState ? RestorationTheme.neonTeal.opacity(0.2) : RestorationTheme.saffron.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 480, height: 520)
        .background(RestorationTheme.deepSpace)
        .preferredColorScheme(.dark)
        .onAppear(perform: loadDefaults)
    }
    
    private var successStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: isQueuedState ? "clock.arrow.2.circlepath" : "paperplane.fill")
                .font(.system(size: 44))
                .foregroundColor(RestorationTheme.neonTeal)
                .feedbackSymbolEffect()
            
            Text(isQueuedState ? "Feedback Saved Locally" : "Feedback Sent Successfully")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text(isQueuedState ? "We couldn't connect to the server right now. Your feedback has been saved locally, and Sangeet will automatically retry delivering it as soon as you're back online!" : "Thank you! Your feedback has been received and routed straight to beta@sangeet.app. Your contribution helps preserve authentic Indian musical heritage.")
                .font(.system(size: 12))
                .foregroundStyle(RestorationTheme.subtleText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .lineSpacing(4)
            
            Button("Dismiss") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(RestorationTheme.saffron)
            .padding(.top, 12)
            
            Spacer()
        }
        .padding(24)
    }
    
    private var isQueuedState: Bool {
        statusMessage?.contains("queued") == true
    }
    
    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !message.trimmingCharacters(in: .whitespaces).isEmpty &&
        !isSubmitting
    }
    
    private var lastRestorationURL: URL? {
        if viewModel.restorationComplete, let url = viewModel.outputFileURL {
            return url
        }
        return nil
    }
    
    private func loadDefaults() {
        self.email = UserDefaults.standard.string(forKey: "betaRegistrationEmail") ?? ""
        self.name = UserDefaults.standard.string(forKey: "betaRegistrationName") ?? ""
    }
    
    private func submitFeedback() {
        guard canSubmit else { return }
        
        isSubmitting = true
        statusMessage = nil
        
        // Cache credentials to streamline future submissions
        UserDefaults.standard.set(email, forKey: "betaRegistrationEmail")
        UserDefaults.standard.set(name, forKey: "betaRegistrationName")
        
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let totalMemoryGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        let modelIdentifier = getMacModel()
        
        let audioPath = attachDetails ? lastRestorationURL?.path : nil
        let yamlString = attachDetails ? convertAnalysisToYAML(result: viewModel.analysisResult) : nil
        
        // Prepare request
        guard let url = URL(string: "https://feedback.sangeet.app/api/submit") else {
            self.isSubmitting = false
            self.statusMessage = "Configuration error: Invalid submission endpoint"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        func appendField(_ name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        appendField("name", value: name)
        appendField("email", value: email)
        appendField("category", value: category.rawValue)
        appendField("subject", value: "Beta Feedback: \(category.displayName)")
        appendField("message", value: message)
        appendField("timestamp", value: ISO8601DateFormatter().string(from: Date()))
        
        appendField("macos_version", value: osVersion)
        appendField("mac_model", value: modelIdentifier)
        appendField("total_ram", value: "\(totalMemoryGB) GB")
        appendField("app_version", value: "1.0.0 Beta (Build 1)")
        
        // YAML Attachment
        if let yaml = yamlString, !yaml.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"yaml\"; filename=\"analysis.yaml\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: text/yaml\r\n\r\n".data(using: .utf8)!)
            body.append("\(yaml)\r\n".data(using: .utf8)!)
        }
        
        // Audio Attachment
        var hasAudioData = false
        if let audioURL = lastRestorationURL, attachDetails {
            if let audioData = try? Data(contentsOf: audioURL) {
                // Check size guardrail (15MB)
                if audioData.count <= 15 * 1024 * 1024 {
                    let filename = audioURL.lastPathComponent
                    let mimeType = getMimeType(for: audioURL)
                    body.append("--\(boundary)\r\n".data(using: .utf8)!)
                    body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
                    body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
                    body.append(audioData)
                    body.append("\r\n".data(using: .utf8)!)
                    hasAudioData = true
                } else {
                    print("[FeedbackWidgetView] Audio file exceeds 15MB size threshold.")
                }
            }
        }
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        // Dynamic submission session
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isSubmitting = false
                
                if let error = error {
                    // Save to local offline queue on network failures
                    print("[FeedbackWidgetView] Submission failed. Queuing feedback locally: \(error.localizedDescription)")
                    self.queueFeedbackLocally(audioPath: audioPath, yamlString: yamlString)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.queueFeedbackLocally(audioPath: audioPath, yamlString: yamlString)
                    return
                }
                
                if (200...299).contains(httpResponse.statusCode) {
                    withAnimation {
                        self.isSuccessState = true
                        self.statusMessage = "Feedback sent successfully!"
                    }
                } else {
                    // Queue locally on server error status (5xx)
                    print("[FeedbackWidgetView] Server error \(httpResponse.statusCode). Queuing feedback locally.")
                    self.queueFeedbackLocally(audioPath: audioPath, yamlString: yamlString)
                }
            }
        }.resume()
    }
    
    private func queueFeedbackLocally(audioPath: String?, yamlString: String?) {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let totalMemoryGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        let modelIdentifier = getMacModel()
        
        FeedbackQueueManager.shared.queueFailedSubmission(
            name: name,
            email: email,
            category: category.rawValue,
            subject: "Beta Feedback: \(category.displayName)",
            message: message,
            includeDiagnostics: true,
            macosVersion: osVersion,
            macModel: modelIdentifier,
            totalRam: "\(totalMemoryGB) GB",
            attachMedia: attachDetails && audioPath != nil,
            audioFilePath: audioPath,
            yamlString: yamlString
        )
        
        withAnimation {
            self.isSuccessState = true
            self.statusMessage = "Network failed. Feedback has been queued locally."
        }
    }
    
    private func getMacModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
    
    private func getMimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "wav": return "audio/wav"
        case "flac": return "audio/x-flac"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        default: return "application/octet-stream"
        }
    }
    
    private func convertAnalysisToYAML(result: SangeetV1AnalysisResult?) -> String {
        guard let result = result else { return "" }
        var yaml = "---\n"
        yaml += "analysis_result:\n"
        yaml += "  features:\n"
        yaml += "    sample_rate_hz: \(result.features.sampleRate)\n"
        yaml += "    channels: \(result.features.channels)\n"
        yaml += "    duration_seconds: \(String(format: "%.3f", result.features.durationS))\n"
        yaml += "    snr_estimate_db: \(String(format: "%.2f", result.features.snrEstimateDb))\n"
        yaml += "    hum_50hz_present: \(result.features.hum50HzPresent)\n"
        yaml += "    click_rate_per_second: \(String(format: "%.2f", result.features.clickRatePerS))\n"
        yaml += "    hf_rolloff_hz: \(String(format: "%.1f", result.features.hfRolloffHz))\n"
        yaml += "  suggested_recipe:\n"
        yaml += "    stages:\n"
        for stage in result.suggestedRecipe.stages {
            yaml += "      - stage_name: \"\(stage.stageName)\"\n"
            yaml += "        strength: \(String(format: "%.3f", stage.strength))\n"
        }
        return yaml
    }
}

// MARK: - View Extension for macOS 13+ Backward Compatibility
extension View {
    @ViewBuilder
    fileprivate func feedbackSymbolEffect() -> some View {
        if #available(macOS 14.0, *) {
            self.symbolEffect(.bounce, options: .nonRepeating)
        } else {
            self
        }
    }
}
#endif
