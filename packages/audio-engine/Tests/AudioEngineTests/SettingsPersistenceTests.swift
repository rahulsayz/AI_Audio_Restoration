import XCTest
@testable import AudioEngine

final class SettingsPersistenceTests: XCTestCase {
    func test_tilde_expansion_resolves_correctly() {
        let tildePath = "~/Library/Application Support/SangeetAI/library.sqlite"
        let resolved = (tildePath as NSString).expandingTildeInPath
        
        XCTAssertFalse(resolved.contains("~"))
        XCTAssertTrue(resolved.contains("/Library/Application Support/SangeetAI/library.sqlite"))
        XCTAssertEqual(resolved, NSHomeDirectory() + "/Library/Application Support/SangeetAI/library.sqlite")
    }
    
    func test_default_settings_keys_setup() {
        // Assert keys can be read/written successfully in UserDefaults
        let mockPreset = "remaster"
        UserDefaults.standard.set(mockPreset, forKey: "defaultMasteringPreset")
        
        let retrieved = UserDefaults.standard.string(forKey: "defaultMasteringPreset")
        XCTAssertEqual(retrieved, mockPreset)
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: "defaultMasteringPreset")
    }
}
