import Foundation
import AVFoundation

public final class AudioEncoder {
    public init() {}
    
    /// Encodes and writes the provided AVAudioPCMBuffer to a file URL.
    /// The target format is automatically determined from the file URL's path extension.
    /// - Parameters:
    ///   - buffer: The source AVAudioPCMBuffer.
    ///   - fileURL: The target local file URL.
    public func encode(buffer: AVAudioPCMBuffer, to fileURL: URL) throws {
        let ext = fileURL.pathExtension.lowercased()
        let format = buffer.format
        
        var settings: [String: Any] = [:]
        
        switch ext {
        case "wav":
            // 32-bit Floating Point PCM WAV
            settings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        case "flac":
            // Native FLAC Compression
            settings = [
                AVFormatIDKey: kAudioFormatFLAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount
            ]
        case "m4a", "aac":
            // 256kbps High-Quality AAC
            settings = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderBitRateKey: 256_000
            ]
        case "mp3":
            throw AudioEngineError.encodeFailed(
                "MP3 encoding is not natively supported by macOS AVFoundation. Please select WAV, FLAC, or M4A (AAC) instead."
            )
        default:
            throw AudioEngineError.encodeFailed("Unsupported audio format extension: .\(ext).")
        }
        
        let file: AVAudioFile
        do {
            file = try AVAudioFile(
                forWriting: fileURL,
                settings: settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw AudioEngineError.encodeFailed("Could not initialize target file writer: \(error.localizedDescription)")
        }
        
        do {
            try file.write(from: buffer)
        } catch {
            throw AudioEngineError.encodeFailed("Failed to encode/write buffer: \(error.localizedDescription)")
        }
    }
}
