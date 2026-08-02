import AppKit
import SwiftUI
import Combine
import SSChatMixCore

class MenuBarController: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    
    // Core components running in-process
    private var hidController: HIDController?
    private var audioController = AudioController()
    private var audioMonitor: AudioMonitor?
    
    // Current configuration
    private var config: Config?
    private let configManager = ConfigManager()
    
    // State
    @Published var gameVolume: Int = 50
    @Published var chatVolume: Int = 50
    @Published var isRunning: Bool = false
    @Published var statusMessage: String = "Not configured"
    
    // Windows
    var deviceSelectionWindow: NSWindow?
    var settingsWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemName: "slider.horizontal.3", accessibilityDescription: "ChatMix")
            button.image?.isTemplate = true
        }
        
        // Build menu
        updateMenu()
        
        // Load config if exists
        if configManager.exists() {
            do {
                config = try configManager.load()
                startController()
            } catch {
                statusMessage = "⚠️ Config error"
            }
        }
        
        // Update menu every second
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMenu()
        }
    }
    
    func updateMenu() {
        let menu = NSMenu()
        
        // Header
        menu.addItem(NSMenuItem(title: "ChatMix Controller", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // Volume display
        menu.addItem(NSMenuItem(title: "🎮 Game: \(gameVolume)%", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "💬 Chat: \(chatVolume)%", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // Status
        let statusItem = NSMenuItem(title: statusMessage, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(NSMenuItem.separator())
        
        // Device selection
        let devicesItem = NSMenuItem(title: "Select Devices...", action: #selector(showDeviceSelection), keyEquivalent: "d")
        devicesItem.target = self
        menu.addItem(devicesItem)
        
        // Restart
        if isRunning {
            let restartItem = NSMenuItem(title: "Restart Controller", action: #selector(restartController), keyEquivalent: "r")
            restartItem.target = self
            menu.addItem(restartItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        // About
        let aboutItem = NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        self.statusItem.menu = menu
    }
    
    func startController() {
        guard let config = config else {
            statusMessage = "⚙️ Not configured"
            return
        }
        
        // Stop existing controller
        stopController()
        
        do {
            // Find audio devices
            guard let gameDeviceID = try audioController.findDevice(byUID: config.audioDevices.game.uid) else {
                statusMessage = "❌ Game device not found"
                return
            }
            
            guard let chatDeviceID = try audioController.findDevice(byUID: config.audioDevices.chat.uid) else {
                statusMessage = "❌ Chat device not found"
                return
            }
            
            guard let outputUID = config.outputDeviceUid,
                  let outputDeviceID = try audioController.findDevice(byUID: outputUID) else {
                statusMessage = "❌ Output device not found"
                return
            }
            
            // Configure HID controller
            let vendorID = Int(config.hidDevice.vendorId.dropFirst(2), radix: 16) ?? 0x1038
            let productID = Int(config.hidDevice.productId.dropFirst(2), radix: 16) ?? 0x2202
            
            hidController = HIDController()
            hidController?.configure(vendorID: vendorID, productID: productID)
            
            // Create audio monitor
            let monitor = AudioMonitor(
                gameDeviceID: gameDeviceID,
                chatDeviceID: chatDeviceID,
                outputDeviceID: outputDeviceID
            )
            try monitor.start()
            audioMonitor = monitor
            
            // Set up HID callback
            hidController?.onDialChanged = { [weak self, weak monitor] gameVol, chatVol in
                DispatchQueue.main.async {
                    self?.gameVolume = gameVol
                    self?.chatVolume = chatVol
                }
                
                monitor?.updateVolumes(
                    game: Float(gameVol) / 100.0,
                    chat: Float(chatVol) / 100.0
                )
            }
            
            // Start listening
            try hidController?.start()
            
            isRunning = true
            statusMessage = "✅ Running"
            
            print("✅ ChatMix Controller started")
            
        } catch {
            statusMessage = "❌ Error: \(error.localizedDescription)"
            isRunning = false
        }
    }
    
    func stopController() {
        audioMonitor?.stop()
        audioMonitor = nil
        hidController?.stop()
        hidController = nil
        isRunning = false
    }
    
    @objc func restartController() {
        stopController()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startController()
        }
    }
    
    @objc func showDeviceSelection() {
        if deviceSelectionWindow == nil {
            let deviceView = DeviceSelectionView { [weak self] newConfig in
                self?.config = newConfig
                try? self?.configManager.save(newConfig)
                self?.startController()
                self?.deviceSelectionWindow?.close()
                self?.deviceSelectionWindow = nil
            }
            
            let hostingController = NSHostingController(rootView: deviceView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Select Devices"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 600, height: 500))
            window.center()
            
            deviceSelectionWindow = window
        }
        
        deviceSelectionWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func showSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView(config: config)
            let hostingController = NSHostingController(rootView: settingsView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Settings"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 500, height: 300))
            window.center()
            
            settingsWindow = window
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "SSChatMix"
        alert.informativeText = """
        Native macOS controller for SteelSeries Arctis Nova ChatMix dial.
        
        Version 1.0.0
        
        The controller runs inside this app - no external processes needed.
        """
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    @objc func quit() {
        stopController()
        NSApplication.shared.terminate(nil)
    }
}
