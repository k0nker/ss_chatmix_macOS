import AppKit
import SwiftUI
import SSChatMixCore

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var runCommand: RunCommand?
    var configManager = ConfigManager()
    var audioController = AudioController()
    var processManager = ProcessManager()
    var preferencesWindow: NSWindow?
    
    // Volume state
    @Published var gameVolume: Int = 50
    @Published var chatVolume: Int = 50
    @Published var isRunning: Bool = false
    @Published var statusMessage: String = "Initializing..."
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "ChatMix")
            button.image?.isTemplate = true
        }
        
        // Build menu
        setupMenu()
        
        // Check if configured
        if configManager.exists() {
            startController()
        } else {
            statusMessage = "Not configured - Click to setup"
        }
        
        // Update menu every second
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMenu()
        }
    }
    
    func setupMenu() {
        let menu = NSMenu()
        
        // Status section
        menu.addItem(NSMenuItem(title: "ChatMix Controller", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // Volume indicators
        menu.addItem(NSMenuItem(title: "Game: \(gameVolume)%", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Chat: \(chatVolume)%", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // Status
        let statusMenuItem = NSMenuItem(title: statusMessage, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())
        
        // Actions
        if configManager.exists() {
            let restartItem = NSMenuItem(title: "Restart Controller", action: #selector(restartController), keyEquivalent: "r")
            restartItem.target = self
            menu.addItem(restartItem)
            
            let changeDevicesItem = NSMenuItem(title: "Change Devices", action: #selector(changeDevices), keyEquivalent: "d")
            changeDevicesItem.target = self
            menu.addItem(changeDevicesItem)
        } else {
            let setupItem = NSMenuItem(title: "Setup...", action: #selector(runSetup), keyEquivalent: "s")
            setupItem.target = self
            menu.addItem(setupItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)
        
        let aboutItem = NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        self.statusItem.menu = menu
    }
    
    func updateMenu() {
        // Check if controller is running
        isRunning = processManager.isAlreadyRunning()
        
        if isRunning {
            statusMessage = "✅ Running"
        } else if configManager.exists() {
            statusMessage = "⚠️ Not running"
        } else {
            statusMessage = "⚙️ Not configured"
        }
        
        // Rebuild menu with updated state
        setupMenu()
    }
    
    func startController() {
        // Check if already running
        if processManager.isAlreadyRunning() {
            statusMessage = "✅ Already running"
            isRunning = true
            return
        }
        
        runCommand = RunCommand()
        
        // Set up volume callback
        runCommand?.onVolumeChanged = { [weak self] game, chat in
            DispatchQueue.main.async {
                self?.gameVolume = game
                self?.chatVolume = chat
            }
        }
        
        // Start in background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try self?.runCommand?.execute()
            } catch {
                DispatchQueue.main.async {
                    self?.statusMessage = "❌ Error: \(error.localizedDescription)"
                    self?.isRunning = false
                }
            }
        }
        
        // Give it a moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isRunning = self?.processManager.isAlreadyRunning() ?? false
            if self?.isRunning == true {
                self?.statusMessage = "✅ Running"
            }
        }
    }
    
    @objc func restartController() {
        // Kill existing process
        try? processManager.killRunningProcess()
        
        // Wait a moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startController()
        }
    }
    
    @objc func changeDevices() {
        let alert = NSAlert()
        alert.messageText = "Change Devices"
        alert.informativeText = "This will open Terminal to run the device selection wizard."
        alert.addButton(withTitle: "Open Terminal")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        
        if alert.runModal() == .alertFirstButtonReturn {
            // Open terminal and run device command
            let script = "tell application \"Terminal\" to do script \"sschatmix --device\""
            if let scriptObject = NSAppleScript(source: script) {
                var error: NSDictionary?
                scriptObject.executeAndReturnError(&error)
            }
        }
    }
    
    @objc func runSetup() {
        let alert = NSAlert()
        alert.messageText = "Initial Setup"
        alert.informativeText = "This will open Terminal to run the setup wizard."
        alert.addButton(withTitle: "Open Terminal")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        
        if alert.runModal() == .alertFirstButtonReturn {
            // Open terminal and run setup
            let script = "tell application \"Terminal\" to do script \"sschatmix --setup\""
            if let scriptObject = NSAppleScript(source: script) {
                var error: NSDictionary?
                scriptObject.executeAndReturnError(&error)
            }
        }
    }
    
    @objc func showPreferences() {
        if preferencesWindow == nil {
            let prefsView = PreferencesView()
            let hostingController = NSHostingController(rootView: prefsView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Preferences"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 500, height: 400))
            window.center()
            
            preferencesWindow = window
        }
        
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "SSChatMix"
        alert.informativeText = """
        Native macOS controller for SteelSeries Arctis Nova ChatMix dial.
        
        Version 1.0.0
        
        Created because SteelSeries doesn't support SONAR on macOS.
        """
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    @objc func quit() {
        // Stop controller if running
        try? processManager.killRunningProcess()
        NSApplication.shared.terminate(nil)
    }
}
