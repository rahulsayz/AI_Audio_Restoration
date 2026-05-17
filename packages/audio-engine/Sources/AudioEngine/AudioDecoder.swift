import Foundation
import AVFoundation

public final class AudioDecoder {
    public init() {}
    
    /// Decodes any supported audio format (WAV, FLAC, MP3, M4A/AAC) into an AVAudioPCMBuffer.
    /// The decoded buffer standardizes to single-precision float32 non-interleaved format at the native file sample rate.
    /// - Parameter fileURL: The local URL of the audio file to read.
    /// - Returns: An AVAudioPCMBuffer containing decoded float32 samples.
    public func decode(fileURL: URL) throws -> AVAudioPCMBuffer {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: fileURL)
        } catch {
            throw AudioEngineError.decodeFailed("Could not open file at \(fileURL.lastPathComponent). It may be corrupted or in an unsupported format.")
        }
        
        let nativeFormat = file.fileFormat
        
        // Define our standard float32 processing format at the file's native sample rate and channel count
        guard let processingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: nativeFormat.sampleRate,
            channels: nativeFormat.channelCount,
            interleaved: false
        ) else {
            throw AudioEngineError.decodeFailed("Could not define float32 processing format for \(nativeFormat.channelCount) channels.")
        }
        
        let totalFrames = AVAudioFrameCount(file.length)
        guard totalFrames > 0 else {
            throw AudioEngineError.decodeFailed("The audio file contains no frames.")
        }
        
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: totalFrames) else {
            throw AudioEngineError.decodeFailed("Out of memory. Could not allocate PCM buffer for \(totalFrames) frames.")
        }
        
        do {
            try file.read(into: pcmBuffer)
        } catch {
            throw AudioEngineError.decodeFailed("Failed to read frames into memory: \(error.localizedDescription)")
        }
        
        return pcmBuffer
    }
}
