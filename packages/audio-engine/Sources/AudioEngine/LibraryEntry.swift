import Foundation
import GRDB

public struct LibraryEntry: Codable, FetchableRecord, MutablePersistableRecord {
    // Define the database table name
    public static let databaseTableName = "library_entries"
    
    public var id: UUID
    public var filename: String
    public var originalPath: String
    public var restoredPath: String?
    public var restorationDate: Date
    public var durationString: String
    public var sampleRateString: String
    public var preset: String
    public var measuredLUFS: Double?
    public var measuredTruePeak: Double?
    public var analysisResultData: Data // Binary protobuf SangeetV1AnalysisResult
    public var waveformPointsData: Data // JSON serialized [Float]
    
    public init(
        id: UUID = UUID(),
        filename: String,
        originalPath: String,
        restoredPath: String?,
        restorationDate: Date = Date(),
        durationString: String,
        sampleRateString: String,
        preset: String,
        measuredLUFS: Double?,
        measuredTruePeak: Double?,
        analysisResultData: Data,
        waveformPointsData: Data
    ) {
        self.id = id
        self.filename = filename
        self.originalPath = originalPath
        self.restoredPath = restoredPath
        self.restorationDate = restorationDate
        self.durationString = durationString
        self.sampleRateString = sampleRateString
        self.preset = preset
        self.measuredLUFS = measuredLUFS
        self.measuredTruePeak = measuredTruePeak
        self.analysisResultData = analysisResultData
        self.waveformPointsData = waveformPointsData
    }
}
