import XCTest
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
}
