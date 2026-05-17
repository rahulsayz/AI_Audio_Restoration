import XCTest
import GRDB
@testable import AudioEngine

final class LibraryPersistenceTests: XCTestCase {
    private var tempDBURL: URL!
    private var database: LibraryDatabase!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        // Initialize an in-memory or localized temporary SQLite file for testing
        let tempDir = FileManager.default.temporaryDirectory
        tempDBURL = tempDir.appendingPathComponent(UUID().uuidString + "-test.sqlite")
        database = try LibraryDatabase(storeURL: tempDBURL)
    }
    
    override func tearDownWithError() throws {
        // Clean up the temp SQLite database file
        try? FileManager.default.removeItem(at: tempDBURL)
        database = nil
        try super.tearDownWithError()
    }
    
    func test_database_initialization_creates_table() throws {
        // Assert that we can fetch entries from the newly created table without error (means table exists)
        let entries = try database.fetchAllEntries()
        XCTAssertTrue(entries.isEmpty)
    }
    
    func test_save_and_fetch_entry() throws {
        let entryId = UUID()
        let entry = LibraryEntry(
            id: entryId,
            filename: "lata_1952.mp3",
            originalPath: "/path/to/original.mp3",
            restoredPath: "/path/to/restored.mp3",
            restorationDate: Date(),
            durationString: "3:32",
            sampleRateString: "44.1 kHz",
            preset: "streaming",
            measuredLUFS: -14.2,
            measuredTruePeak: -1.1,
            analysisResultData: Data([0, 1, 2, 3]),
            waveformPointsData: Data([4, 5, 6, 7])
        )
        
        // Save
        try database.saveEntry(entry)
        
        // Fetch
        let fetched = try database.fetchAllEntries()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, entryId)
        XCTAssertEqual(fetched.first?.filename, "lata_1952.mp3")
        XCTAssertEqual(fetched.first?.measuredLUFS, -14.2)
        XCTAssertEqual(fetched.first?.measuredTruePeak, -1.1)
    }
    
    func test_delete_entry() throws {
        let entryId = UUID()
        let entry = LibraryEntry(
            id: entryId,
            filename: "lata_1952.mp3",
            originalPath: "/path/to/original.mp3",
            restoredPath: "/path/to/restored.mp3",
            restorationDate: Date(),
            durationString: "3:32",
            sampleRateString: "44.1 kHz",
            preset: "streaming",
            measuredLUFS: -14.2,
            measuredTruePeak: -1.1,
            analysisResultData: Data(),
            waveformPointsData: Data()
        )
        
        try database.saveEntry(entry)
        var fetched = try database.fetchAllEntries()
        XCTAssertEqual(fetched.count, 1)
        
        // Delete
        try database.deleteEntry(id: entryId)
        fetched = try database.fetchAllEntries()
        XCTAssertTrue(fetched.isEmpty)
    }
    
    func test_fetch_ordering_newest_first() throws {
        let firstDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let secondDate = Date() // Now
        
        let entry1 = LibraryEntry(
            id: UUID(),
            filename: "old_song.mp3",
            originalPath: "/path/1",
            restoredPath: nil,
            restorationDate: firstDate,
            durationString: "2:00",
            sampleRateString: "44.1 kHz",
            preset: "streaming",
            measuredLUFS: nil,
            measuredTruePeak: nil,
            analysisResultData: Data(),
            waveformPointsData: Data()
        )
        
        let entry2 = LibraryEntry(
            id: UUID(),
            filename: "new_song.mp3",
            originalPath: "/path/2",
            restoredPath: nil,
            restorationDate: secondDate,
            durationString: "3:00",
            sampleRateString: "48.0 kHz",
            preset: "remaster",
            measuredLUFS: nil,
            measuredTruePeak: nil,
            analysisResultData: Data(),
            waveformPointsData: Data()
        )
        
        try database.saveEntry(entry1)
        try database.saveEntry(entry2)
        
        let fetched = try database.fetchAllEntries()
        XCTAssertEqual(fetched.count, 2)
        // Verify newest is first
        XCTAssertEqual(fetched[0].filename, "new_song.mp3")
        XCTAssertEqual(fetched[1].filename, "old_song.mp3")
    }
    
    func test_waveform_generator_handles_invalid_file_gracefully() {
        let invalidURL = URL(fileURLWithPath: "/invalid/path/to/music.mp3")
        let amplitudes = WaveformGenerator.generateAmplitudes(from: invalidURL, targetPoints: 10)
        XCTAssertEqual(amplitudes.count, 10)
        // Default fallback should be 0.05
        XCTAssertEqual(amplitudes.first, 0.05)
    }
}
