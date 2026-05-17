import Foundation
import Accelerate

/// A high-performance, Accelerate-optimized loudness meter implementing ITU-R BS.1770-4 and EBU R128 specifications.
/// It operates on float32 non-interleaved channels at a fixed sample rate of 48 kHz.
public final class LUFSMeter {
    
    // ITU-R BS.1770-4 K-weighting filter coefficients at 48 kHz (Double precision required for CreateSetup)
    // Stage 1 (High Shelving): B0, B1, B2, A1, A2
    private static let biquad1Coeffs: [Double] = [
        1.5309609, -2.651169, 1.1691668,
        -1.6636501, 0.71258884
    ]
    
    // Stage 2 (High-Pass): B0, B1, B2, A1, A2
    private static let biquad2Coeffs: [Double] = [
        1.0, -2.0, 1.0,
        -1.9900475, 0.99007225
    ]
    
    public init() {}
    
    /// Analyzes the integrated loudness of a non-interleaved multi-channel audio buffer in LUFS.
    /// - Parameter channels: Non-interleaved channel buffers, where each outer element is a channel [Float].
    /// - Returns: Gated integrated loudness in LUFS. Returns -70.0 if the audio is completely silent.
    public func analyzeLoudness(channels: [[Float]]) -> Double {
        guard !channels.isEmpty, !channels[0].isEmpty else {
            return -70.0
        }
        
        let sampleCount = channels[0].count
        let channelCount = channels.count
        
        // 1. K-Weighting Pre-Filtering using Accelerate
        let cascadeCoeffs = Self.biquad1Coeffs + Self.biquad2Coeffs
        
        var filteredChannels = Array(repeating: [Float](repeating: 0.0, count: sampleCount), count: channelCount)
        
        // Create single-precision biquad cascade setup (requires Double coefficients)
        guard let biquadSetup = vDSP_biquad_CreateSetup(cascadeCoeffs, 2) else {
            return -70.0
        }
        
        defer {
            vDSP_biquad_DestroySetup(biquadSetup)
        }
        
        for c in 0..<channelCount {
            var delayState = [Float](repeating: 0.0, count: 6) // (2 * M + 2) for M=2 sections
            
            vDSP_biquad(
                biquadSetup,
                &delayState,
                channels[c], 1,
                &filteredChannels[c], 1,
                vDSP_Length(sampleCount)
            )
        }
        
        // 2. Overlapping 400ms Block Energy Evaluation
        // Block size: 400ms = 19200 samples at 48 kHz
        // Stride: 100ms (75% overlap) = 4800 samples
        let blockSize = 19200
        let stride = 4800
        
        guard sampleCount >= blockSize else {
            return -70.0
        }
        
        let blockCount = (sampleCount - blockSize) / stride + 1
        var blockEnergies = [Double](repeating: 0.0, count: blockCount)
        
        // Channel weights: Left = 1.0, Right = 1.0, others default to 1.0
        let weights = [Double](repeating: 1.0, count: channelCount)
        
        for i in 0..<blockCount {
            let offset = i * stride
            var weightedSum = 0.0
            
            for c in 0..<channelCount {
                let blockSlice = filteredChannels[c][offset..<(offset + blockSize)]
                var meanSquare: Float = 0.0
                
                blockSlice.withUnsafeBufferPointer { slicePtr in
                    vDSP_measqv(slicePtr.baseAddress!, 1, &meanSquare, vDSP_Length(blockSize))
                }
                
                weightedSum += Double(meanSquare) * weights[c]
            }
            
            blockEnergies[i] = weightedSum
        }
        
        // 3. Absolute Gating Pass (-70.0 LUFS)
        var absolutePassedIndices: [Int] = []
        var absolutePassedEnergies: [Double] = []
        
        for i in 0..<blockCount {
            let energy = blockEnergies[i]
            let dbValue = -0.691 + 10.0 * log10(max(energy, 1e-12))
            if dbValue > -70.0 {
                absolutePassedIndices.append(i)
                absolutePassedEnergies.append(energy)
            }
        }
        
        if absolutePassedEnergies.isEmpty {
            return -70.0
        }
        
        // 4. Relative Gating Pass (-10 dB relative to absolute average)
        var totalAbsPassedEnergy = 0.0
        vDSP_sveD(absolutePassedEnergies, 1, &totalAbsPassedEnergy, vDSP_Length(absolutePassedEnergies.count))
        let averageAbsPassedEnergy = totalAbsPassedEnergy / Double(absolutePassedEnergies.count)
        
        let relativeThresholdDb = -0.691 + 10.0 * log10(max(averageAbsPassedEnergy, 1e-12)) - 10.0
        
        var relativePassedEnergies: [Double] = []
        for idx in absolutePassedIndices {
            let energy = blockEnergies[idx]
            let dbValue = -0.691 + 10.0 * log10(max(energy, 1e-12))
            if dbValue > relativeThresholdDb {
                relativePassedEnergies.append(energy)
            }
        }
        
        if relativePassedEnergies.isEmpty {
            return -70.0
        }
        
        // 5. Integrated Loudness Calculation
        var totalFinalEnergy = 0.0
        vDSP_sveD(relativePassedEnergies, 1, &totalFinalEnergy, vDSP_Length(relativePassedEnergies.count))
        let averageFinalEnergy = totalFinalEnergy / Double(relativePassedEnergies.count)
        
        let finalLoudness = -0.691 + 10.0 * log10(max(averageFinalEnergy, 1e-12))
        return finalLoudness
    }
}
