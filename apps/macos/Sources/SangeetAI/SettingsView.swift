import SwiftUI
import UniformTypeIdentifiers

/// Native macOS Sangeet AI Settings Panel View
public struct SettingsView: View {
    private enum Tab: Hashable {
        case general
        case audio
        case storage
        case privacy
        #if BETA
        case feedback
        #endif
        case about
    }
    
    @State private var activeTab: Tab = .general
    @ObservedObject var updaterViewModel: UpdaterViewModel
    
    public init(updaterViewModel: UpdaterViewModel) {
        self.updaterViewModel = updaterViewModel
    }
    
    public var body: some View {
        TabView(selection: $activeTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(Tab.general)
            
            AudioSettingsView()
                .tabItem {
                    Label("Audio", systemImage: "waveform")
                }
                .tag(Tab.audio)
            
            StorageSettingsView()
                .tabItem {
                    Label("Storage", systemImage: "folder")
                }
                .tag(Tab.storage)
            
            PrivacySettingsView()
                .tabItem {
                    Label("Privacy", systemImage: "lock.shield")
                }
                .tag(Tab.privacy)
            
            #if BETA
            FeedbackSettingsView()
                .tabItem {
                    Label("Feedback", systemImage: "envelope.badge")
                }
                .tag(Tab.feedback)
            #endif
            
            AboutSettingsView(updaterViewModel: updaterViewModel)
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(Tab.about)
        }
        .frame(width: 480, height: 420)
        .padding(.horizontal, 8)
    }
}

// MARK: - General Tab View
struct GeneralSettingsView: View {
    @AppStorage("defaultMasteringPreset") private var defaultMasteringPreset = "streaming"
    
    // Sparkle User Defaults Keys
    @AppStorage("SUEnableAutomaticChecks") private var enableAutomaticChecks = true
    @AppStorage("SUAutomaticallyUpdate") private var automaticallyUpdate = false
    @AppStorage("SUScheduledCheckInterval") private var scheduledCheckInterval = 604800 // 1 week
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Restoration & Mastering Settings")
                        .font(.headline)
                    
                    Picker("Default Mastering Preset", selection: $defaultMasteringPreset) {
                        Text("Standard Streaming (-14 LUFS, -1 dBTP)").tag("streaming")
                        Text("Modern Indian Remaster (-9 LUFS, -1 dBTP)").tag("remaster")
                    }
                    .pickerStyle(.radioGroup)
                    .help("Select the default mastering target applied when processing new tracks.")
                    
                    Text("Streaming is optimized for global digital distribution. Remaster is punchier and matches standard golden-era Indian music LP re-releases.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Application Updates")
                        .font(.headline)
                    
                    Toggle("Check for updates automatically", isOn: $enableAutomaticChecks)
                        .help("If enabled, Sangeet AI will periodically check our secure feed for new versions.")
                    
                    if enableAutomaticChecks {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Automatically download updates", isOn: $automaticallyUpdate)
                                .help("Default is off to preserve metered connections. Sangeet will notify you when a download is ready.")
                                .padding(.leading, 20)
                            
                            Picker("Check Frequency", selection: $scheduledCheckInterval) {
                                Text("Daily").tag(86400)
                                Text("Weekly").tag(604800)
                                Text("Monthly").tag(2628000)
                            }
                            .pickerStyle(.menu)
                            .frame(width: 280)
                            .padding(.leading, 20)
                            .help("How often Sparkle checks for new updates.")
                        }
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Audio Tab View
struct AudioSettingsView: View {
    @AppStorage("defaultOutputFormat") private var defaultOutputFormat = "WAV"
    @AppStorage("defaultWavBitDepth") private var defaultWavBitDepth = 24
    @AppStorage("defaultAudioBitrate") private var defaultAudioBitrate = 256
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio Encoding Specifications")
                .font(.headline)
            
            Picker("Default Output Format", selection: $defaultOutputFormat) {
                Text("WAV (.wav)").tag("WAV")
                Text("FLAC (.flac)").tag("FLAC")
                Text("MP3 (.mp3)").tag("MP3")
                Text("M4A / AAC (.m4a)").tag("M4A")
            }
            .pickerStyle(.menu)
            .frame(width: 280)
            .help("The default audio format selected for restored file output.")
            
            if defaultOutputFormat == "WAV" {
                Picker("WAV Bit Depth", selection: $defaultWavBitDepth) {
                    Text("16-bit Integer PCM").tag(16)
                    Text("24-bit Integer PCM (Standard)").tag(24)
                    Text("32-bit Floating Point").tag(32)
                }
                .pickerStyle(.radioGroup)
                .padding(.leading, 10)
                .help("Linear PCM bit resolution. 24-bit is the professional production standard.")
            }
            
            if defaultOutputFormat == "MP3" || defaultOutputFormat == "M4A" {
                Picker("Target Bitrate", selection: $defaultAudioBitrate) {
                    Text("128 kbps (Standard)").tag(128)
                    Text("192 kbps (Medium High)").tag(192)
                    Text("256 kbps (High Quality)").tag(256)
                    Text("320 kbps (Maximum Quality)").tag(320)
                }
                .pickerStyle(.menu)
                .frame(width: 280)
                .padding(.leading, 10)
                .help("Target compressed bitrate. Higher values preserve more high-frequency spatial detail.")
            }
            
            if defaultOutputFormat == "MP3" {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("MP3 encoding is not natively supported by macOS AVFoundation. Sangeet will write a high-fidelity M4A (AAC) file as a replacement if MP3 is selected.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Storage Tab View
struct StorageSettingsView: View {
    @AppStorage("modelLocation") private var modelLocation = "~/Library/Application Support/SangeetAI/models/"
    @AppStorage("libraryLocation") private var libraryLocation = "~/Library/Application Support/SangeetAI/library.sqlite"
    @AppStorage("evalCacheSizeMB") private var evalCacheSizeMB = 512
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Local Directories & Storage Paths")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Model Download Path")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    TextField("", text: $modelLocation)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        selectDirectory { path in
                            modelLocation = path
                        }
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Project Library SQLite Path")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    TextField("", text: $libraryLocation)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        selectFile { path in
                            libraryLocation = path
                        }
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Evaluation Cache Size Threshold")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    Slider(value: Binding(
                        get: { Double(evalCacheSizeMB) },
                        set: { evalCacheSizeMB = Int($0) }
                    ), in: 128...4096, step: 128)
                    Text("\(evalCacheSizeMB) MB")
                        .frame(width: 60, alignment: .trailing)
                }
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private func selectDirectory(completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: (modelLocation as NSString).expandingTildeInPath)
        
        if panel.runModal() == .OK, let url = panel.url {
            completion(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
        }
    }
    
    private func selectFile(completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "sqlite") ?? .data]
        panel.directoryURL = URL(fileURLWithPath: ((libraryLocation as NSString).deletingLastPathComponent as NSString).expandingTildeInPath)
        
        if panel.runModal() == .OK, let url = panel.url {
            completion(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
        }
    }
}

// MARK: - About Tab View
struct AboutSettingsView: View {
    @ObservedObject var updaterViewModel: UpdaterViewModel
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.house.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .foregroundColor(.orange)
                
            Text("Sangeet AI")
                .font(.system(size: 18, weight: .bold, design: .rounded))
            
            #if BETA
            Text("Version 1.0.0 Beta (Build 1)")
                .font(.caption)
                .foregroundColor(.secondary)
            #else
            Text("Version 1.0.0 (Build 1)")
                .font(.caption)
                .foregroundColor(.secondary)
            #endif
            
            Button("Check for Updates...") {
                updaterViewModel.checkForUpdates()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(!updaterViewModel.canCheckForUpdates)
            .padding(.vertical, 2)
            
            Text("Indian Music AI Restoration & Remastering Console")
                .font(.caption2)
                .italic()
                .foregroundColor(.secondary)
                
            Divider()
                .padding(.vertical, 2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Third-Party Model Audit & EULA Cleanliness:")
                    .font(.system(size: 10, weight: .bold))
                
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("This application is distributed under a commercial EULA. Redistribution, decompilation, or generative derivative extraction are strictly prohibited. Model licenses conform strictly to commercial guidelines:")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            
                        ModelLicenseRow(name: "Demucs v4", code: "MIT", weights: "MIT", status: "Approved")
                        ModelLicenseRow(name: "DeepFilterNet 3", code: "Apache 2.0 / MIT", weights: "Apache 2.0", status: "Approved")
                        ModelLicenseRow(name: "NVSR", code: "MIT", weights: "MIT", status: "Approved")
                        ModelLicenseRow(name: "VoiceFixer", code: "MIT", weights: "MIT", status: "Approved")
                    }
                    .padding(4)
                }
                .frame(height: 100)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
                .border(Color(NSColor.separatorColor), width: 0.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("Sangeet AI • Rahul Chaturvedi © 2026. All Rights Reserved.")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .padding(.horizontal)
        .padding(.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Model License Row Helper
struct ModelLicenseRow: View {
    let name: String
    let code: String
    let weights: String
    let status: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 9, weight: .bold))
                Text("Code: \(code) | Weights: \(weights)")
                    .font(.system(size: 7))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(status)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.green)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.green.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 5)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(4)
    }
}

// MARK: - Privacy Tab View
struct PrivacySettingsView: View {
    @AppStorage("SAITelemetryEnabled") private var isTelemetryEnabled = true
    @ObservedObject var telemetryManager = TelemetryManager.shared
    @State private var showViewer = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Privacy & Diagnostic Telemetry")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Share anonymous telemetry data", isOn: $isTelemetryEnabled)
                    .font(.body)
                    .help("Help improve Sangeet by sharing diagnostics. We never collect audio files, names, or identifiers.")
                
                Text("Help improve Sangeet AI by automatically sharing diagnostic logs. Telemetry is opt-out by default, completely anonymous, and never transmits audio content, spectra, or personal identifiers. You can opt out at any time.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
                    .padding(.leading, 18)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Transparency & Data Sovereignty")
                    .font(.subheadline)
                    .fontWeight(.bold)
                
                Text("We believe you should have complete visibility into what is collected. View the raw rolling diagnostic buffer currently stored in memory.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
                
                Button("See what's collected") {
                    showViewer = true
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showViewer) {
            TelemetryViewerSheet(isPresented: $showViewer, telemetryManager: telemetryManager)
        }
    }
}

// MARK: - Telemetry Viewer Sheet
struct TelemetryViewerSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var telemetryManager: TelemetryManager
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Diagnostic Telemetry Logs")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Button("Clear Logs") {
                    telemetryManager.clearLocalHistory()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.top)
            
            Text("Below is the real-time queue of the last 20 events recorded during this session. Logging halts completely if sharing is disabled.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            
            ScrollView {
                if telemetryManager.localEventsBuffer.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "opticaldisc.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                        Text("No telemetry events recorded yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 60)
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(telemetryManager.localEventsBuffer) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(event.eventName)
                                        .font(.system(.caption, design: .monospaced))
                                        .fontWeight(.bold)
                                        .foregroundColor(.orange)
                                    Spacer()
                                    Text(event.formattedTimestamp)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                
                                if !event.properties.isEmpty {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(event.properties.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                            HStack(alignment: .top) {
                                                Text("\(key):")
                                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                                Text(value)
                                                    .font(.system(size: 8, design: .monospaced))
                                                    .foregroundColor(.primary)
                                            }
                                        }
                                    }
                                    .padding(.leading, 8)
                                }
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .frame(height: 240)
            
            Divider()
            
            Button("Close") {
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .padding(.bottom)
        }
        .frame(width: 440)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

#if BETA
struct FeedbackSettingsView: View {
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var category: String = "Bug Report"
    @State private var subject: String = ""
    @State private var message: String = ""
    @State private var includeDiagnostics: Bool = true
    
    @State private var isSubmitting: Bool = false
    @State private var submissionStatus: SubmissionStatus = .idle
    
    private let categories = ["Bug Report", "Audio Quality", "Feature Request", "Other"]
    
    enum SubmissionStatus: Equatable {
        case idle
        case success
        case failure(String)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Beta Feedback")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(RestorationTheme.saffron)
            
            Text("Your feedback is emailed straight to beta@sangeet.app. Sangeet preserves authentic Indian acoustic traits—let us know how our models handle vocal nasality or microtonal pitch slides.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(nil)
            
            if submissionStatus == .success {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(RestorationTheme.neonTeal)
                    
                    Text("Thank you for your feedback!")
                        .font(.system(size: 14, weight: .bold))
                    
                    Text("Our engineers are on it. Your contribution helps preserve Indian musical heritage.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Send Another Message") {
                        resetForm()
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                Form {
                    Section {
                        HStack {
                            Text("Name:")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 60, alignment: .leading)
                            TextField("Your name", text: $name)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                        }
                        
                        HStack {
                            Text("Email:")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 60, alignment: .leading)
                            TextField("your.email@example.com", text: $email)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                        }
                        
                        Picker(selection: $category, label: Text("Topic:").font(.system(size: 11, weight: .bold)).frame(width: 60, alignment: .leading)) {
                            ForEach(categories, id: \.self) { cat in
                                Text(cat).tag(cat).font(.system(size: 11))
                            }
                        }
                        .pickerStyle(.menu)
                        
                        HStack {
                            Text("Subject:")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 60, alignment: .leading)
                            TextField("Brief summary", text: $subject)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                        }
                    }
                    
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Message:")
                                .font(.system(size: 11, weight: .bold))
                            TextEditor(text: $message)
                                .font(.system(size: 11))
                                .frame(height: 80)
                                .cornerRadius(4)
                        }
                    }
                    
                    Section {
                        Toggle(isOn: $includeDiagnostics) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Include system diagnostics")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("App version, macOS build, and machine specifications.")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .formStyle(.grouped)
                .frame(height: 250)
                
                HStack {
                    if case .failure(let error) = submissionStatus {
                        Text(error)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.red)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    if isSubmitting {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 20, height: 20)
                    } else {
                        Button(action: submitFeedback) {
                            Text("Submit Feedback")
                                .fontWeight(.bold)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(RestorationTheme.saffron)
                        .disabled(name.isEmpty || email.isEmpty || message.isEmpty)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
    }
    
    private func resetForm() {
        name = ""
        email = ""
        category = "Bug Report"
        subject = ""
        message = ""
        includeDiagnostics = true
        submissionStatus = .idle
        isSubmitting = false
    }
    
    private func getMacModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
    
    private func submitFeedback() {
        guard !name.isEmpty, !email.isEmpty, !message.isEmpty else { return }
        
        isSubmitting = true
        submissionStatus = .idle
        
        var payload: [String: Any] = [
            "name": name,
            "email": email,
            "category": category,
            "subject": subject.isEmpty ? "Beta Feedback: \(category)" : subject,
            "message": message,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        if includeDiagnostics {
            let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            let totalMemoryGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
            let diagnostics: [String: String] = [
                "app_version": "1.0.0 Beta (Build 1)",
                "macos_version": osVersion,
                "mac_model": getMacModel(),
                "total_ram": "\(totalMemoryGB) GB"
            ]
            payload["diagnostics"] = diagnostics
        }
        
        guard let url = URL(string: "https://feedback.sangeet.app/api/submit") else {
            isSubmitting = false
            submissionStatus = .failure("Internal Error: Invalid Submission URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            isSubmitting = false
            submissionStatus = .failure("Failed to encode payload: \(error.localizedDescription)")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isSubmitting = false
                
                if let error = error {
                    submissionStatus = .failure("Network connection failed: \(error.localizedDescription)")
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    submissionStatus = .failure("Server returned an invalid response.")
                    return
                }
                
                if (200...299).contains(httpResponse.statusCode) {
                    withAnimation {
                        submissionStatus = .success
                    }
                } else {
                    submissionStatus = .failure("Server returned error code: \(httpResponse.statusCode)")
                }
            }
        }.resume()
    }
}
#endif

