import Foundation
import AVFoundation
import AudioEngine

func runDecoderEncoderRoundtrip() throws {
    print("\n--- Starting Validation 1: Decoder/Encoder Roundtrip ---")
    let sampleRate: Double = 48000.0
    let channels: AVAudioChannelCount = 2
    guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false) else {
        throw NSError(domain: "SmokeTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create AVAudioFormat"])
    }
    
    // Generate 1 second of audio (48000 frames)
    let frameCount: AVAudioFrameCount = 48000
    guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        throw NSError(domain: "SmokeTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create srcBuffer"])
    }
    srcBuffer.frameLength = frameCount
    
    // Fill with 440Hz sine wave
    if let floatChannelData = srcBuffer.floatChannelData {
        for channel in 0..<Int(channels) {
            let channelData = floatChannelData[channel]
            for frame in 0..<Int(frameCount) {
                let time = Double(frame) / sampleRate
                channelData[frame] = Float(sin(2.0 * .pi * 440.0 * time))
            }
        }
    }
    
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent("smoke_roundtrip_\(UUID().uuidString).wav")
    
    let encoder = AudioEncoder()
    let decoder = AudioDecoder()
    
    // Encode to temp WAV file
    try encoder.encode(buffer: srcBuffer, to: fileURL)
    print("Wrote synthetic WAV file: \(fileURL.path)")
    
    // Decode back
    let decodedBuffer = try decoder.decode(fileURL: fileURL)
    print("Decoded WAV file successfully. Format: SR=\(decodedBuffer.format.sampleRate), channels=\(decodedBuffer.format.channelCount)")
    
    // Validate assertions
    guard decodedBuffer.format.sampleRate == sampleRate else {
        throw NSError(domain: "SmokeTest", code: 3, userInfo: [NSLocalizedDescriptionKey: "Sample rate mismatch"])
    }
    guard decodedBuffer.format.channelCount == channels else {
        throw NSError(domain: "SmokeTest", code: 4, userInfo: [NSLocalizedDescriptionKey: "Channel count mismatch"])
    }
    guard decodedBuffer.frameLength == frameCount else {
        throw NSError(domain: "SmokeTest", code: 5, userInfo: [NSLocalizedDescriptionKey: "Frame length mismatch"])
    }
    
    if let srcData = srcBuffer.floatChannelData, let destData = decodedBuffer.floatChannelData {
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(frameCount) {
                let diff = abs(destData[channel][frame] - srcData[channel][frame])
                if diff > 1e-4 {
                    throw NSError(domain: "SmokeTest", code: 6, userInfo: [NSLocalizedDescriptionKey: "Signal sample mismatch at ch \(channel) frame \(frame): src=\(srcData[channel][frame]) dest=\(destData[channel][frame])"])
                }
            }
        }
    }
    
    // Cleanup
    try? FileManager.default.removeItem(at: fileURL)
    print("Validation 1 (Decoder/Encoder Roundtrip): PASSED")
}

func runInferenceClientCheck(socketPath: String) async throws {
    print("\n--- Starting Validation 2: Inference Client capabilities check ---")
    
    let launcher = DaemonLauncher()
    try launcher.launch(socketPath: socketPath)
    
    defer {
        launcher.stop()
    }
    
    let client = InferenceClient(socketPath: socketPath)
    
    // Test GetCapabilities
    let caps = try await client.getCapabilities()
    print("Received capabilities from Daemon:")
    print("  Version: \(caps.daemonVersion)")
    print("  Supported Formats: \(caps.supportedAudioFormats)")
    print("  MPS Available: \(caps.mpsAvailable)")
    
    guard caps.daemonVersion == "0.1.0" else {
        throw NSError(domain: "SmokeTest", code: 7, userInfo: [NSLocalizedDescriptionKey: "Unexpected daemon version: \(caps.daemonVersion)"])
    }
    guard caps.supportedAudioFormats.contains("WAV") else {
        throw NSError(domain: "SmokeTest", code: 8, userInfo: [NSLocalizedDescriptionKey: "Supported formats missing WAV"])
    }
    
    // Test ListModels
    let modelList = try await client.listModels()
    print("Loaded Daemon models count: \(modelList.models.count)")
    
    print("Validation 2 (Inference Client capabilities check): PASSED")
}

func runEndToEndRestoration(socketPath: String) async throws {
    print("\n--- Starting Validation 3: End-to-End coordinator restoration ---")
    let tempDir = FileManager.default.temporaryDirectory
    let inputURL = tempDir.appendingPathComponent("smoke_coord_in_\(UUID().uuidString).wav")
    let outputURL = tempDir.appendingPathComponent("smoke_coord_out_\(UUID().uuidString).wav")
    
    // 1. Generate input audio
    let sampleRate: Double = 48000.0
    let channels: AVAudioChannelCount = 2
    guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false) else {
        throw NSError(domain: "SmokeTest", code: 9, userInfo: [NSLocalizedDescriptionKey: "Failed to create AVAudioFormat"])
    }
    
    let frameCount: AVAudioFrameCount = 48000
    guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        throw NSError(domain: "SmokeTest", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to create srcBuffer"])
    }
    srcBuffer.frameLength = frameCount
    
    if let floatChannelData = srcBuffer.floatChannelData {
        for channel in 0..<Int(channels) {
            let channelData = floatChannelData[channel]
            for frame in 0..<Int(frameCount) {
                let time = Double(frame) / sampleRate
                channelData[frame] = Float(sin(2.0 * .pi * 440.0 * time))
            }
        }
    }
    
    let encoder = AudioEncoder()
    try encoder.encode(buffer: srcBuffer, to: inputURL)
    
    // 2. Setup RestorationCoordinator
    let coordinator = RestorationCoordinator(socketPath: socketPath)
    try coordinator.prepare()
    
    defer {
        Task {
            try? await coordinator.shutdown()
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
    }
    
    // 3. Audio Analysis
    let analysis = try await coordinator.analyzeAudio(inputURL: inputURL)
    print("Audio analysis results:")
    print("  Sample Rate: \(analysis.features.sampleRate) Hz")
    print("  Channels: \(analysis.features.channels)")
    print("  Duration: \(analysis.features.durationS) seconds")
    
    guard analysis.features.sampleRate == 48000 else {
        throw NSError(domain: "SmokeTest", code: 11, userInfo: [NSLocalizedDescriptionKey: "Analysis sample rate is not 48000"])
    }
    
    // 4. Restoration invocation
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
    
    print("Starting progressive restoration stream...")
    var eventsReceived = 0
    for try await progress in progressStream {
        eventsReceived += 1
        print("  Progress: \(progress.stageName) -> \(progress.percentComplete)%, elapsed=\(progress.elapsedS)s")
    }
    
    guard eventsReceived > 0 else {
        throw NSError(domain: "SmokeTest", code: 12, userInfo: [NSLocalizedDescriptionKey: "Did not receive any progress events"])
    }
    
    // 5. Decode output WAV and verify identity within -90 dB (1e-4 accuracy)
    let decoder = AudioDecoder()
    let destBuffer = try decoder.decode(fileURL: outputURL)
    print("Restored output format: SR=\(destBuffer.format.sampleRate), channels=\(destBuffer.format.channelCount), frames=\(destBuffer.frameLength)")
    
    guard destBuffer.format.sampleRate == sampleRate else {
        throw NSError(domain: "SmokeTest", code: 13, userInfo: [NSLocalizedDescriptionKey: "Restored sample rate mismatch"])
    }
    guard destBuffer.format.channelCount == channels else {
        throw NSError(domain: "SmokeTest", code: 14, userInfo: [NSLocalizedDescriptionKey: "Restored channel count mismatch"])
    }
    guard destBuffer.frameLength == frameCount else {
        throw NSError(domain: "SmokeTest", code: 15, userInfo: [NSLocalizedDescriptionKey: "Restored frame length mismatch"])
    }
    
    if let srcData = srcBuffer.floatChannelData, let destData = destBuffer.floatChannelData {
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(frameCount) {
                let diff = abs(destData[channel][frame] - srcData[channel][frame])
                if diff > 1e-4 {
                    throw NSError(domain: "SmokeTest", code: 16, userInfo: [NSLocalizedDescriptionKey: "Restored signal mismatch at ch \(channel) frame \(frame)"])
                }
            }
        }
    }
    
    try await coordinator.shutdown()
    print("Validation 3 (End-to-End coordinator restoration): PASSED")
}

@main
struct SmokeRunner {
    static func main() async {
        let tempDir = FileManager.default.temporaryDirectory
        let socketPath = tempDir.appendingPathComponent("sg_sm_\(Int.random(in: 1000...9999)).sock").path
        
        try? FileManager.default.removeItem(atPath: socketPath)
        
        print("==================================================")
        print("SANGEET AUDIO ENGINE - INTEGRATION VALIDATION SUITE")
        print("==================================================")
        
        do {
            // Validation 1: Decoders/Encoders roundtrip
            try runDecoderEncoderRoundtrip()
            
            // Validation 2: Inference Client capabilities
            try await runInferenceClientCheck(socketPath: socketPath)
            
            // Validation 3: End-to-End Restoration
            try await runEndToEndRestoration(socketPath: socketPath)
            
            print("\n==================================================")
            print("🎉 ALL SANGEET INTEGRATION AND UNIT VALIDATIONS PASSED SUCCESSFUL! 🎉")
            print("==================================================")
            exit(0)
        } catch {
            print("\n❌ VALIDATION FAILED ❌")
            print("Error details: \(error.localizedDescription)")
            print("==================================================")
            exit(1)
        }
    }
}
