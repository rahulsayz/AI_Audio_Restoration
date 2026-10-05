import SwiftUI
import AudioEngine

struct OnboardingView: View {
    @ObservedObject var viewModel: RestorationViewModel
    @Binding var isPresented: Bool
    
    @State private var currentScreen: Int = 1
    
    // Screen 3 Trial states
    @State private var selectedSample: String? = nil
    @State private var hasStartedTrialRestoration = false
    
    // Telemetry Consent (Screen 4 binds)
    @AppStorage("SAITelemetryEnabled") private var isTelemetryEnabled = true
    @AppStorage("SAITelemetryConsentShown") private var isConsentShown = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Text("SANGEET AI BETA TOUR")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.orange.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
                
                Spacer()
                
                // Screen Indicator Dots
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { index in
                        Circle()
                            .fill(currentScreen == index ? Color.orange : Color.gray.opacity(0.3))
                            .frame(width: 6, height: 6)
                            .animation(.spring(), value: currentScreen)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            // Content view switching
            Group {
                switch currentScreen {
                case 1:
                    welcomeScreen
                case 2:
                    howItWorksScreen
                case 3:
                    trySampleScreen
                case 4:
                    telemetryScreen
                case 5:
                    quickTourScreen
                default:
                    welcomeScreen
                }
            }
            .frame(maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            
            Divider()
                .background(Color.gray.opacity(0.2))
            
            // Footer Navigation Bar
            HStack {
                if currentScreen > 1 {
                    Button(action: {
                        // Pause any onboarding playback when moving screens to prevent leaking audio
                        viewModel.cleanupPlayer()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            currentScreen -= 1
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .frame(width: 80, height: 24)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Spacer()
                        .frame(width: 90)
                }
                
                Spacer()
                
                if currentScreen < 5 {
                    Button(action: {
                        // Pause playback when navigating away from trial screen
                        if currentScreen == 3 {
                            viewModel.cleanupPlayer()
                        }
                        
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            currentScreen += 1
                        }
                    }) {
                        HStack(spacing: 6) {
                            Text(currentScreen == 3 ? "Skip Sample" : "Next")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 100, height: 24)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    // Disable next from trial if it's currently processing
                    .disabled(currentScreen == 3 && viewModel.isProcessing)
                } else {
                    // Screen 5 Completion Action
                    Button(action: {
                        viewModel.cleanupPlayer()
                        isConsentShown = true
                        isPresented = false
                    }) {
                        Text("Start Restoring")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 150, height: 26)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        }
        .frame(width: 720, height: 500)
        .background(
            ZStack {
                Color(NSColor.underPageBackgroundColor)
                
                // Deep space gradient effect
                RadialGradient(
                    colors: [Color.orange.opacity(0.08), Color.clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 400
                )
                
                RadialGradient(
                    colors: [Color.orange.opacity(0.03), Color.clear],
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: 300
                )
            }
        )
    }
    
    // MARK: - Screen 1: Welcome
    private var welcomeScreen: some View {
        VStack(spacing: 16) {
            Spacer()
            
            // Brand Logo Glow
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 72, height: 72)
                    .blur(radius: 8)
                
                Image(systemName: "music.quarternote.button.angled")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .foregroundColor(.orange)
            }
            
            Text("Welcome to Sangeet AI Beta")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            
            Text("You are one of the first 30 Indian music collectors and archives selected to test Sangeet.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .padding(.top, 2)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Expect Things to Break")
                            .font(.system(size: 12, weight: .semibold))
                        Text("This is an early Phase 1 orchestrated beta. You may encounter processing failures on highly corrupted shellacs or clipping artifacts on custom formats.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "waveform.path.badge.plus")
                        .foregroundColor(.orange)
                        .padding(.top, 2)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your Feedback Shapes Sangeet")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Every bug you submit or restored file you flag helps refine our ML intelligence routing prior to our commercial production launch.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.03))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.orange.opacity(0.15), lineWidth: 1)
            )
            .padding(.horizontal, 60)
            
            Spacer()
        }
    }
    
    // MARK: - Screen 2: How It Works
    private var howItWorksScreen: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Text("How Sangeet Works")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            
            Text("Sangeet bridges low-latency native Swift audio processing with localized Python ML daemon engines to restore historical playback files in three high-fidelity stages:")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
            
            // Flowchart Diagram
            HStack(spacing: 0) {
                // Node 1
                VStack(spacing: 6) {
                    Text("1. ANALYZE")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                    
                    VStack(spacing: 4) {
                        Text("Spectral Profiling")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Detects hum frequency, clipping levels, and broadband hiss ratios.")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(8)
                    .frame(width: 140, height: 75)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.orange.opacity(0.5))
                    .padding(.horizontal, 10)
                
                // Node 2
                VStack(spacing: 6) {
                    Text("2. RESTORE")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                    
                    VStack(spacing: 4) {
                        Text("Localized ML Models")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Removes background noise and transients via local DeepFilterNet and Click DSP.")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(8)
                    .frame(width: 140, height: 75)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.orange.opacity(0.5))
                    .padding(.horizontal, 10)
                
                // Node 3
                VStack(spacing: 6) {
                    Text("3. MASTER")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                    
                    VStack(spacing: 4) {
                        Text("Accelerate mastering")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Runs final peak limiting & loudness matching using Apple's Accelerate framework.")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(8)
                    .frame(width: 140, height: 75)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
            }
            .padding(.top, 10)
            
            Text("No data leaves your Mac — all processing, modeling, and audio rendering is 100% offline.")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.orange.opacity(0.7))
                .padding(.top, 6)
            
            Spacer()
        }
    }
    
    // MARK: - Screen 3: Try Sample Restoration
    private var trySampleScreen: some View {
        VStack(spacing: 12) {
            Text("Try a Sample Restoration")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .padding(.top, 8)
            
            if !hasStartedTrialRestoration {
                Text("Select one of our licensed or Creative Commons archival reference tracks to hear Sangeet's restoration chain in action:")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
                    .padding(.bottom, 6)
                
                // Track Cards
                VStack(spacing: 8) {
                    sampleCard(
                        id: "noisy_playback",
                        title: "Noisy Playback Recording",
                        description: "Mohammed Rafi 1957 Vocal track. High hiss and surface noise.",
                        icon: "music.mic"
                    )
                    
                    sampleCard(
                        id: "scratchy_classical",
                        title: "Scratchy Classical Recording",
                        description: "Pandit Ravi Shankar Sitar performance. Transient clicks and electrical hum.",
                        icon: "guitars"
                    )
                    
                    sampleCard(
                        id: "muffled_tape",
                        title: "Muffled Tape Recording",
                        description: "RD Burman 1972 Film Orchestra. Muffled highs and mains buzz.",
                        icon: "opticaldisc"
                    )
                }
                .padding(.horizontal, 48)
                
                Button(action: {
                    triggerSampleRestoration()
                }) {
                    Text("Restore Selected Track")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 180, height: 26)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(selectedSample == nil)
                .padding(.top, 10)
                
            } else {
                // Restoration progress & comparison UI
                VStack(spacing: 16) {
                    if viewModel.isProcessing {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            
                            Text(viewModel.currentStage)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.orange)
                            
                            // Progress bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 6)
                                    
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.orange)
                                        .frame(width: geo.size.width * CGFloat(viewModel.progress), height: 6)
                                        .animation(.easeInOut, value: viewModel.progress)
                                }
                            }
                            .frame(height: 6)
                            .padding(.horizontal, 100)
                            
                            Text(String(format: "%.0f%% Completed", viewModel.progress * 100.0))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .frame(height: 180)
                    } else if viewModel.restorationComplete {
                        // Trial Playback Success UI
                        VStack(spacing: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.title3)
                                Text("Restoration Completed Successfully!")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                            }
                            
                            // Comparison Control Panel
                            VStack(spacing: 12) {
                                // A/B Toggle pills
                                HStack(spacing: 0) {
                                    Button(action: {
                                        if !viewModel.playerOriginalActive {
                                            viewModel.toggleSource()
                                        }
                                    }) {
                                        Text("ORIGINAL")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(viewModel.playerOriginalActive ? .black : .secondary)
                                            .frame(width: 100, height: 24)
                                            .background(viewModel.playerOriginalActive ? Color.orange : Color.clear)
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Button(action: {
                                        if viewModel.playerOriginalActive {
                                            viewModel.toggleSource()
                                        }
                                    }) {
                                        Text("RESTORED")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(!viewModel.playerOriginalActive ? .black : .secondary)
                                            .frame(width: 100, height: 24)
                                            .background(!viewModel.playerOriginalActive ? Color.orange : Color.clear)
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(3)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                                
                                // Scrubbing & playback slider
                                VStack(spacing: 4) {
                                    HStack {
                                        Text(formatTime(viewModel.playerCurrentTime))
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.secondary)
                                        
                                        Spacer()
                                        
                                        Text(formatTime(viewModel.playerTotalDuration))
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Slider(value: Binding(
                                        get: { viewModel.playerProgress },
                                        set: { viewModel.seekPlayer(toPercent: $0) }
                                    ), in: 0...1)
                                    .accentColor(.orange)
                                }
                                .padding(.horizontal, 60)
                                
                                // Play / Pause & Volume matching
                                HStack(spacing: 24) {
                                    Button(action: {
                                        viewModel.toggleVolumeMatch()
                                    }) {
                                        Image(systemName: viewModel.playerVolumeMatchActive ? "speaker.wave.3.fill" : "speaker.wave.1")
                                            .foregroundColor(viewModel.playerVolumeMatchActive ? .orange : .secondary)
                                            .font(.system(size: 14))
                                            .frame(width: 32, height: 32)
                                            .background(Color.white.opacity(0.03))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("Toggle volume matching to A/B at identical loudness levels.")
                                    
                                    Button(action: {
                                        viewModel.togglePlayback()
                                    }) {
                                        Image(systemName: viewModel.playerIsPlaying ? "pause.fill" : "play.fill")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(.black)
                                            .frame(width: 48, height: 48)
                                            .background(Color.orange)
                                            .clipShape(Circle())
                                            .shadow(color: Color.orange.opacity(0.3), radius: 6)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Button(action: {
                                        viewModel.toggleLoop()
                                    }) {
                                        Image(systemName: "repeat")
                                            .foregroundColor(viewModel.playerLoopActive ? .orange : .secondary)
                                            .font(.system(size: 14))
                                            .frame(width: 32, height: 32)
                                            .background(Color.white.opacity(0.03))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.02))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .padding(.horizontal, 60)
                            
                            Button(action: {
                                viewModel.cleanupPlayer()
                                withAnimation {
                                    hasStartedTrialRestoration = false
                                    selectedSample = nil
                                }
                            }) {
                                Text("Try Another Sample Track")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(height: 250)
                    } else if let error = viewModel.errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.title)
                            
                            Text("Restoration Failed")
                                .font(.system(size: 14, weight: .bold))
                            
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 60)
                            
                            Button(action: {
                                withAnimation {
                                    hasStartedTrialRestoration = false
                                }
                            }) {
                                Text("Retry")
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                    .background(Color.orange)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(height: 180)
                    }
                }
                .transition(.opacity)
            }
        }
    }
    
    // Custom item cards for Sample choices
    private func sampleCard(id: String, title: String, description: String, icon: String) -> some View {
        Button(action: {
            selectedSample = id
        }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(selectedSample == id ? .orange : .secondary)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(selectedSample == id ? .orange : .primary)
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Circle()
                    .fill(selectedSample == id ? Color.orange : Color.clear)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                    )
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(selectedSample == id ? Color.orange.opacity(0.04) : Color.white.opacity(0.02))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedSample == id ? Color.orange.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // Execute sample restoration
    private func triggerSampleRestoration() {
        guard let sampleId = selectedSample else { return }
        
        // 1. Fetch file path from bundle or local disk
        guard let url = getSampleFileURL(name: sampleId) else {
            viewModel.loadFile(url: URL(fileURLWithPath: "")) // Trigger error state
            return
        }
        
        hasStartedTrialRestoration = true
        
        // 2. Queue processing in View Model
        viewModel.loadFile(url: url)
        
        // 3. Initiate pipeline execution
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            viewModel.startRestoration()
            
            // Periodically check if completion succeeded and setup players inside the OnboardingView
            observeCompletion()
        }
    }
    
    private func observeCompletion() {
        Task {
            while true {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if !viewModel.isProcessing {
                    if viewModel.restorationComplete {
                        viewModel.setupPlayer()
                    }
                    break
                }
            }
        }
    }
    
    private func getSampleFileURL(name: String) -> URL? {
        // Search Bundle.main
        if let path = Bundle.main.path(forResource: name, ofType: "wav") {
            return URL(fileURLWithPath: path)
        }
        
        // Search workspace gitignored corpus as a fallback for local developers
        let corpusName: String
        switch name {
        case "noisy_playback": corpusName = "real_test_vocal_rafi"
        case "scratchy_classical": corpusName = "real_test_sitar_ravi"
        case "muffled_tape": corpusName = "real_test_orchestra_burman"
        default: return nil
        }
        let fallbackPath = "/Users/rahulchaturvedi/AI_Audio_Restoration/eval/corpus/\(corpusName).wav"
        if FileManager.default.fileExists(atPath: fallbackPath) {
            return URL(fileURLWithPath: fallbackPath)
        }
        return nil
    }
    
    private func formatTime(_ time: Double) -> String {
        guard !time.isNaN && !time.isInfinite else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Screen 4: Telemetry Consent
    private var telemetryScreen: some View {
        VStack(spacing: 16) {
            Spacer()
            
            HStack(spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .foregroundColor(.orange)
                
                Text("Help Improve Sangeet — Anonymous Performance Diagnostics")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 40)
            
            Text("Sangeet AI works fully offline to guarantee your music intellectual property remains secure. However, sharing hardware diagnostics and anonymized processing telemetry helps our engineers troubleshoot model inference errors:")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 48)
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text("We collect: Application crashes, model processing duration, and settings presets utilized.")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "xmark.shield.fill")
                        .foregroundColor(.red)
                    Text("We NEVER collect: Your audio material, metadata, filenames, or personal identifiers.")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.02))
            .cornerRadius(8)
            .padding(.horizontal, 48)
            
            // Switch Choice Options
            HStack(spacing: 20) {
                Button(action: {
                    isTelemetryEnabled = false
                    TelemetryManager.shared.track(event: "onboarding_telemetry_opt_out")
                }) {
                    HStack {
                        Image(systemName: !isTelemetryEnabled ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(!isTelemetryEnabled ? .orange : .secondary)
                        Text("Skip Diagnostics")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(width: 180, height: 30)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(!isTelemetryEnabled ? Color.orange.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    isTelemetryEnabled = true
                    TelemetryManager.shared.trackHardwareConfig()
                    TelemetryManager.shared.track(event: "onboarding_telemetry_opt_in")
                }) {
                    HStack {
                        Image(systemName: isTelemetryEnabled ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(isTelemetryEnabled ? .orange : .secondary)
                        Text("Opt-In (Recommended)")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .frame(width: 200, height: 30)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isTelemetryEnabled ? Color.orange.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)
            
            Spacer()
        }
    }
    
    // MARK: - Screen 5: Quick Tour
    private var quickTourScreen: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Text("Ready to Restore Your Catalog?")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            
            Text("Here is a quick tour of key Sangeet elements designed for professional workflows:")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
            
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right.fill")
                        .foregroundColor(.orange)
                        .font(.title3)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Instant A/B Comparison")
                            .font(.system(size: 12, weight: .bold))
                        Text("Toggle source signals on-the-fly. Active loudness matching ensures A/B comparison represents true signal corrections, not volume differences.")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "folder.fill.badge.plus")
                        .foregroundColor(.orange)
                        .font(.title3)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Local Project Library Sidebar")
                            .font(.system(size: 12, weight: .bold))
                        Text("All restorations are tracked automatically in your local SQLite library. Select an entry to review features, re-listen, or trigger export.")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.orange)
                        .font(.title3)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Custom Mastering & Presets")
                            .font(.system(size: 12, weight: .bold))
                        Text("Configure target LUFS targets in Settings (e.g., -14 integrated for streaming or -9 for high-punch remasters) to standardize exports.")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.02))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 50)
            
            Spacer()
        }
    }
}
