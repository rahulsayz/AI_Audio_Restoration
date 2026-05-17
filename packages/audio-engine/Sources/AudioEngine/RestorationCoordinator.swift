import Foundation
import GRPC
import NIO
import AVFoundation

public final class RestorationCoordinator {
    private let socketPath: String
    private let launcher: DaemonLauncher
    private var client: InferenceClient?
    
    public var lastMeasuredLUFS: Double? = nil
    public var lastMeasuredTruePeak: Double? = nil
    
    public init(socketPath: String? = nil) {
        if let customPath = socketPath {
            self.socketPath = customPath
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let sangeetDir = appSupport.appendingPathComponent("SangeetAI")
            self.socketPath = sangeetDir.appendingPathComponent("inference.sock").path
        }
        self.launcher = DaemonLauncher()
    }
    
    /// Prepares the restoration pipeline, launching the daemon if needed and setting up the client.
    /// - Parameter daemonPath: Optional direct path to compiled daemon binary.
    public func prepare(daemonPath: String? = nil) throws {
        guard client == nil else { return }
        
        let socketURL = URL(fileURLWithPath: socketPath)
        let parentDir = socketURL.deletingLastPathComponent()
        
        do {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        } catch {
            throw AudioEngineError.daemonLaunchFailed(
                "Could not create Application Support directories: \(error.localizedDescription)"
            )
        }
        
        // Check if an existing daemon is already connectable to avoid redundant launches/socket unlinks
        if launcher.isSocketConnectable(path: socketPath) {
            print("[RestorationCoordinator] Connectable daemon is already running. Reusing existing instance.")
            self.client = InferenceClient(socketPath: socketPath)
            return
        }
        
        // Launch daemon process
        try launcher.launch(daemonPath: daemonPath, socketPath: socketPath)
        
        // Initialize gRPC connection
        self.client = InferenceClient(socketPath: socketPath)
    }
    
    /// Executes analysis on a target audio file.
    public func analyzeAudio(inputURL: URL) async throws -> SangeetV1AnalysisResult {
        if client == nil {
            try prepare()
        }
        
        guard let client = self.client else {
            throw AudioEngineError.connectionFailed("Restoration daemon client is not initialized.")
        }
        
        do {
            return try await client.analyzeAudio(inputPath: inputURL.path)
        } catch {
            throw AudioEngineError.restorationFailed("Audio analysis failed: \(error.localizedDescription)")
        }
    }
    
    /// Triggers progressive restoration streaming progress events.
    public func restore(
        inputURL: URL,
        outputURL: URL,
        recipe: SangeetV1RestorationRecipe,
        preset: MasteringChain.Preset = .streaming
    ) -> AsyncStream<SangeetV1RestorationProgress> {
        return AsyncStream { continuation in
            Task {
                // Ensure coordinator has an isolated temp location for intermediate wav
                let tempRestoredURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".wav")
                
                defer {
                    // Always clean up the intermediate unmastered WAV file
                    try? FileManager.default.removeItem(at: tempRestoredURL)
                }
                
                do {
                    if self.client == nil {
                        try prepare()
                    }
                    
                    guard let client = self.client else {
                        continuation.finish()
                        return
                    }
                    
                    var req = SangeetV1RestorationRequest()
                    req.inputPath = inputURL.path
                    req.outputPath = tempRestoredURL.path
                    req.recipe = recipe
                    req.outputFormat = "WAV"
                    
                    let stream = client.startRestoration(request: req)
                    
                    for try await progress in stream {
                        continuation.yield(progress)
                    }
                    
                    // Yield a progress event indicating we are doing native mastering
                    var masteringProgress = SangeetV1RestorationProgress()
                    masteringProgress.stageName = "native_mastering"
                    masteringProgress.percentComplete = 95.0
                    continuation.yield(masteringProgress)
                    
                    // Read the daemon's output file
                    let decoder = AudioDecoder()
                    let buffer = try decoder.decode(fileURL: tempRestoredURL)
                    
                    // Convert buffer to channels
                    let channels = RestorationCoordinator.bufferToChannels(buffer: buffer)
                    
                    // Apply MasteringChain at the user-selected preset
                    let chain = MasteringChain()
                    let masteredChannels = chain.process(channels: channels, preset: preset)
                    
                    // Measure final metrics
                    let lufsMeter = LUFSMeter()
                    let tpDetector = TruePeakDetector()
                    
                    let finalLUFS = lufsMeter.analyzeLoudness(channels: masteredChannels)
                    let finalTP = Double(tpDetector.detectPeakdBTP(channels: masteredChannels))
                    
                    self.lastMeasuredLUFS = finalLUFS
                    self.lastMeasuredTruePeak = finalTP
                    
                    // Convert channels back to buffer
                    guard let outputFormat = AVAudioFormat(
                        commonFormat: .pcmFormatFloat32,
                        sampleRate: buffer.format.sampleRate,
                        channels: buffer.format.channelCount,
                        interleaved: false
                    ) else {
                        throw AudioEngineError.encodeFailed("Could not create output AVAudioFormat.")
                    }
                    
                    guard let outputBuffer = RestorationCoordinator.channelsToBuffer(channels: masteredChannels, format: outputFormat) else {
                        throw AudioEngineError.encodeFailed("Could not convert mastered channels to output buffer.")
                    }
                    
                    // Write the final output
                    let encoder = AudioEncoder()
                    try encoder.encode(buffer: outputBuffer, to: outputURL)
                    
                    // Yield completion progress
                    var finalProgress = SangeetV1RestorationProgress()
                    finalProgress.stageName = "mastering_complete"
                    finalProgress.percentComplete = 100.0
                    continuation.yield(finalProgress)
                    
                    continuation.finish()
                } catch {
                    print("[RestorationCoordinator] Error during native mastering flow: \(error.localizedDescription)")
                    continuation.finish()
                }
            }
        }
    }
    
    /// Cancels a running restoration job.
    public func cancel(jobId: String) async throws {
        guard let client = client else { return }
        try await client.cancelJob(jobId: jobId)
    }
    
    /// Shuts down the restoration daemon cleanly by sending the Shutdown RPC and terminating the process after 5 seconds.
    public func shutdown() async throws {
        if let client = client {
            do {
                try await client.shutdown()
            } catch {
                print("[RestorationCoordinator] Shutdown RPC failed: \(error.localizedDescription)")
            }
        }
        launcher.stop()
        self.client = nil
    }
    
    // Helper to convert AVAudioPCMBuffer to [[Float]] channels-first array
    internal static func bufferToChannels(buffer: AVAudioPCMBuffer) -> [[Float]] {
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        var channels: [[Float]] = []
        
        guard let floatPointerArray = buffer.floatChannelData else {
            return []
        }
        
        for c in 0..<channelCount {
            let channelPointer = floatPointerArray[c]
            let channelArray = Array(UnsafeBufferPointer(start: channelPointer, count: frameLength))
            channels.append(channelArray)
        }
        return channels
    }
    
    // Helper to convert [[Float]] channels-first array to AVAudioPCMBuffer
    internal static func channelsToBuffer(channels: [[Float]], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let channelCount = UInt32(channels.count)
        let frameLength = UInt32(channels[0].count)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
            return nil
        }
        
        buffer.frameLength = frameLength
        
        guard let floatPointerArray = buffer.floatChannelData else {
            return nil
        }
        
        for c in 0..<Int(channelCount) {
            let channelPointer = floatPointerArray[c]
            let channelArray = channels[c]
            channelArray.withUnsafeBufferPointer { srcPtr in
                channelPointer.initialize(from: srcPtr.baseAddress!, count: Int(frameLength))
            }
        }
        
        return buffer
    }
}
