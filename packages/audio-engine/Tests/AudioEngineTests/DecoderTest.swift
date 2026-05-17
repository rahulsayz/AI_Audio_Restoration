import XCTest
import AVFoundation
@testable import AudioEngine

final class DecoderTest: XCTestCase {
    func testSyntheticWavRoundtrip() throws {
        let sampleRate: Double = 48000.0
        let channels: AVAudioChannelCount = 2
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false) else {
            XCTFail("Failed to create AVAudioFormat")
            return
        }
        
        // Generate 1 second of audio (48000 frames)
        let frameCount: AVAudioFrameCount = 48000
        guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            XCTFail("Failed to create srcBuffer")
            return
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
        
        // Setup temp URLs
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("synthetic_test_\(UUID().uuidString).wav")
        
        let encoder = AudioEncoder()
        let decoder = AudioDecoder()
        
        // Write the buffer using the encoder
        try encoder.encode(buffer: srcBuffer, to: fileURL)
        
        // Read it using the decoder
        let decodedBuffer = try decoder.decode(fileURL: fileURL)
        
        // Verify structure
        XCTAssertEqual(decodedBuffer.format.sampleRate, sampleRate)
        XCTAssertEqual(decodedBuffer.format.channelCount, channels)
        XCTAssertEqual(decodedBuffer.frameLength, frameCount)
        
        // Verify content
        if let srcData = srcBuffer.floatChannelData, let destData = decodedBuffer.floatChannelData {
            for channel in 0..<Int(channels) {
                for frame in 0..<Int(frameCount) {
                    XCTAssertEqual(destData[channel][frame], srcData[channel][frame], accuracy: 1e-4)
                }
            }
        }
        
        // Cleanup
        try? FileManager.default.removeItem(at: fileURL)
    }
}
