import Foundation
import Accelerate

public final class RealtimeFFTAnalyzer {
    private let fftSize = 1024
    private let log2FFTSize: vDSP_Length
    private let fftSetup: FFTSetup
    
    private var window: [Float]
    private var realParts: [Float]
    private var imagParts: [Float]
    
    // Logarithmic band definition (30 bands)
    public let bandCount = 30
    private var bandFrequencies: [Float] = []
    private var smoothedMagnitudes: [Float]
    
    public init() {
        self.log2FFTSize = vDSP_Length(log2(Double(fftSize)))
        self.fftSetup = vDSP_create_fftsetup(log2FFTSize, FFTRadix(kFFTRadix2))!
        
        self.window = [Float](repeating: 0.0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        
        self.realParts = [Float](repeating: 0.0, count: fftSize / 2)
        self.imagParts = [Float](repeating: 0.0, count: fftSize / 2)
        
        self.smoothedMagnitudes = [Float](repeating: 0.0, count: bandCount)
        
        // Calculate logarithmic frequency bands (20Hz to 20kHz)
        let minFreq: Float = 20.0
        let maxFreq: Float = 20000.0
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let logStep = (logMax - logMin) / Float(bandCount)
        
        for i in 0...bandCount {
            let freq = pow(10.0, logMin + Float(i) * logStep)
            bandFrequencies.append(freq)
        }
    }
    
    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }
    
    /// Analyzes a buffer of 1024 Float32 samples, returning 30 logarithmic frequency bands
    public func analyze(samples: [Float], sampleRate: Double) -> [Float] {
        guard samples.count >= fftSize else {
            return smoothedMagnitudes
        }
        
        // 1. Apply Windowing
        var windowedSamples = [Float](repeating: 0.0, count: fftSize)
        vDSP_vmul(samples, 1, window, 1, &windowedSamples, 1, vDSP_Length(fftSize))
        
        // 2. Execute FFT and analyze magnitudes
        realParts.withUnsafeMutableBufferPointer { realPtr in
            imagParts.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                
                windowedSamples.withUnsafeBufferPointer { bufferPtr in
                    let rawPtr = UnsafeRawPointer(bufferPtr.baseAddress!)
                    let complexPtr = rawPtr.bindMemory(to: DSPComplex.self, capacity: fftSize / 2)
                    vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                }
                
                // Execute forward FFT
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2FFTSize, FFTDirection(kFFTDirection_Forward))
                
                // Calculate squared magnitudes
                var magnitudes = [Float](repeating: 0.0, count: fftSize / 2)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
                
                // Scale magnitudes
                var scale = 1.0 / Float(fftSize)
                vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(fftSize / 2))
                
                // Convert power to decibels with reference 1.0
                var dbMagnitudes = [Float](repeating: 0.0, count: fftSize / 2)
                for idx in 0..<(fftSize / 2) {
                    let mag = magnitudes[idx]
                    dbMagnitudes[idx] = mag > 1e-8 ? 10.0 * log10(mag) : -120.0
                }
                
                // Group into 30 logarithmic bands
                let binWidth = Float(sampleRate) / Float(fftSize)
                for band in 0..<bandCount {
                    let lowFreq = bandFrequencies[band]
                    let highFreq = bandFrequencies[band + 1]
                    
                    var sumPower: Float = 0.0
                    var count: Float = 0.0
                    
                    for bin in 0..<(fftSize / 2) {
                        let freq = Float(bin) * binWidth
                        if freq >= lowFreq && freq <= highFreq {
                            let db = dbMagnitudes[bin]
                            sumPower += pow(10.0, db / 10.0)
                            count += 1.0
                        }
                    }
                    
                    let avgPower = count > 0 ? (sumPower / count) : 1e-8
                    let avgDb = 10.0 * log10(avgPower)
                    
                    // Normalize dB (-80 to 0) to [0.0, 1.0] range
                    let norm = max(0.0, min(1.0, (avgDb + 80.0) / 80.0))
                    
                    // Exponential smoothing decay (alpha = 0.3)
                    smoothedMagnitudes[band] = 0.7 * smoothedMagnitudes[band] + 0.3 * norm
                }
            }
        }
        
        return smoothedMagnitudes
    }
}
