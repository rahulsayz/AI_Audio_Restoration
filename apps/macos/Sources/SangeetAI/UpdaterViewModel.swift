import Foundation
import Sparkle
import Combine

/// Native macOS Sangeet AI Update Controller Wrapper
/// Handles update checking state and wraps the standard Sparkle 2.x updater.
public final class UpdaterViewModel: NSObject, ObservableObject {
    /// Controller managing the updater lifecycle and Sparkle's default user driver UI
    private let updaterController: SPUStandardUpdaterController
    
    /// Published property telling SwiftUI whether an update check is currently allowed
    @Published public var canCheckForUpdates = false
    
    public override init() {
        // Instantiate the SPUStandardUpdaterController with default driver delegates
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
        
        // Set the initial checkability state
        self.canCheckForUpdates = updaterController.updater.canCheckForUpdates
    }
    
    /// Triggers a manual, user-initiated update check with Sparkle's native alert/progress UI
    public func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
