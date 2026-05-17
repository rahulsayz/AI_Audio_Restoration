import Foundation
import AVFoundation

public final class WaveformGenerator {
    /// Reads an audio file and generates a list of downsampled float amplitudes (0.0 to 1.0)
    /// - Parameters:
    ///   - fileURL: Local URL of the audio file to inspect.
    ///   - targetPoints: The exact number of amplitude points to return (defaults to 40).
    public static func generateAmplitudes(from fileURL: URL, targetPoints: Int = 40) -> [Float] {
        let accessScoped = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessScoped {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            let file = try AVAudioFile(forReading: fileURL)
            let format = file.fileFormat
            let frameCount = UInt32(file.length)
            
            guard frameCount > 0 else {
                return Array(repeating: 0.0, count: targetPoints)
            }
            
            // Sample the file in discrete segments to maintain zero-latency response and avoid OOM issues
            let segmentSize = max(1024, frameCount / UInt32(targetPoints))
            var amplitudes: [Float] = []
            
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(1024))!
            
            for i in 0..<targetPoints {
                let startFrame = Int64(UInt32(i) * segmentSize)
                if startFrame >= file.length {
                    amplitudes.append(0.0)
                    continue
                }
                
                file.framePosition = startFrame
                try file.read(into: buffer, frameCount: min(1024, UInt32(file.length - startFrame)))
                
                guard let channelData = buffer.floatChannelData else {
                    amplitudes.append(0.0)
                    continue
                }
                
                let frameLength = Int(buffer.frameLength)
                if frameLength == 0 {
                    amplitudes.append(0.0)
                    continue
                }
                
                // Calculate RMS amplitude of the segment
                var sum: Float = 0.0
                for f in 0..<frameLength {
                    let sample = channelData[0][f]
                    sum += sample * sample
                }
                let rms = sqrt(sum / Float(frameLength))
                amplitudes.append(rms)
            }
            
            // Normalize amplitudes to a visually uniform [0.05, 1.0] range
            let maxAmp = amplitudes.max() ?? 1.0
            if maxAmp > 0 {
                return amplitudes.map { max(0.05, $0 / maxAmp) }
            } else {
                return Array(repeating: 0.05, count: targetPoints)
            }
        } catch {
            print("[WaveformGenerator] Failed to generate amplitudes: \(error.localizedDescription)")
            return Array(repeating: 0.05, count: targetPoints)
        }
    }
}
