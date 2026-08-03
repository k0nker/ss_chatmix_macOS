import Sparkle
import Foundation

final class SparkleUpdater: NSObject, ObservableObject {
    static let shared = SparkleUpdater()
    
    let updater: SPUUpdater
    
    @Published var canCheckForUpdates = false
    @Published var isAutomaticallyChecksForUpdates = true
    
    override init() {
        // Initialize updater with GitHub releases feed
        // Replace USERNAME and REPO with your GitHub details
        let hostBundle = Bundle.main
        self.updater = SPUUpdater(hostBundle: hostBundle)!
        
        super.init()
        
        // Set the update feed URL (GitHub releases as Sparkle appcast)
        // Format: https://github.com/USERNAME/REPO/releases.atom
        updater.feedURL = URL(string: "https://github.com/k0nker/ss_chatmix_macOS/releases.atom")
        updater.delegate = self
        
        // Start automatic update checks
        updater.startUpdatingAndDisplayingUserInterface()
        
        // Observe automatic check setting
        self.isAutomaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
    }
    
    func checkForUpdates() {
        updater.checkForUpdates()
    }
    
    func toggleAutomaticUpdates(_ enabled: Bool) {
        updater.automaticallyChecksForUpdates = enabled
        isAutomaticallyChecksForUpdates = enabled
    }
}

// MARK: - SPUUpdaterDelegate

extension SparkleUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFinishChecking updateItems: [SUAppcastItem], isUpdateAvailable: Bool) {
        // Called when update check completes
        print("Update check complete. Available: \(isUpdateAvailable)")
    }
    
    func updaterDidNotFind(anUpdateWithLatestUserProfile latestProfile: SUAppcastItem) {
        // Called when no update is available
        print("No update available")
    }
}
