import XCTest
@testable import AudioEngine

final class SpectrumAnalyzerTests: XCTestCase {
    func testFFTAnalysisAndBands() {
        let analyzer = RealtimeFFTAnalyzer()
        
        // Assert exactly 30 logarithmic bands
        XCTAssertEqual(analyzer.bandCount, 30)
        
        // Prepare synthetic sine wave at 1000 Hz
        let sampleRate: Double = 48000.0
        let frequency: Double = 1000.0
        var samples = [Float](repeating: 0.0, count: 1024)
        
        for i in 0..<1024 {
            let t = Double(i) / sampleRate
            samples[i] = Float(sin(2.0 * .pi * frequency * t))
        }
        
        // Analyze the synthetic samples
        let spectrum = analyzer.analyze(samples: samples, sampleRate: sampleRate)
        
        // Check that spectrum has exactly 30 bands
        XCTAssertEqual(spectrum.count, 30)
        
        // Spectrum values should be between 0.0 and 1.0
        for val in spectrum {
            XCTAssertTrue(val >= 0.0 && val <= 1.0)
        }
    }
}
