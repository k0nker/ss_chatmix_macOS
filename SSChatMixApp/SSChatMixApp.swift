import SwiftUI

@main
struct SSChatMixApp: App {
    @NSApplicationDelegateAdaptor(MenuBarController.self) var menuBarController
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
