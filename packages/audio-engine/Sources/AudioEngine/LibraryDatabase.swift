import Foundation
import GRDB

public final class LibraryDatabase {
    private let dbQueue: DatabaseQueue
    
    /// Initializes a SQLite connection and triggers automated schema migrations
    /// - Parameter storeURL: The local URL path of the sqlite database file.
    public init(storeURL: URL) throws {
        // Ensure the parent directories exist on disk
        let parentDir = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        
        // Initialize GRDB Database Queue
        self.dbQueue = try DatabaseQueue(path: storeURL.path)
        try migrate()
    }
    
    private func migrate() throws {
        var migrator = DatabaseMigrator()
        
        #if DEBUG
        // Speed up development migrations
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        
        migrator.registerMigration("createLibraryEntriesTable") { db in
            try db.create(table: LibraryEntry.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("filename", .text).notNull()
                t.column("originalPath", .text).notNull()
                t.column("restoredPath", .text)
                t.column("restorationDate", .datetime).notNull()
                t.column("durationString", .text).notNull()
                t.column("sampleRateString", .text).notNull()
                t.column("preset", .text).notNull()
                t.column("measuredLUFS", .double)
                t.column("measuredTruePeak", .double)
                t.column("analysisResultData", .blob).notNull()
                t.column("waveformPointsData", .blob).notNull()
            }
        }
        
        try migrator.migrate(dbQueue)
    }
    
    /// Persists a new or modified library entry
    public func saveEntry(_ entry: LibraryEntry) throws {
        var mutableEntry = entry
        try dbQueue.write { db in
            try mutableEntry.save(db)
        }
    }
    
    /// Fetches all library entries ordered newest first
    public func fetchAllEntries() throws -> [LibraryEntry] {
        try dbQueue.read { db in
            try LibraryEntry
                .order(Column("restorationDate").desc)
                .fetchAll(db)
        }
    }
    
    /// Purges a single entry by ID from the library
    public func deleteEntry(id: UUID) throws {
        _ = try dbQueue.write { db in
            try LibraryEntry.deleteOne(db, key: id)
        }
    }
}
