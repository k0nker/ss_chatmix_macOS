import SwiftUI

@main
struct SSChatMixApp: App {
    @NSApplicationDelegateAdaptor(MenuBarController.self) var menuBarController
    
    // Initialize Sparkle updater
    private let updater = SparkleUpdaterViewModel.shared
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
