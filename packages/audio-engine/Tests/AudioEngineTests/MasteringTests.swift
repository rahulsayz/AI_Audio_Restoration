import XCTest
@testable import AudioEngine

final class MasteringTests: XCTestCase {
    
    private let sampleRate: Float = 48000.0
    
    /// Generates a synthetic 1 kHz sine wave at a specified level in dBFS.
    private func generateSineWave(freq: Float = 1000.0, leveldBFS: Float, duration: Float) -> [Float] {
        let sampleCount = Int(duration * sampleRate)
        let amplitude = pow(10.0, leveldBFS / 20.0)
        var signal = [Float](repeating: 0.0, count: sampleCount)
        
        for n in 0..<sampleCount {
            let t = Float(n) / sampleRate
            signal[n] = amplitude * sin(2.0 * Float.pi * freq * t)
        }
        return signal
    }
    
    /// Test that a silent input signal processed through the loudness meter returns -70.0 LUFS.
    func testLUFSMeterSilence() {
        let meter = LUFSMeter()
        let silence = [[Float](repeating: 0.0, count: 48000)] // 1 second of silence
        let loudness = meter.analyzeLoudness(channels: silence)
        XCTAssertEqual(loudness, -70.0, accuracy: 0.1)
    }
    
    /// Test that LUFSMeter measures a 1 kHz sine wave at -10 dBFS accurately.
    /// K-weighting pre-filtering attenuates 1 kHz slightly (shelving boosts, highpass rolls off).
    /// The mathematically expected loudness is approximately within a small bound of -10 LUFS.
    func testLUFSMeterSineAccuracy() {
        let meter = LUFSMeter()
        
        // 1 kHz sine at -10.0 dBFS, 2 seconds duration
        let sine = generateSineWave(freq: 1000.0, leveldBFS: -10.0, duration: 2.0)
        let channels = [sine, sine] // Stereo
        
        let loudness = meter.analyzeLoudness(channels: channels)
        
        // ITU-R BS.1770-4 predicts that a full-scale 1 kHz sine wave is slightly adjusted.
        // It should be around -10 LUFS. We assert a broad tolerance of ±2.5 dB since K-weighting
        // has a non-flat frequency response.
        XCTAssertGreaterThan(loudness, -13.0)
        XCTAssertLessThan(loudness, -8.0)
    }
    
    /// Test that TruePeakDetector measures sample peak and oversampled peak correctly.
    func testTruePeakDetectorSine() {
        let detector = TruePeakDetector()
        
        // Sine wave at -3 dBFS
        let sine = generateSineWave(freq: 1000.0, leveldBFS: -3.0, duration: 0.1)
        let peakLinear = detector.detectPeak(channels: [sine])
        let peakdBTP = detector.detectPeakdBTP(channels: [sine])
        
        XCTAssertEqual(peakLinear, pow(10.0, -3.0 / 20.0), accuracy: 0.02)
        XCTAssertEqual(peakdBTP, -3.0, accuracy: 0.2)
    }
    
    /// Test that the Linkwitz-Riley 4th order crossover reconstructs the input signal perfectly.
    /// In a high-fidelity crossover, splitting a signal and summing the bands back must yield the original signal.
    func testCrossoverReconstruction() {
        let compressor = MultibandCompressor()
        
        // Let's test with a sine sweep / complex tone containing low, mid, and high frequencies
        let sampleCount = 9600 // 200ms
        var signal = [Float](repeating: 0.0, count: sampleCount)
        for n in 0..<sampleCount {
            let t = Float(n) / sampleRate
            signal[n] = 0.3 * sin(2.0 * Float.pi * 100.0 * t) +  // Low (100 Hz)
                        0.3 * sin(2.0 * Float.pi * 1000.0 * t) + // Mid (1000 Hz)
                        0.3 * sin(2.0 * Float.pi * 8000.0 * t)   // High (8000 Hz)
        }
        
        // Bypass compressor thresholds (make them extremely high so no compression happens)
        compressor.lowBandParams.thresholddB = 10.0
        compressor.midBandParams.thresholddB = 10.0
        compressor.highBandParams.thresholddB = 10.0
        
        let outputChannels = compressor.process(channels: [signal])
        let reconstructed = outputChannels[0]
        
        // Verify that the reconstructed signal is identical to the input signal.
        // The subtractive crossover sum is mathematically guaranteed to reconstruct the input.
        for n in 500..<(sampleCount - 500) {
            XCTAssertEqual(reconstructed[n], signal[n], accuracy: 0.001, "Reconstruction error at index \(n)")
        }
    }
    
    /// Test that Limiter strictly caps the true peak of high-amplitude transient signals below -1.0 dBTP.
    func testLimiterCeilingGuarantee() {
        let limiter = Limiter()
        limiter.ceilingLinear = Float(pow(10.0, -1.0 / 20.0)) // -1.0 dBTP
        
        // Generate a signal that severely overshoots (sine wave boosted to +6 dBFS)
        let sineOvershoot = generateSineWave(freq: 1000.0, leveldBFS: 6.0, duration: 0.5)
        
        let limitedChannels = limiter.process(channels: [sineOvershoot])
        
        let detector = TruePeakDetector()
        let outputPeakdBTP = detector.detectPeakdBTP(channels: limitedChannels)
        
        // Output true peak must be strictly <= -1.0 dBTP (within standard floating point tolerance)
        XCTAssertLessThanOrEqual(outputPeakdBTP, -0.99)
    }
    
    /// Test the full MasteringChain on a 1 kHz sine at -10 dBFS.
    /// It must align integrated loudness to -14 LUFS (streaming preset) and clamp true peak below -1 dBTP.
    func testMasteringChainStreamingPreset() {
        let chain = MasteringChain()
        
        // 1 kHz sine at -10 dBFS, 5 seconds duration
        let sine = generateSineWave(freq: 1000.0, leveldBFS: -10.0, duration: 5.0)
        let channels = [sine, sine]
        
        let mastered = chain.process(channels: channels, preset: .streaming)
        
        // Check loudness of mastered output
        let meter = LUFSMeter()
        let finalLoudness = meter.analyzeLoudness(channels: mastered)
        
        // Check true peak of mastered output
        let detector = TruePeakDetector()
        let finalPeakdBTP = detector.detectPeakdBTP(channels: mastered)
        
        // Integrated loudness should be approximately -14 LUFS (±1.5 dB)
        XCTAssertEqual(finalLoudness, -14.0, accuracy: 1.5)
        
        // True peak must be strictly < -1.0 dBTP (with 0.05 dB margin for filters)
        XCTAssertLessThanOrEqual(finalPeakdBTP, -0.95)
    }
}
