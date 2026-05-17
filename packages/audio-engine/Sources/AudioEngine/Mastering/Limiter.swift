import Foundation
import Accelerate

/// A high-performance, true-peak look-ahead limiter with zero-overshoot ceiling compliance.
/// It uses a 5ms delay line (240 samples at 48 kHz) and a 4x oversampled polyphase sidechain.
public final class Limiter {
    
    private let sampleRate: Float = 48000.0
    private let lookAheadTime: Float = 0.005  // 5ms
    private let releaseTime: Float = 0.050    // 50ms
    
    private let delaySamples = 240 // 0.005 * 48000
    private let detector = TruePeakDetector()
    
    /// Target true-peak ceiling in linear scale. Defaults to -1.0 dBTP (approx 0.89125).
    public var ceilingLinear: Float = 0.89125
    
    public init() {}
    
    /// Limits multi-channel non-interleaved buffers.
    /// - Parameter channels: Non-interleaved channel buffers `[[Float]]`.
    /// - Returns: Limited non-interleaved channel buffers.
    public func process(channels: [[Float]]) -> [[Float]] {
        guard !channels.isEmpty, !channels[0].isEmpty else { return channels }
        
        let sampleCount = channels[0].count
        let channelCount = channels.count
        var outputChannels = Array(repeating: [Float](repeating: 0.0, count: sampleCount), count: channelCount)
        
        // Dynamic time constants
        let alphaRelease = exp(-1.0 / (sampleRate * releaseTime))
        
        // Setup polyphase filter setups from detector
        // We will pre-calculate the oversampled true peaks for each original sample index c.
        // P_raw[i] is the maximum absolute value of the 4x oversampled phases at index i.
        var rawPeaks = [Float](repeating: 0.0, count: sampleCount)
        
        // To build the sidechain peak detector, we take the maximum peak across all channels
        for c in 0..<channelCount {
            let signal = channels[c]
            
            // Pad the signal to avoid reading past the end in vDSP_conv (requires N + P - 1 samples)
            var paddedSignal = signal
            paddedSignal.append(contentsOf: [Float](repeating: 0.0, count: 11)) // 12 - 1 = 11
            
            // Using mirror-reflected or direct access to coefficients
            // Since we already have the detector instance, let's extract the polyphase filters.
            // We can just oversample using the detector's internal polyphase filters!
            // Let's write the oversampling convolution here for raw peaks.
            let phaseFilters = getPolyphaseFilters()
            
            for p in 0..<4 {
                var reversedCoeffs = Array(phaseFilters[p].reversed())
                var output = [Float](repeating: 0.0, count: sampleCount)
                
                paddedSignal.withUnsafeBufferPointer { signalPtr in
                    reversedCoeffs.withUnsafeBufferPointer { filterPtr in
                        output.withUnsafeMutableBufferPointer { outPtr in
                            vDSP_conv(
                                signalPtr.baseAddress!, 1,
                                filterPtr.baseAddress!, 1,
                                outPtr.baseAddress!, 1,
                                vDSP_Length(sampleCount),
                                12
                            )
                        }
                    }
                }
                
                // Track raw peaks
                for i in 0..<sampleCount {
                    let absVal = abs(output[i])
                    if absVal > rawPeaks[i] {
                        rawPeaks[i] = absVal
                    }
                }
            }
        }
        
        // 2. Sliding Window Peak Detection
        // P[n] is the maximum raw peak in the past window [n - delaySamples, n].
        // This ensures the gain envelope is fully reduced 5ms before the peak is output.
        var futurePeaks = [Float](repeating: 0.0, count: sampleCount)
        
        var maxVal: Float = 0.0
        var windowMaxIdx = -1
        
        for n in 0..<sampleCount {
            let start = max(0, n - delaySamples)
            
            // If the previous maximum is still inside our current window [start, n],
            // we only need to compare it with the new sample entering the window (rawPeaks[n])
            if windowMaxIdx >= start {
                if rawPeaks[n] >= maxVal {
                    maxVal = rawPeaks[n]
                    windowMaxIdx = n
                }
            } else {
                // Otherwise, scan the window to locate the new maximum
                maxVal = 0.0
                windowMaxIdx = start
                for k in start...n {
                    let val = rawPeaks[k]
                    if val > maxVal {
                        maxVal = val
                        windowMaxIdx = k
                    }
                }
            }
            futurePeaks[n] = maxVal
        }
        
        // 3. Gain Reduction Envelope and Release Tracking
        var gainEnvelope = [Float](repeating: 1.0, count: sampleCount)
        var lastGain: Float = 1.0
        
        for n in 0..<sampleCount {
            let peak = futurePeaks[n]
            
            // Target gain to bring peak exactly to ceiling
            let targetGain: Float
            if peak > ceilingLinear {
                targetGain = ceilingLinear / peak
            } else {
                targetGain = 1.0
            }
            
            // Attack is instant (because look-ahead peak scans ahead).
            // Release tracks recovery slowly.
            if targetGain < lastGain {
                // Instant gain reduction drop
                lastGain = targetGain
            } else {
                // Smooth gain recovery towards targetGain
                lastGain = lastGain * alphaRelease + (1.0 - alphaRelease) * targetGain
            }
            
            gainEnvelope[n] = lastGain
        }
        
        // 4. Apply Gain to the Delayed Signal
        for c in 0..<channelCount {
            let signal = channels[c]
            var output = [Float](repeating: 0.0, count: sampleCount)
            
            for n in 0..<sampleCount {
                // Retrieve delayed sample (pad with quiet reflection/zero if index < delaySamples)
                let delayedSample: Float
                if n >= delaySamples {
                    delayedSample = signal[n - delaySamples]
                } else {
                    delayedSample = 0.0
                }
                
                output[n] = delayedSample * gainEnvelope[n]
            }
            
            outputChannels[c] = output
        }
        
        return outputChannels
    }
    
    /// Extracts interpolation filter coefficients from the polyphase FIR design.
    private func getPolyphaseFilters() -> [[Float]] {
        var filters = Array(repeating: Array(repeating: Float(0.0), count: 12), count: 4)
        
        for p in 0..<4 {
            let fracDelay = Float(p) / 4.0
            var sum: Float = 0.0
            
            for k in 0..<12 {
                let t = Float(k) - 5.5 - fracDelay
                let val: Float
                if abs(t) < 1e-5 {
                    val = 1.0
                } else {
                    let omega = Float.pi * t / 2.0
                    val = sin(omega) / omega
                }
                
                let windowIdx = Float(k * 4 + p)
                let windowVal = 0.54 - 0.46 * cos(2.0 * Float.pi * windowIdx / 47.0)
                
                let coef = val * windowVal
                filters[p][k] = coef
                sum += coef
            }
            
            if sum > 0.0 {
                let scale = 1.0 / sum
                for k in 0..<12 {
                    filters[p][k] *= scale
                }
            }
        }
        
        return filters
    }
}
