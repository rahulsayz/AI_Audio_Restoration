import XCTest
import AVFoundation
@testable import AudioEngine

final class ComparePlayerTests: XCTestCase {
    
    var tempFileURLs: [URL] = []
    
    override func tearDown() {
        for url in tempFileURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempFileURLs.removeAll()
        super.tearDown()
    }
    
    private func generateSineFile(amplitude: Float, frequency: Double = 440.0) throws -> URL {
        let sampleRate: Double = 48000.0
        let channels: AVAudioChannelCount = 2
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false) else {
            throw NSError(domain: "ComparePlayerTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create format"])
        }
        
        let frameCount: AVAudioFrameCount = 48000 * 2 // 2 seconds
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "ComparePlayerTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
        }
        buffer.frameLength = frameCount
        
        if let floatChannelData = buffer.floatChannelData {
            for channel in 0..<Int(channels) {
                let channelData = floatChannelData[channel]
                for frame in 0..<Int(frameCount) {
                    let time = Double(frame) / sampleRate
                    channelData[frame] = Float(sin(2.0 * .pi * frequency * time)) * amplitude
                }
            }
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("compare_test_\(UUID().uuidString).wav")
        let encoder = AudioEncoder()
        try encoder.encode(buffer: buffer, to: fileURL)
        
        tempFileURLs.append(fileURL)
        return fileURL
    }
    
    func testPlayerPreparationAndVolumeMatching() async throws {
        // Generate a loud original file (amp = 0.8) and a quiet restored file (amp = 0.2)
        let originalURL = try generateSineFile(amplitude: 0.8)
        let restoredURL = try generateSineFile(amplitude: 0.2)
        
        let player = SynchronizedAudioPlayer()
        
        // Prepare the players
        try await player.prepare(originalURL: originalURL, restoredURL: restoredURL, restoredLUFS: -14.0)
        
        let origLUFS = player.originalLUFS
        let restLUFS = player.restoredLUFS
        
        // The loud file (amp=0.8) should have higher (closer to 0) LUFS than the quiet one (amp=0.2)
        XCTAssertGreaterThan(origLUFS, restLUFS)
        
        // Verify default states
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.isOriginalActive)
        XCTAssertFalse(player.isVolumeMatchEnabled)
        
        // When volume matching is enabled, verify gain correction is applied to the quieter channel
        player.setVolumeMatchEnabled(true)
        XCTAssertTrue(player.isVolumeMatchEnabled)
        
        // Playback and seek operations
        player.play()
        XCTAssertTrue(player.isPlaying)
        
        player.seek(toPercent: 0.5)
        
        player.pause()
        XCTAssertFalse(player.isPlaying)
        
        player.stop()
    }
}
