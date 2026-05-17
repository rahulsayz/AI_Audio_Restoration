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
    
    // Coordinator & Task
    private let coordinator: RestorationCoordinator
    private var restorationTask: Task<Void, Never>? = nil
    
    public init(coordinator: RestorationCoordinator = RestorationCoordinator()) {
        self.coordinator = coordinator
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
        
        self.loadedFileURL = url
        self.filename = url.lastPathComponent
        
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
                    targetLoudnessLUFS: -14.0 // Standard streaming target
                )
                
                for try await progressEvent in stream {
                    // Update state on MainActor
                    self.progress = progressEvent.hasPercentComplete ? Double(progressEvent.percentComplete) / 100.0 : 0.0
                    
                    if !progressEvent.stageName.isEmpty {
                        self.currentStage = progressEvent.stageName.replacingOccurrences(of: "_", with: " ").capitalized
                    }
                }
                
                // Finalize restoration complete state
                self.progress = 1.0
                self.currentStage = "Restoration complete"
                self.restorationComplete = true
                self.isProcessing = false
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
        restorationTask?.cancel()
        restorationTask = nil
    }
}
