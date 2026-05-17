import Foundation
import GRPC
import NIO

public final class RestorationCoordinator {
    private let socketPath: String
    private let launcher: DaemonLauncher
    private var client: InferenceClient?
    
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
        targetLoudnessLUFS: Double? = nil
    ) -> AsyncStream<SangeetV1RestorationProgress> {
        return AsyncStream { continuation in
            Task {
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
                    req.outputPath = outputURL.path
                    req.recipe = recipe
                    if let loudness = targetLoudnessLUFS {
                        req.targetLoudnessLufs = loudness
                    }
                    req.outputFormat = outputURL.pathExtension.uppercased()
                    
                    let stream = client.startRestoration(request: req)
                    
                    for try await progress in stream {
                        continuation.yield(progress)
                    }
                    
                    continuation.finish()
                } catch {
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
}
