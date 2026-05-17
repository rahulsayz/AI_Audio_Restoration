import Foundation
import Combine
import SwiftUI
import AVFoundation
import AudioEngine

@MainActor
public final class RestorationViewModel: ObservableObject {
    // Input File state
    @Published public private(set) var loadedFileURL: URL? = nil
    @Published public private(set) var filename: String = ""
    @Published public private(set) var durationString: String = ""
    @Published public private(set) var sampleRateString: String = ""
    
    // Audio Analysis state
    @Published public private(set) var isAnalyzing: Bool = false
    @Published public private(set) var analysisResult: SangeetV1AnalysisResult? = nil
    
    // Processing state
    @Published public private(set) var isProcessing: Bool = false
    @Published public private(set) var progress: Double = 0.0
    @Published public private(set) var currentStage: String = ""
    @Published public private(set) var errorMessage: String? = nil
    
    // Output state
    @Published public private(set) var outputFileURL: URL? = nil
    @Published public private(set) var restorationComplete: Bool = false
    @Published public var selectedPreset: MasteringChain.Preset = .streaming
    @Published public private(set) var measuredLUFS: Double? = nil
    @Published public private(set) var measuredTruePeak: Double? = nil
    
    // Library persistence state
    @Published public private(set) var libraryEntries: [LibraryEntry] = []
    @Published public var selectedEntryID: UUID? = nil
    
    // A/B Compare Player State
    @Published public var playerIsPlaying: Bool = false
    @Published public var playerOriginalActive: Bool = false
    @Published public var playerVolumeMatchActive: Bool = false
    @Published public var playerProgress: Double = 0.0
    @Published public var playerTotalDuration: Double = 0.0
    @Published public var playerCurrentTime: Double = 0.0
    @Published public var isPlayerPreparing: Bool = false
    @Published public var originalLUFSVal: Double? = nil
    @Published public var restoredLUFSVal: Double? = nil
    
    private var player: SynchronizedAudioPlayer? = nil
    private var database: LibraryDatabase? = nil
    
    // Coordinator & Task
    private let coordinator: RestorationCoordinator
    private var restorationTask: Task<Void, Never>? = nil
    
    public init(coordinator: RestorationCoordinator = RestorationCoordinator()) {
        self.coordinator = coordinator
        setupDatabase()
        loadLibrary()
    }
    
    private func setupDatabase() {
        do {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let storeURL = appSupport.appendingPathComponent("SangeetAI").appendingPathComponent("library.sqlite")
            self.database = try LibraryDatabase(storeURL: storeURL)
        } catch {
            print("[RestorationViewModel] Database setup failed: \(error.localizedDescription)")
        }
    }
    
    public func loadLibrary() {
        guard let database = database else { return }
        do {
            self.libraryEntries = try database.fetchAllEntries()
        } catch {
            print("[RestorationViewModel] Failed to fetch library entries: \(error.localizedDescription)")
        }
    }
    
    /// Loads an audio file and extracts basic metadata locally using AVFoundation to keep UI fast
    /// - Parameter url: The local URL of the audio file to inspect.
    public func loadFile(url: URL) {
        // Clear previous state
        resetState()
        
        // Validate file type
        let supportedExtensions = ["wav", "flac", "mp3", "m4a"]
        guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
            self.errorMessage = "Sangeet only supports WAV, FLAC, MP3, and M4A files. Please import a supported format."
            return
        }
        
        // Validate file existence
        guard FileManager.default.fileExists(atPath: url.path) else {
            self.errorMessage = "Sangeet couldn't find the audio file at the specified path. Please make sure the file exists and try again."
            return
        }
        
        self.loadedFileURL = url
        self.filename = url.lastPathComponent
        
        let accessScoped = url.startAccessingSecurityScopedResource()
        defer {
            if accessScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            // Local metadata parsing via AVAudioFile (AVFoundation) to maintain instant UI responses
            let file = try AVAudioFile(forReading: url)
            let format = file.fileFormat
            let sampleRate = format.sampleRate
            let duration = Double(file.length) / sampleRate
            
            self.sampleRateString = String(format: "%.1f kHz", sampleRate / 1000.0)
            
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            self.durationString = String(format: "%d:%02d", minutes, seconds)
        } catch {
            // Fallback: file may be encoded differently (e.g. some compressed MP3/M4A), show simplified info
            self.sampleRateString = "-- kHz"
            self.durationString = "--:--"
            print("[RestorationViewModel] Local AVFoundation metadata read failed: \(error.localizedDescription)")
        }
        
        // Asynchronously trigger AnalyzeAudio daemon RPC immediately when the file is dropped
        self.isAnalyzing = true
        self.analysisResult = nil
        
        let daemonPath = ProcessInfo.processInfo.environment["SANGEET_DAEMON_PATH"]
        Task {
            let innerAccessScoped = url.startAccessingSecurityScopedResource()
            defer {
                if innerAccessScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                try coordinator.prepare(daemonPath: daemonPath)
                let result = try await coordinator.analyzeAudio(inputURL: url)
                self.analysisResult = result
                self.isAnalyzing = false
            } catch {
                print("[RestorationViewModel] Audio analysis daemon RPC failed: \(error.localizedDescription)")
                self.errorMessage = "Sangeet couldn't analyze the audio characteristics: \(error.localizedDescription). You can still proceed with restoration using default settings."
                self.isAnalyzing = false
            }
        }
    }
    
    #if DEBUG
    /// Injects custom states for SwiftUI preview rendering without touching the disk or daemon
    public func injectMockStateForPreview(
        filename: String,
        sampleRate: String,
        duration: String,
        isAnalyzing: Bool = false,
        analysisResult: SangeetV1AnalysisResult? = nil,
        isProcessing: Bool = false,
        progress: Double = 0.0,
        currentStage: String = "",
        errorMessage: String? = nil,
        restorationComplete: Bool = false
    ) {
        self.loadedFileURL = URL(fileURLWithPath: "/Users/mock/Music/\(filename)")
        self.filename = filename
        self.sampleRateString = sampleRate
        self.durationString = duration
        self.isAnalyzing = isAnalyzing
        self.analysisResult = analysisResult
        self.isProcessing = isProcessing
        self.progress = progress
        self.currentStage = currentStage
        self.errorMessage = errorMessage
        self.restorationComplete = restorationComplete
    }
    #endif
    
    /// Triggers the restoration pipeline via the RestorationCoordinator
    public func startRestoration() {
        guard let inputURL = loadedFileURL else {
            self.errorMessage = "Sangeet couldn't start restoration because no file was loaded. Please drop an audio file first."
            return
        }
        
        self.isProcessing = true
        self.progress = 0.0
        self.currentStage = "Launching audio engine..."
        self.errorMessage = nil
        self.restorationComplete = false
        self.outputFileURL = nil
        self.measuredLUFS = nil
        self.measuredTruePeak = nil
        
        // Determine output file path (e.g. sibling with -restored suffix)
        let fileExtension = inputURL.pathExtension
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let outputName = "\(baseName)-restored.\(fileExtension)"
        let outputURL = inputURL.deletingLastPathComponent().appendingPathComponent(outputName)
        self.outputFileURL = outputURL
        
        // Read daemon path from environment variable for development, as per requirements
        let daemonPath = ProcessInfo.processInfo.environment["SANGEET_DAEMON_PATH"]
        if let path = daemonPath {
            print("[RestorationViewModel] Using SANGEET_DAEMON_PATH: \(path)")
        }
        
        // Use recipe from analysis result, with a conservative deep_filter_net fallback if analysis failed/skipped
        let recipe: SangeetV1RestorationRecipe
        if let analysis = self.analysisResult {
            recipe = analysis.suggestedRecipe
        } else {
            var defaultRecipe = SangeetV1RestorationRecipe()
            var denoiseInvocation = SangeetV1StageInvocation()
            denoiseInvocation.stageName = "deep_filter_net"
            denoiseInvocation.strength = 0.5
            defaultRecipe.stages = [denoiseInvocation]
            recipe = defaultRecipe
        }
        
        restorationTask = Task {
            do {
                // Ensure coordinator is prepared (launches daemon internally)
                try coordinator.prepare(daemonPath: daemonPath)
                
                self.currentStage = "Analyzing audio signal..."
                let stream = coordinator.restore(
                    inputURL: inputURL,
                    outputURL: outputURL,
                    recipe: recipe,
                    preset: selectedPreset
                )
                
                for try await progressEvent in stream {
                    // Update state on MainActor
                    self.progress = progressEvent.hasPercentComplete ? Double(progressEvent.percentComplete) / 100.0 : 0.0
                    
                    if !progressEvent.stageName.isEmpty {
                        self.currentStage = progressEvent.stageName.replacingOccurrences(of: "_", with: " ").capitalized
                    }
                }
                
                // Finalize restoration complete state
                self.measuredLUFS = coordinator.lastMeasuredLUFS
                self.measuredTruePeak = coordinator.lastMeasuredTruePeak
                
                self.progress = 1.0
                self.currentStage = "Restoration complete"
                self.restorationComplete = true
                self.isProcessing = false
                
                // Persist completed restoration to library database
                self.saveCurrentToLibrary()
                self.setupPlayer()
            } catch {
                // User-friendly error message format
                self.errorMessage = "Sangeet couldn't complete the restoration. There was an internal issue communicating with the background daemon: \(error.localizedDescription). You can try restarting Sangeet or checking your environment variables."
                self.isProcessing = false
                self.currentStage = ""
            }
        }
    }
    
    /// Cancels the active restoration job
    public func cancelRestoration() {
        restorationTask?.cancel()
        restorationTask = nil
        self.isProcessing = false
        self.progress = 0.0
        self.currentStage = "Cancelled"
    }
    
    /// Opens the output folder in Finder and highlights the completed file
    public func showInFinder() {
        guard let outputURL = outputFileURL else { return }
        NSWorkspace.shared.selectFile(outputURL.path, inFileViewerRootedAtPath: outputURL.deletingLastPathComponent().path)
    }
    
    /// Clears and resets all view-state variables back to initial loaded state
    public func clearFile() {
        resetState()
    }
    
    private func resetState() {
        self.loadedFileURL = nil
        self.filename = ""
        self.durationString = ""
        self.sampleRateString = ""
        self.isProcessing = false
        self.progress = 0.0
        self.currentStage = ""
        self.errorMessage = nil
        self.outputFileURL = nil
        self.restorationComplete = false
        self.isAnalyzing = false
        self.analysisResult = nil
        self.measuredLUFS = nil
        self.measuredTruePeak = nil
        self.selectedEntryID = nil
        cleanupPlayer()
        restorationTask?.cancel()
        restorationTask = nil
    }
    
    private func saveCurrentToLibrary() {
        guard let database = database,
              let loadedURL = loadedFileURL,
              let analysis = analysisResult else { return }
        
        let originalPath = loadedURL.path
        let restoredPath = outputFileURL?.path
        let filename = self.filename
        let duration = self.durationString
        let sampleRate = self.sampleRateString
        let presetName = self.selectedPreset == .streaming ? "streaming" : "remaster"
        let lufs = self.measuredLUFS
        let tp = self.measuredTruePeak
        
        Task {
            // Compute waveform amplitudes in a separate background thread
            let amplitudes = WaveformGenerator.generateAmplitudes(from: loadedURL, targetPoints: 40)
            
            // Serialize to Data
            let pointsData = (try? JSONEncoder().encode(amplitudes)) ?? Data()
            let analysisData = (try? analysis.serializedData()) ?? Data()
            
            let entry = LibraryEntry(
                filename: filename,
                originalPath: originalPath,
                restoredPath: restoredPath,
                durationString: duration,
                sampleRateString: sampleRate,
                preset: presetName,
                measuredLUFS: lufs,
                measuredTruePeak: tp,
                analysisResultData: analysisData,
                waveformPointsData: pointsData
            )
            
            do {
                try database.saveEntry(entry)
                // Reload on MainActor
                await MainActor.run {
                    self.loadLibrary()
                }
            } catch {
                print("[RestorationViewModel] Failed to save restoration: \(error.localizedDescription)")
            }
        }
    }
    
    public func deleteEntry(id: UUID) {
        guard let database = database else { return }
        do {
            try database.deleteEntry(id: id)
            loadLibrary()
            if selectedEntryID == id {
                clearFile()
            }
        } catch {
            print("[RestorationViewModel] Failed to delete library entry: \(error.localizedDescription)")
        }
    }
    
    public func selectEntry(_ entry: LibraryEntry) {
        // Clear previous state first
        resetState()
        
        let fileURL = URL(fileURLWithPath: entry.originalPath)
        
        // Graceful handle for orphaned files (missing original file)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            self.errorMessage = "Sangeet couldn't find the original file at \(entry.originalPath). It may have been moved or deleted."
            return
        }
        
        self.selectedEntryID = entry.id
        self.loadedFileURL = fileURL
        self.filename = entry.filename
        self.durationString = entry.durationString
        self.sampleRateString = entry.sampleRateString
        self.selectedPreset = entry.preset == "streaming" ? .streaming : .remaster
        self.measuredLUFS = entry.measuredLUFS
        self.measuredTruePeak = entry.measuredTruePeak
        
        if let restoredPath = entry.restoredPath {
            self.outputFileURL = URL(fileURLWithPath: restoredPath)
            self.restorationComplete = true
            self.setupPlayer()
        }
        
        // Deserialize the protobuf analysis result from binary blob
        do {
            let result = try SangeetV1AnalysisResult(serializedData: entry.analysisResultData)
            self.analysisResult = result
        } catch {
            print("[RestorationViewModel] Failed to deserialize analysis result: \(error.localizedDescription)")
            // Fallback: trigger fresh analysis if the binary is corrupted
            loadFile(url: fileURL)
        }
    }
    
    public func setupPlayer() {
        guard let originalURL = loadedFileURL,
              let restoredURL = outputFileURL,
              restorationComplete else { return }
              
        cleanupPlayer()
        isPlayerPreparing = true
        
        Task {
            do {
                let p = SynchronizedAudioPlayer()
                let targetLUFS = measuredLUFS ?? -14.0
                try await p.prepare(originalURL: originalURL, restoredURL: restoredURL, restoredLUFS: targetLUFS)
                
                await MainActor.run {
                    self.player = p
                    self.originalLUFSVal = p.originalLUFS
                    self.restoredLUFSVal = p.restoredLUFS
                    self.playerOriginalActive = p.isOriginalActive
                    self.playerVolumeMatchActive = p.isVolumeMatchEnabled
                    
                    p.onTimeUpdate = { [weak self] current, total in
                        guard let self = self else { return }
                        Task { @MainActor in
                            self.playerCurrentTime = current
                            self.playerTotalDuration = total
                            self.playerProgress = total > 0 ? (current / total) : 0.0
                        }
                    }
                    
                    self.isPlayerPreparing = false
                }
            } catch {
                print("[RestorationViewModel] Failed to prepare SynchronizedAudioPlayer: \(error.localizedDescription)")
                await MainActor.run {
                    self.isPlayerPreparing = false
                }
            }
        }
    }
    
    public func cleanupPlayer() {
        player?.stop()
        player = nil
        playerIsPlaying = false
        playerOriginalActive = false
        playerVolumeMatchActive = false
        playerProgress = 0.0
        playerTotalDuration = 0.0
        playerCurrentTime = 0.0
        isPlayerPreparing = false
        originalLUFSVal = nil
        restoredLUFSVal = nil
    }
    
    public func togglePlayback() {
        guard let player = player else { return }
        if player.isPlaying {
            player.pause()
            playerIsPlaying = false
        } else {
            player.play()
            playerIsPlaying = true
        }
    }
    
    public func toggleSource() {
        guard let player = player else { return }
        let newActive = !player.isOriginalActive
        player.setOriginalActive(newActive)
        playerOriginalActive = newActive
    }
    
    public func toggleVolumeMatch() {
        guard let player = player else { return }
        let newMatch = !player.isVolumeMatchEnabled
        player.setVolumeMatchEnabled(newMatch)
        playerVolumeMatchActive = newMatch
    }
    
    public func seekPlayer(toPercent percent: Double) {
        player?.seek(toPercent: percent)
    }
}
