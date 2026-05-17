import SwiftUI
import UniformTypeIdentifiers

/// Native macOS Sangeet AI Settings Panel View
public struct SettingsView: View {
    private enum Tab: Hashable {
        case general
        case audio
        case storage
        case about
    }
    
    @State private var activeTab: Tab = .general
    
    public init() {}
    
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
            
            AboutSettingsView()
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
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
            
            Spacer()
        }
        .padding()
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
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.house.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .foregroundColor(.orange)
                
            Text("Sangeet AI")
                .font(.system(size: 18, weight: .bold, design: .rounded))
            
            Text("Version 1.0.0 (Build 1)")
                .font(.caption)
                .foregroundColor(.secondary)
            
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
                .frame(height: 120)
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
