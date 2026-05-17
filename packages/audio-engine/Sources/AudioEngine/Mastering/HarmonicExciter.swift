import Foundation
import Accelerate

/// A high-performance harmonic exciter that generates subtle high-frequency harmonics
/// by applying soft saturation in the 6 kHz – 15 kHz frequency band.
public final class HarmonicExciter {
    
    /// Helper to manage a single-precision biquad filter.
    private final class BiquadFilter {
        private var setup: vDSP_biquad_Setup?
        private var delayState = [Float](repeating: 0.0, count: 4) // (2 * M + 2) for M=1 section
        
        init(freq: Float, q: Float, type: FilterType, sampleRate: Float = 48000.0) {
            let omega = 2.0 * Float.pi * freq / sampleRate
            let sinOmega = sin(omega)
            let cosOmega = cos(omega)
            let alpha = sinOmega / (2.0 * q)
            
            let b0: Float
            let b1: Float
            let b2: Float
            let a0: Float
            let a1: Float
            let a2: Float
            
            switch type {
            case .bandpass:
                b0 = sinOmega / 2.0
                b1 = 0.0
                b2 = -sinOmega / 2.0
                a0 = 1.0 + alpha
                a1 = -2.0 * cosOmega
                a2 = 1.0 - alpha
            case .highpass:
                b0 = (1.0 + cosOmega) / 2.0
                b1 = -(1.0 + cosOmega)
                b2 = (1.0 + cosOmega) / 2.0
                a0 = 1.0 + alpha
                a1 = -2.0 * cosOmega
                a2 = 1.0 - alpha
            }
            
            // Setup coefficients in Double precision (as required by Accelerate)
            let coeffs: [Double] = [
                Double(b0 / a0), Double(b1 / a0), Double(b2 / a0),
                Double(a1 / a0), Double(a2 / a0)
            ]
            
            self.setup = vDSP_biquad_CreateSetup(coeffs, 1)
        }
        
        deinit {
            if let setup = setup {
                vDSP_biquad_DestroySetup(setup)
            }
        }
        
        func reset() {
            delayState = [Float](repeating: 0.0, count: 4)
        }
        
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
        
        enum FilterType {
            case bandpass
            case highpass
        }
    }
    
    private var bandpassFilterLeft: BiquadFilter?
    private var bandpassFilterRight: BiquadFilter?
    private var safetyHighpassLeft: BiquadFilter?
    private var safetyHighpassRight: BiquadFilter?
    
    /// Drive/Saturation intensity. Higher values yield more harmonic generation. Default is 1.5.
    public var drive: Float = 1.5
    
    /// Mix level of the excited harmonics blended back with the original signal (0.0 to 1.0). Default is 0.4.
    public var mix: Float = 0.4
    
    public init() {
        resetFilters()
    }
    
    private func resetFilters() {
        // Bandpass filter at 10.5 kHz (center of 6k-15k band) with Q=0.8 to cover the band
        bandpassFilterLeft = BiquadFilter(freq: 10500.0, q: 0.8, type: .bandpass)
        bandpassFilterRight = BiquadFilter(freq: 10500.0, q: 0.8, type: .bandpass)
        
        // Safety high-pass filter at 6 kHz to remove any generated subharmonic folddown
        safetyHighpassLeft = BiquadFilter(freq: 6000.0, q: 0.707, type: .highpass)
        safetyHighpassRight = BiquadFilter(freq: 6000.0, q: 0.707, type: .highpass)
    }
    
    public func reset() {
        bandpassFilterLeft?.reset()
        bandpassFilterRight?.reset()
        safetyHighpassLeft?.reset()
        safetyHighpassRight?.reset()
    }
    
    /// Processes a multi-channel non-interleaved buffer and applies high-frequency harmonic excitation.
    /// - Parameter channels: Non-interleaved channel buffers `[[Float]]`.
    /// - Returns: Excited non-interleaved channel buffers.
    public func process(channels: [[Float]]) -> [[Float]] {
        guard !channels.isEmpty, !channels[0].isEmpty else { return channels }
        
        let sampleCount = channels[0].count
        let channelCount = channels.count
        var outputChannels = Array(repeating: [Float](repeating: 0.0, count: sampleCount), count: channelCount)
        
        for c in 0..<channelCount {
            let input = channels[c]
            
            // 1. Isolate the HF 6-15 kHz band
            let bpFilter = (c == 0) ? bandpassFilterLeft : bandpassFilterRight
            let hpFilter = (c == 0) ? safetyHighpassLeft : safetyHighpassRight
            
            guard let isolatedHF = bpFilter?.process(input: input) else {
                outputChannels[c] = input
                continue
            }
            
            // 2. Dynamic high-speed soft-saturation using vForce tanh
            var drivenHF = [Float](repeating: 0.0, count: sampleCount)
            var scale = drive
            
            // Apply drive amplification to the isolated band
            vDSP_vsmul(isolatedHF, 1, &scale, &drivenHF, 1, vDSP_Length(sampleCount))
            
            // Calculate tanh saturation: drivenHF = tanh(drivenHF)
            var saturatedHF = [Float](repeating: 0.0, count: sampleCount)
            var count = Int32(sampleCount)
            vvtanhf(&saturatedHF, drivenHF, &count)
            
            // Subtract the driven linear part to isolate only the newly generated *harmonics* (distortion delta)
            // harmonics = saturatedHF - (isolatedHF * 0.5)
            var harmonics = [Float](repeating: 0.0, count: sampleCount)
            var linearScale: Float = -0.5
            vDSP_vsma(isolatedHF, 1, &linearScale, saturatedHF, 1, &harmonics, 1, vDSP_Length(sampleCount))
            
            // 3. Safety high-pass filter at 6 kHz on the harmonics to eliminate low-frequency intermodulation
            guard let cleanHarmonics = hpFilter?.process(input: harmonics) else {
                outputChannels[c] = input
                continue
            }
            
            // 4. Blend the generated harmonics back with the original signal
            var output = [Float](repeating: 0.0, count: sampleCount)
            var blendFactor = mix
            
            vDSP_vsma(cleanHarmonics, 1, &blendFactor, input, 1, &output, 1, vDSP_Length(sampleCount))
            
            outputChannels[c] = output
        }
        
        return outputChannels
    }
}
