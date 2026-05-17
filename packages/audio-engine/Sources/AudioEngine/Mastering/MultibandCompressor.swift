import Foundation
import Accelerate

/// A high-performance 3-band multiband compressor using a mathematically perfect subtractive crossover.
/// It splits the signal at 250 Hz and 4000 Hz into Low, Mid, and High bands, compresses them gently,
/// and recombines them. The subtractive crossover guarantees 100% flat frequency and phase reconstruction.
public final class MultibandCompressor {
    
    /// Helper to manage a cascade of single-precision biquad filters.
    private final class LR4Filter {
        private var setup: vDSP_biquad_Setup?
        private var delayState = [Float](repeating: 0.0, count: 6) // (2 * M + 2) for M=2 sections
        
        init(freq: Float, isLowPass: Bool, sampleRate: Float = 48000.0) {
            let theta = Float.pi * freq / sampleRate
            let d = 1.0 / tan(theta)
            
            let a0 = 1.0 + sqrt(2.0) * d + d * d
            let a1_val = 2.0 * (1.0 - d * d)
            let a2_val = 1.0 - sqrt(2.0) * d + d * d
            
            let b0: Float
            let b1: Float
            let b2: Float
            
            if isLowPass {
                b0 = 1.0
                b1 = 2.0
                b2 = 1.0
            } else {
                b0 = d * d
                b1 = -2.0 * d * d
                b2 = d * d
            }
            
            // Normalize coefficients by dividing by a0
            let b0_norm = b0 / a0
            let b1_norm = b1 / a0
            let b2_norm = b2 / a0
            let a1_norm = a1_val / a0
            let a2_norm = a2_val / a0
            
            // Cascaded LR4 filter consists of two identical 2nd-order Butterworth biquad sections (Double precision required for setup)
            let singleSection: [Double] = [
                Double(b0_norm), Double(b1_norm), Double(b2_norm),
                Double(a1_norm), Double(a2_norm)
            ]
            let cascadeCoeffs = singleSection + singleSection
            
            self.setup = vDSP_biquad_CreateSetup(cascadeCoeffs, 2)
        }
        
        deinit {
            if let setup = setup {
                vDSP_biquad_DestroySetup(setup)
            }
        }
        
        func reset() {
            delayState = [Float](repeating: 0.0, count: 6)
        }
        
        /// Filters a Float array.
        func process(input: [Float]) -> [Float] {
            guard let setup = setup else { return input }
            let count = input.count
            var output = [Float](repeating: 0.0, count: count)
            
            vDSP_biquad(
                setup,
                &delayState,
                input, 1,
                &output, 1,
                vDSP_Length(count)
            )
            
            return output
        }
    }
    
    // Compressor parameters per band
    public struct BandParams {
        public var thresholddB: Float
        public var ratio: Float = 2.0
        public var attackTime: Float = 0.050  // 50ms
        public var releaseTime: Float = 0.200 // 200ms
        
        public init(thresholddB: Float) {
            self.thresholddB = thresholddB
        }
    }
    
    public var lowBandParams = BandParams(thresholddB: -18.0)
    public var midBandParams = BandParams(thresholddB: -22.0)
    public var highBandParams = BandParams(thresholddB: -26.0)
    
    private var crossoverLow: LR4Filter?
    private var crossoverHigh: LR4Filter?
    
    public init() {
        resetCrossovers()
    }
    
    private func resetCrossovers() {
        // Low crossover at 250 Hz (Low band lowpass)
        crossoverLow = LR4Filter(freq: 250.0, isLowPass: true)
        
        // High crossover at 4000 Hz (High band highpass)
        crossoverHigh = LR4Filter(freq: 4000.0, isLowPass: false)
    }
    
    public func reset() {
        crossoverLow?.reset()
        crossoverHigh?.reset()
    }
    
    /// Processes a multi-channel non-interleaved buffer and applies multiband compression.
    /// - Parameter channels: Non-interleaved channel buffers `[[Float]]`.
    /// - Returns: Compressed non-interleaved channel buffers.
    public func process(channels: [[Float]]) -> [[Float]] {
        guard !channels.isEmpty, !channels[0].isEmpty else { return channels }
        
        let sampleCount = channels[0].count
        let channelCount = channels.count
        var outputChannels = Array(repeating: [Float](repeating: 0.0, count: sampleCount), count: channelCount)
        
        for c in 0..<channelCount {
            let input = channels[c]
            
            // 1. Splitting the signal mathematically into Low, High, and Mid (subtractive)
            guard let xLow = crossoverLow?.process(input: input),
                  let xHigh = crossoverHigh?.process(input: input) else {
                outputChannels[c] = input
                continue
            }
            
            // xMid = input - xLow - xHigh
            var xMid = [Float](repeating: 0.0, count: sampleCount)
            
            // Step A: xMid = input - xLow
            var minusOne: Float = -1.0
            vDSP_vsma(xLow, 1, &minusOne, input, 1, &xMid, 1, vDSP_Length(sampleCount))
            
            // Step B: xMid = xMid - xHigh
            var xMidFinal = [Float](repeating: 0.0, count: sampleCount)
            vDSP_vsma(xHigh, 1, &minusOne, xMid, 1, &xMidFinal, 1, vDSP_Length(sampleCount))
            
            // 2. Compressing each band independently
            let compressedLow = compressBand(signal: xLow, params: lowBandParams)
            let compressedMid = compressBand(signal: xMidFinal, params: midBandParams)
            let compressedHigh = compressBand(signal: xHigh, params: highBandParams)
            
            // 3. Summing bands back to reconstruct original signal
            var output = [Float](repeating: 0.0, count: sampleCount)
            
            // Low + Mid
            vDSP_vadd(compressedLow, 1, compressedMid, 1, &output, 1, vDSP_Length(sampleCount))
            // (Low + Mid) + High
            vDSP_vadd(output, 1, compressedHigh, 1, &output, 1, vDSP_Length(sampleCount))
            
            outputChannels[c] = output
        }
        
        return outputChannels
    }
    
    /// Dynamic compression stage for a single band using peak smoothing.
    private func compressBand(signal: [Float], params: BandParams) -> [Float] {
        let sampleCount = signal.count
        var output = [Float](repeating: 0.0, count: sampleCount)
        
        // Dynamic time constant constants
        let sampleRate: Float = 48000.0
        let alphaAttack = exp(-1.0 / (sampleRate * params.attackTime))
        let alphaRelease = exp(-1.0 / (sampleRate * params.releaseTime))
        
        let ratioRecip = 1.0 / params.ratio
        
        var envelope: Float = 0.0
        let epsilon: Float = 1e-6
        
        for n in 0..<sampleCount {
            let absSample = abs(signal[n])
            
            // Smoothed Peak Sidechain Level Detector
            if absSample > envelope {
                envelope = absSample * (1.0 - alphaAttack) + envelope * alphaAttack
            } else {
                envelope = absSample * (1.0 - alphaRelease) + envelope * alphaRelease
            }
            
            // Gain Computer
            let envDb = 20.0 * log10(max(envelope, epsilon))
            var gainDb: Float = 0.0
            
            if envDb > params.thresholddB {
                gainDb = (envDb - params.thresholddB) * (ratioRecip - 1.0)
            }
            
            let gainLinear = pow(10.0, gainDb / 20.0)
            
            // Apply gain
            output[n] = signal[n] * gainLinear
        }
        
        return output
    }
}
