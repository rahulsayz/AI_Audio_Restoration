import Foundation
import Accelerate

/// A high-performance, Accelerate-optimized True Peak detector implementing ITU-R BS.1770-4 Annex 2.
/// It uses a 4-phase polyphase FIR interpolation filter (48 taps total, 12 taps per phase) designed
/// with a Hamming-windowed sinc to detect exact inter-sample peaks.
public final class TruePeakDetector {
    
    private let phaseCount = 4
    private let tapsPerPhase = 12
    private var polyphaseFilters: [[Float]] = []
    
    public init() {
        generateFilterCoefficients()
    }
    
    /// Generates high-fidelity polyphase 4x interpolation coefficients.
    private func generateFilterCoefficients() {
        polyphaseFilters = Array(repeating: Array(repeating: 0.0, count: tapsPerPhase), count: phaseCount)
        
        // Group delay is centered around index 5.5 in the original samples.
        // For each of the 4 phases (0.0, 0.25, 0.50, 0.75 fractional delay)
        for p in 0..<phaseCount {
            let fracDelay = Float(p) / Float(phaseCount)
            var sum: Float = 0.0
            
            for k in 0..<tapsPerPhase {
                // Time relative to the center of the windowed sinc
                let t = Float(k) - 5.5 - fracDelay
                
                let val: Float
                if abs(t) < 1e-5 {
                    val = 1.0
                } else {
                    // Sinc filter with cutoff at 20 kHz (f_c = 20k / 48k = 0.4167)
                    // Or for standard 4x interpolation, f_c = 0.25 relative to oversampled rate
                    // Which is 24 kHz in 192 kHz rate, i.e., cutoff at 0.5 relative to 48 kHz Nyquist.
                    let omega = Float.pi * t / 2.0
                    val = sin(omega) / omega
                }
                
                // Hamming window
                let windowIdx = Float(k * phaseCount + p)
                let windowVal = 0.54 - 0.46 * cos(2.0 * Float.pi * windowIdx / Float(phaseCount * tapsPerPhase - 1))
                
                let coef = val * windowVal
                polyphaseFilters[p][k] = coef
                sum += coef
            }
            
            // Normalize each phase so that it maintains unity DC gain
            if sum > 0.0 {
                var scale = 1.0 / sum
                vDSP_vsmul(polyphaseFilters[p], 1, &scale, &polyphaseFilters[p], 1, vDSP_Length(tapsPerPhase))
            }
        }
    }
    
    /// Measures the true peak magnitude of a single channel of audio samples.
    /// - Parameter signal: Float array representing single-channel samples.
    /// - Returns: True peak amplitude value (linear scale).
    public func detectPeak(signal: [Float]) -> Float {
        guard !signal.isEmpty else { return 0.0 }
        
        let sampleCount = signal.count
        var maxPeak: Float = 0.0
        
        // Pad the signal to avoid reading past the end in vDSP_conv (requires N + P - 1 samples)
        var paddedSignal = signal
        paddedSignal.append(contentsOf: [Float](repeating: 0.0, count: tapsPerPhase - 1))
        
        // Run polyphase FIR filtering for each of the 4 phases
        // Since we are looking for the maximum absolute value of the 4x oversampled signal,
        // we can filter each phase separately and take the maximum of each phase output!
        // This is a major optimization as it avoids interleaving and keeps everything in cache.
        for p in 0..<phaseCount {
            // Allocate space for the filtered signal
            var output = [Float](repeating: 0.0, count: sampleCount)
            
            // vDSP_conv performs convolution:
            // Input signal: paddedSignal
            // Filter coefficients: polyphaseFilters[p] (length 12)
            // Output: output
            // We reverse the filter coefficients because vDSP_conv does a correlation summation.
            var reversedCoeffs = Array(polyphaseFilters[p].reversed())
            
            paddedSignal.withUnsafeBufferPointer { signalPtr in
                reversedCoeffs.withUnsafeBufferPointer { filterPtr in
                    output.withUnsafeMutableBufferPointer { outPtr in
                        vDSP_conv(
                            signalPtr.baseAddress!, 1,
                            filterPtr.baseAddress!, 1,
                            outPtr.baseAddress!, 1,
                            vDSP_Length(sampleCount),
                            vDSP_Length(tapsPerPhase)
                        )
                    }
                }
            }
            
            // Find the maximum absolute value of this phase output
            var phaseMax: Float = 0.0
            vDSP_maxmgv(output, 1, &phaseMax, vDSP_Length(sampleCount))
            
            maxPeak = max(maxPeak, phaseMax)
        }
        
        return maxPeak
    }
    
    /// Measures the true peak magnitude across multiple channels and returns the maximum.
    /// - Parameter channels: Non-interleaved multichannel signal array.
    /// - Returns: Maximum true peak amplitude value (linear scale).
    public func detectPeak(channels: [[Float]]) -> Float {
        var overallMax: Float = 0.0
        for signal in channels {
            let chMax = detectPeak(signal: signal)
            overallMax = max(overallMax, chMax)
        }
        return overallMax
    }
    
    /// Measures the true peak in Decibels True Peak (dBTP).
    /// - Parameter channels: Non-interleaved multichannel signal array.
    /// - Returns: True peak in dBTP.
    public func detectPeakdBTP(channels: [[Float]]) -> Float {
        let linearPeak = detectPeak(channels: channels)
        guard linearPeak > 0.0 else { return -120.0 }
        return 20.0 * log10(linearPeak)
    }
}
