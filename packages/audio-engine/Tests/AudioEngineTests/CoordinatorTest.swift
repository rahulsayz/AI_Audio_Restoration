import XCTest
import AVFoundation
@testable import AudioEngine

final class CoordinatorTest: XCTestCase {
    func testCoordinatorEndToEnd() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let socketPath = tempDir.appendingPathComponent("sg_coord_\(Int.random(in: 1000...9999)).sock").path
        let inputURL = tempDir.appendingPathComponent("coord_input_\(UUID().uuidString).wav")
        let outputURL = tempDir.appendingPathComponent("coord_output_\(UUID().uuidString).wav")
        
        // Cleanup stale test resources
        for path in [socketPath, inputURL.path, outputURL.path] {
            try? FileManager.default.removeItem(atPath: path)
        }
        
        // 1. Generate 1 second of synthetic stereo audio (48kHz, float32)
        let sampleRate: Double = 48000.0
        let channels: AVAudioChannelCount = 2
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false) else {
            XCTFail("Failed to create AVAudioFormat")
            return
        }
        
        let frameCount: AVAudioFrameCount = 48000
        guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            XCTFail("Failed to create srcBuffer")
            return
        }
        srcBuffer.frameLength = frameCount
        
        // Fill with a nice 440Hz sine wave
        if let floatChannelData = srcBuffer.floatChannelData {
            for ch in 0..<Int(channels) {
                let channelData = floatChannelData[ch]
                for frame in 0..<Int(frameCount) {
                    let time = Double(frame) / sampleRate
                    channelData[frame] = Float(sin(2.0 * .pi * 440.0 * time))
                }
            }
        }
        
        let encoder = AudioEncoder()
        try encoder.encode(buffer: srcBuffer, to: inputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: inputURL.path))
        
        // 2. Initialize and prepare RestorationCoordinator
        let coordinator = RestorationCoordinator(socketPath: socketPath)
        do {
            try coordinator.prepare()
        } catch {
            XCTFail("Failed to prepare coordinator: \(error.localizedDescription)")
            return
        }
        
        defer {
            // Force shutdown and cleanup
            Task {
                try? await coordinator.shutdown()
                try? FileManager.default.removeItem(atPath: socketPath)
                try? FileManager.default.removeItem(at: inputURL)
                try? FileManager.default.removeItem(at: outputURL)
            }
        }
        
        // 3. Test Audio Analysis RPC
        let analysis = try await coordinator.analyzeAudio(inputURL: inputURL)
        XCTAssertEqual(analysis.features.sampleRate, 48000)
        XCTAssertEqual(analysis.features.channels, 2)
        XCTAssertEqual(analysis.features.durationS, 1.0, accuracy: 0.1)
        
        // 4. Trigger restoration using the passthrough stage
        var recipe = SangeetV1RestorationRecipe()
        var passthroughStage = SangeetV1StageInvocation()
        passthroughStage.stageName = "passthrough"
        passthroughStage.strength = 1.0
        recipe.stages.append(passthroughStage)
        
        let progressStream = coordinator.restore(
            inputURL: inputURL,
            outputURL: outputURL,
            recipe: recipe
        )
        
        var progressEvents: [SangeetV1RestorationProgress] = []
        for try await progress in progressStream {
            progressEvents.append(progress)
            print("[CoordinatorTest Progress] Stage: \(progress.stageName), complete: \(progress.percentComplete)%")
        }
        
        XCTAssertFalse(progressEvents.isEmpty, "Should have received progress updates from the daemon.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        
        // 5. Decode output WAV and assert signal match within -90 dB (1e-4 accuracy)
        let decoder = AudioDecoder()
        let destBuffer = try decoder.decode(fileURL: outputURL)
        
        XCTAssertEqual(destBuffer.format.sampleRate, sampleRate)
        XCTAssertEqual(destBuffer.format.channelCount, channels)
        XCTAssertEqual(destBuffer.frameLength, frameCount)
        
        if let srcData = srcBuffer.floatChannelData, let destData = destBuffer.floatChannelData {
            for ch in 0..<Int(channels) {
                for frame in 0..<Int(frameCount) {
                    XCTAssertEqual(destData[ch][frame], srcData[ch][frame], accuracy: 1e-4)
                }
            }
        }
        
        // 6. Graceful shutdown
        try await coordinator.shutdown()
    }
}
