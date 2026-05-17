# ADR-002: Use GRDB.swift for Native macOS Project Library Persistence

Date: 2026-05-17
Status: Accepted

## Context
Sangeet AI requires a native, fast, and robust local persistence solution to store a user's past audio restorations. 
The requirements are:
1. Store metadata (dates, paths, durations, selected presets, measured audio metrics).
2. Store serialized binary data (protobuf `SangeetV1AnalysisResult` and `[Float]` downsampled waveforms).
3. Support query filtering, sorted retrieval (newest first), and transactional single-record deletion.
4. Support simple, robust schema migrations over the lifecycle of Sangeet AI Phase 1 to Phase 3.
5. Work seamlessly on macOS 13 Ventura without cloud-sync overhead.

## Decision
We will use **GRDB.swift** (version `6.27.0`) linked via Swift Package Manager to the local `audio-engine` package. GRDB is a modern SQLite toolkit designed for Swift, offering type-safe record protocols, excellent concurrency guarantees via database queues, and highly responsive read/write speeds.

## Consequences
- **Pros**:
  - Extremely fast read/write speeds, matching raw SQLite performance.
  - Type-safe object mapping through the standard `Codable` and GRDB `Record` protocols, eliminating mapping boilerplate.
  - Robust built-in `DatabaseMigrator` to safely update database schemas between releases.
  - Low memory footprint.
- **Cons**:
  - Introduces one new Swift Package Manager dependency to the build chain.

## Alternatives considered

### 1. SQLite.swift / Raw SQLite C APIs
- **Why rejected**: Writing raw SQL or utilizing light wrappers like SQLite.swift requires high boilerplate overhead to write type-safe mappings, manual migration orchestrations, and query binding. It slows down development and increases structural bug risk.

### 2. Apple Core Data
- **Why rejected**: Core Data is an object graph manager, not just a database. It introduces significant conceptual and execution overhead (persistent store setups, heavy context management across threads, custom threading models, and `.xcdatamodeld` visual files). For a lightweight local single-table history, Core Data is excessively complex and prone to visual schema merging conflicts.

### 3. Plain JSON Files
- **Why rejected**: Storing the history as a single JSON array on disk is extremely fragile. Deleting a single item, sorting, or appending requires deserializing the entire document into memory, modifying it, and writing it back out. If the application crashes or loses power during a write, the entire library history is lost.
