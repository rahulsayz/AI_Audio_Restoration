import Foundation
import Accelerate

/// The main orchestrator for the Sangeet AI mastering chain in native Swift.
/// It applies multiband compression, high-frequency harmonic excitation, makeup gain scaling,
/// and a final look-ahead true-peak limiter to meet standard streaming (-14 LUFS) and remastered (-9 LUFS) specifications.
public final class MasteringChain {
    
    /// Target presets for mastering
    public enum Preset {
        /// Standard streaming target: -14 LUFS, -1 dBTP ceiling
        case streaming
        
        /// Punchy modern Indian remaster target: -9 LUFS, -1 dBTP ceiling
        case remaster
        
        /// Integrated target loudness value in LUFS
        public var targetLoudnessLUFS: Double {
            switch self {
            case .streaming: return -14.0
            case .remaster: return -9.0
            }
        }
        
        /// True peak ceiling in dBTP
        public var targetCeilingdBTP: Float {
            return -1.0
        }
    }
    
    private let lufsMeter = LUFSMeter()
    private let compressor = MultibandCompressor()
    private let exciter = HarmonicExciter()
    private let limiter = Limiter()
    
    public init() {}
    
    /// Processes and masters a multi-channel non-interleaved float32 buffer at 48 kHz.
    /// - Parameters:
    ///   - channels: Non-interleaved channel buffers `[[Float]]`.
    ///   - preset: Target preset (streaming or remaster).
    /// - Returns: Mastered non-interleaved channel buffers.
    public func process(channels: [[Float]], preset: Preset) -> [[Float]] {
        guard !channels.isEmpty, !channels[0].isEmpty else { return channels }
        
        // Reset dynamic component states for clean processing
        compressor.reset()
        exciter.reset()
        
        let sampleCount = channels[0].count
        let channelCount = channels.count
        
        // 1. Process through Multiband Compressor (gentle 2:1 dynamic control)
        // Configure thresholds slightly tailored per preset
        if preset == .remaster {
            // Remaster preset uses slightly tighter thresholds to achieve a punchier sound
            compressor.lowBandParams.thresholddB = -16.0
            compressor.midBandParams.thresholddB = -20.0
            compressor.highBandParams.thresholddB = -24.0
            exciter.mix = 0.8  // Add more top-end sparkle for remastering
            exciter.drive = 2.0
        } else {
            // Standard streaming thresholds
            compressor.lowBandParams.thresholddB = -18.0
            compressor.midBandParams.thresholddB = -22.0
            compressor.highBandParams.thresholddB = -26.0
            exciter.mix = 0.4  // Gentle high-end sparkle for streaming
            exciter.drive = 1.6
        }
        
        let compressed = compressor.process(channels: channels)
        
        // 2. Process through Harmonic Exciter (HF brilliant sparkle in 6-15 kHz band)
        let excited = exciter.process(channels: compressed)
        
        // 3. Measure integrated loudness of the compressed and excited signal before makeup gain
        let intermediateLUFS = lufsMeter.analyzeLoudness(channels: excited)
        
        // 4. Calculate target makeup gain required to reach target preset loudness
        let targetLUFS = preset.targetLoudnessLUFS
        
        // If intermediate LUFS is extremely quiet (like silence/noise floor), we do not apply insane gains.
        // Cap the gain boost at +12 dB maximum to avoid amplifying noise floors.
        var makeupGaindB = targetLUFS - intermediateLUFS
        if makeupGaindB > 12.0 {
            makeupGaindB = 12.0
        } else if makeupGaindB < -20.0 {
            // Cap gain attenuation at -20 dB
            makeupGaindB = -20.0
        }
        
        let makeupGainLinear = Float(pow(10.0, makeupGaindB / 20.0))
        
        // 5. Apply target makeup gain
        var amplified = Array(repeating: [Float](repeating: 0.0, count: sampleCount), count: channelCount)
        var scale = makeupGainLinear
        
        for c in 0..<channelCount {
            vDSP_vsmul(excited[c], 1, &scale, &amplified[c], 1, vDSP_Length(sampleCount))
        }
        
        // 6. Pass through look-ahead True-Peak Limiter (clamps to -1.0 dBTP ceiling)
        limiter.ceilingLinear = Float(pow(10.0, Double(preset.targetCeilingdBTP) / 20.0))
        let limited = limiter.process(channels: amplified)
        
        return limited
    }
}
