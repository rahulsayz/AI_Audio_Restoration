import XCTest
import AVFoundation
@testable import SangeetAI
import AudioEngine

@MainActor
final class SangeetAITests: XCTestCase {
    private var viewModel: RestorationViewModel!
    
    override func setUp() {
        super.setUp()
        // Instantiate using a mock coordinator to avoid launching real background daemons during unit tests
        viewModel = RestorationViewModel(coordinator: RestorationCoordinator())
    }
    
    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }
    
    func test_viewModel_initialization_defaultsToEmptyState() {
        XCTAssertNil(viewModel.loadedFileURL)
        XCTAssertTrue(viewModel.filename.isEmpty)
        XCTAssertTrue(viewModel.durationString.isEmpty)
        XCTAssertTrue(viewModel.sampleRateString.isEmpty)
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertEqual(viewModel.progress, 0.0)
        XCTAssertTrue(viewModel.currentStage.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.restorationComplete)
    }
    
    func test_viewModel_withUnsupportedExtension_producesErrorMessage() {
        let unsupportedURL = URL(fileURLWithPath: "/Users/test/music.png")
        viewModel.loadFile(url: unsupportedURL)
        
        XCTAssertNil(viewModel.loadedFileURL)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage!.contains("only supports WAV, FLAC, MP3, and M4A"))
    }
    
    func test_viewModel_clearFile_correctlyResetsState() {
        // Load an invalid file type first
        viewModel.loadFile(url: URL(fileURLWithPath: "/Users/test/music.txt"))
        XCTAssertNotNil(viewModel.errorMessage)
        
        // Reset
        viewModel.clearFile()
        
        XCTAssertNil(viewModel.loadedFileURL)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isProcessing)
    }
    
    func test_fullRestorationWorkflow_endToEnd() async throws {
        // 1. Arrange a real synthetic WAV file for test drop
        let tempDir = FileManager.default.temporaryDirectory
        let inputURL = tempDir.appendingPathComponent("lata_test.wav")
        
        // Generate a 1-second synthetic sine wave WAV file
        let sampleRate: Double = 44100.0
        let duration: Double = 1.0
        let totalSamples = Int(sampleRate * duration)
        var samples = [Float](repeating: 0.0, count: totalSamples)
        for i in 0..<totalSamples {
            samples[i] = sin(Float(i) * 2.0 * Float.pi * 440.0 / Float(sampleRate))
        }
        
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]
        
        let audioFile = try AVAudioFile(forWriting: inputURL, settings: settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalSamples))!
        buffer.frameLength = AVAudioFrameCount(totalSamples)
        for i in 0..<totalSamples {
            buffer.floatChannelData?[0][i] = samples[i]
        }
        try audioFile.write(from: buffer)
        
        defer {
            try? FileManager.default.removeItem(at: inputURL)
        }
        
        // 2. Drop the file — analysis panel populates
        viewModel.loadFile(url: inputURL)
        XCTAssertEqual(viewModel.filename, "lata_test.wav")
        XCTAssertEqual(viewModel.loadedFileURL, inputURL)
        
        // Wait a tiny moment for metadata / mock analysis to settle
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(viewModel.sampleRateString.isEmpty)
        XCTAssertFalse(viewModel.durationString.isEmpty)
        
        // 3. Click Restore — progress streams
        viewModel.startRestoration()
        
        // Assert that processing has started
        XCTAssertTrue(viewModel.isProcessing)
        
        // Wait for restoration to complete (the mock daemon finishes instantly or extremely fast)
        var checkCount = 0
        while viewModel.isProcessing && checkCount < 100 {
            try await Task.sleep(nanoseconds: 50_000_000)
            checkCount += 1
        }
        
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertTrue(viewModel.restorationComplete)
        XCTAssertNotNil(viewModel.outputFileURL)
        
        // Clean up output file
        if let outURL = viewModel.outputFileURL {
            defer { try? FileManager.default.removeItem(at: outURL) }
        }
        
        // 4. Result appears in library
        viewModel.loadLibrary()
        XCTAssertFalse(viewModel.libraryEntries.isEmpty)
        let latestEntry = viewModel.libraryEntries.first
        XCTAssertEqual(latestEntry?.filename, "lata_test.wav")
        
        // 5. Settings persist across launches
        UserDefaults.standard.set("remaster", forKey: "defaultMasteringPreset")
        let settingsPreset = UserDefaults.standard.string(forKey: "defaultMasteringPreset")
        XCTAssertEqual(settingsPreset, "remaster")
        
        // 6. Restart app — library entry is still there
        let newViewModel = RestorationViewModel(coordinator: RestorationCoordinator())
        newViewModel.loadLibrary()
        XCTAssertFalse(newViewModel.libraryEntries.isEmpty)
        XCTAssertEqual(newViewModel.libraryEntries.first?.filename, "lata_test.wav")
        
        // Clean up database entry
        if let entryId = latestEntry?.id {
            newViewModel.deleteEntry(id: entryId)
        }
    }
    
    func test_telemetryManager_consentDefaultsAndToggle() {
        let manager = TelemetryManager.shared
        
        // Reset defaults
        UserDefaults.standard.removeObject(forKey: "SAITelemetryEnabled")
        UserDefaults.standard.removeObject(forKey: "SAITelemetryConsentShown")
        
        XCTAssertTrue(manager.isTelemetryEnabled) // defaults to true
        XCTAssertFalse(manager.isConsentShown)
        
        // Disable
        manager.setTelemetryEnabled(false)
        XCTAssertFalse(manager.isTelemetryEnabled)
        
        // Toggle consent shown
        manager.setConsentShown(true)
        XCTAssertTrue(manager.isConsentShown)
        
        // Re-enable
        manager.setTelemetryEnabled(true)
        XCTAssertTrue(manager.isTelemetryEnabled)
    }
    
    func test_telemetryManager_eventsRollingBuffer() {
        let manager = TelemetryManager.shared
        manager.setTelemetryEnabled(true)
        manager.clearHistory()
        XCTAssertEqual(manager.recentEvents.count, 0)
        
        // Track 25 events, rolling cache must cap at 20
        for i in 1...25 {
            manager.track(event: "test_event_\(i)", properties: ["index": "\(i)"])
        }
        
        // Since tracking is asynchronous on the serial queue, we wait a tiny moment for processing
        let expectation = XCTestExpectation(description: "Wait for serial queue to process events")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(manager.recentEvents.count, 20)
        // Check that the last event in the buffer is test_event_25 (most recent at the top)
        XCTAssertEqual(manager.recentEvents.first?.name, "test_event_25")
        // Check that the oldest event in the buffer is test_event_6
        XCTAssertEqual(manager.recentEvents.last?.name, "test_event_6")
        
        // Clear history
        manager.clearHistory()
        XCTAssertEqual(manager.recentEvents.count, 0)
    }
    
    func test_telemetryManager_whenDisabled_doesNotRecordEvents() {
        let manager = TelemetryManager.shared
        manager.setTelemetryEnabled(false)
        manager.clearHistory()
        
        manager.track(event: "disabled_test", properties: [:])
        
        let expectation = XCTestExpectation(description: "Wait for serial queue")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(manager.recentEvents.count, 0)
    }
}
