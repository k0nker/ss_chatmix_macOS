import Sparkle
import Combine

// This view model class manages Sparkle's updater and publishes its state for SwiftUI
final class SparkleUpdaterViewModel: ObservableObject {
    static let shared = SparkleUpdaterViewModel()
    
    private let updaterController: SPUStandardUpdaterController
    
    @Published var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates = true
    
    private init() {
        // Create the updater controller which will start the updater automatically
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        
        // Observe canCheckForUpdates property
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        
        // Observe and sync automaticallyChecksForUpdates
        updaterController.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
    }
    
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
    
    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
    }
}
