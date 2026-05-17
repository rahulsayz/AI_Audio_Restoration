import XCTest
@testable import AudioEngine

final class InferenceClientTest: XCTestCase {
    func testInferenceClientCommunication() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let socketPath = tempDir.appendingPathComponent("sg_inf_\(Int.random(in: 1000...9999)).sock").path
        
        // Remove stale socket if any
        try? FileManager.default.removeItem(atPath: socketPath)
        
        let launcher = DaemonLauncher()
        do {
            try launcher.launch(socketPath: socketPath)
        } catch {
            XCTFail("Failed to launch daemon: \(error.localizedDescription)")
            return
        }
        
        defer {
            launcher.stop()
            try? FileManager.default.removeItem(atPath: socketPath)
        }
        
        let client = InferenceClient(socketPath: socketPath)
        
        // 1. Test GetCapabilities
        let caps = try await client.getCapabilities()
        XCTAssertEqual(caps.daemonVersion, "0.1.0")
        XCTAssertTrue(caps.supportedAudioFormats.contains("WAV"))
        
        // 2. Test ListModels
        let modelList = try await client.listModels()
        XCTAssertTrue(modelList.models.isEmpty)
    }
}
