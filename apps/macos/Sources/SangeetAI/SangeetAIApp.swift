import SwiftUI
import AudioEngine

@main
struct SangeetAIApp: App {
    // ViewModel instance managed across the application lifecycle
    @StateObject private var viewModel = RestorationViewModel()
    
    // Sparkle updater view model managed across the application lifecycle
    @StateObject private var updaterViewModel = UpdaterViewModel()
    
    // App storage binding for first launch telemetry consent sheet
    @AppStorage("SAITelemetryConsentShown") private var consentShown = false
    
    // App storage binding for beta onboarding completed state
    @AppStorage("SAIOnboardingCompleted") private var onboardingCompleted = false
    
    init() {
        // Register native Objective-C/Cocoa exception crash monitor
        TelemetryManager.registerCrashHandler()
        
        // Listen to native macOS termination notification to track exit events gracefully
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            TelemetryManager.shared.track(event: "app_quit")
        }
        
        // Audit and report stack traces from previous crashed sessions (if any)
        TelemetryManager.shared.checkAndFlushPendingCrash()
        
        // Track launch and system diagnostics if consent has already been obtained
        if UserDefaults.standard.bool(forKey: "SAITelemetryConsentShown") {
            TelemetryManager.shared.trackHardwareConfig()
            TelemetryManager.shared.track(event: "app_launch")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            RestorationView(viewModel: viewModel)
                .frame(minWidth: 800, minHeight: 600)
                .frame(maxWidth: 800, maxHeight: 600)
                .sheet(isPresented: Binding(
                    get: { !onboardingCompleted },
                    set: { _ in }
                )) {
                    OnboardingView(viewModel: viewModel, isPresented: Binding(
                        get: { !onboardingCompleted },
                        set: {
                            onboardingCompleted = !$0
                            consentShown = !$0
                        }
                    ))
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    updaterViewModel.checkForUpdates()
                }
                .disabled(!updaterViewModel.canCheckForUpdates)
            }
        }
        
        Settings {
            SettingsView(updaterViewModel: updaterViewModel)
        }
    }
}

// MARK: - Telemetry Consent Modal
struct TelemetryConsentView: View {
    @Binding var isPresented: Bool
    @AppStorage("SAITelemetryEnabled") private var isTelemetryEnabled = true
    @AppStorage("SAITelemetryConsentShown") private var isConsentShown = false
    
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .foregroundColor(.orange)
                
                Text("Help improve Sangeet — Share anonymous usage data")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .padding(.top, 6)
            
            Text("Sangeet works fully offline. Your audio never leaves your Mac. We'd like to know how the app performs and which features get used so we can make it better. We collect: app crashes, restoration timing, which features you use. We never collect: your audio, filenames, or anything that could identify you. You can change this anytime in Settings.")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 4)
            
            Divider()
                .padding(.vertical, 4)
            
            HStack(spacing: 16) {
                Button(action: {
                    // Skip = opt-out, no dark pattern
                    isTelemetryEnabled = false
                    isConsentShown = true
                    isPresented = false
                }) {
                    Text("Skip")
                        .frame(width: 110, height: 22)
                }
                .buttonStyle(.bordered)
                
                Button(action: {
                    // Share usage data = opt-in/confirm default
                    isTelemetryEnabled = true
                    isConsentShown = true
                    isPresented = false
                    
                    // Track baseline configuration upon receiving explicit consent
                    TelemetryManager.shared.trackHardwareConfig()
                    TelemetryManager.shared.track(event: "app_launch")
                }) {
                    Text("Share usage data")
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(width: 140, height: 22)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(.bottom, 6)
        }
        .padding(22)
        .frame(width: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

