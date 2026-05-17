import SwiftUI
import AudioEngine

@main
struct SangeetAIApp: App {
    // ViewModel instance managed across the application lifecycle
    @StateObject private var viewModel = RestorationViewModel()
    
    var body: some Scene {
        WindowGroup {
            RestorationView(viewModel: viewModel)
                .frame(minWidth: 800, minHeight: 600)
                .frame(maxWidth: 800, maxHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
