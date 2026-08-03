import AppKit
import SwiftUI
import Combine

class MenuBarController: NSObject, NSApplicationDelegate, ObservableObject {
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
    
    // Available devices (published for SettingsView)
    @Published var availableChatMixDevices: [ChatMixDevice] = []
    @Published var availableAudioDevices: [AudioDeviceInfo] = []
    
    // Selected devices (published for SettingsView)
    @Published var selectedChatMixDevice: ChatMixDevice?
    @Published var selectedGameDevice: AudioDeviceInfo?
    @Published var selectedChatDevice: AudioDeviceInfo?
    @Published var selectedOutputDevice: AudioDeviceInfo?
    
    // Private cached lists
    private var availableHIDDevices: [ChatMixDevice] = []
    
    // Windows
    var settingsWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "ChatMix")
            button.image?.isTemplate = true
        }
        
        // Load available devices
        loadAvailableDevices()
        
        // Build menu
        updateMenu()
        
        // Load config if exists
        if configManager.exists() {
            do {
                config = try configManager.load()
                print("✅ Loaded config from: \(configManager.getConfigPath())")
                print("   Game: \(config!.audioDevices.game.name)")
                print("   Chat: \(config!.audioDevices.chat.name)")
                print("   Output: \(config!.outputDeviceUid ?? "not set")")
                print("   HID: \(config!.hidDevice.vendorId):\(config!.hidDevice.productId)")
                startController()
            } catch {
                print("❌ Failed to load config: \(error)")
                statusMessage = "⚠️ Config error"
            }
        } else {
            print("ℹ️ No config file found at: \(configManager.getConfigPath())")
            print("   Select devices from menu to configure")
        }
    }
    
    func loadAvailableDevices() {
        // Load HID devices
        let hidController = HIDController()
        availableHIDDevices = hidController.listChatMixDevices()
        availableChatMixDevices = availableHIDDevices // Publish for SwiftUI
        
        // Load audio devices
        do {
            let devices = try audioController.listOutputDevices()
            availableAudioDevices = devices // Publish for SwiftUI
        } catch {
            print("Failed to load audio devices: \(error)")
        }
        
        // Update selected devices from config
        updateSelectedDevicesFromConfig()
    }
    
    func updateSelectedDevicesFromConfig() {
        guard let config = config else {
            selectedChatMixDevice = nil
            selectedGameDevice = nil
            selectedChatDevice = nil
            selectedOutputDevice = nil
            return
        }
        
        // Find selected ChatMix device
        if let vendorID = Int(config.hidDevice.vendorId.dropFirst(2), radix: 16),
           let productID = Int(config.hidDevice.productId.dropFirst(2), radix: 16) {
            selectedChatMixDevice = availableChatMixDevices.first {
                $0.vendorID == vendorID && $0.productID == productID
            }
            if selectedChatMixDevice == nil {
                print("⚠️ ChatMix device not found in available list: VID=\(String(format: "0x%04X", vendorID)) PID=\(String(format: "0x%04X", productID))")
            }
        }
        
        // Find selected audio devices
        selectedGameDevice = availableAudioDevices.first { $0.uid == config.audioDevices.game.uid }
        if selectedGameDevice == nil {
            print("⚠️ Game device not found: \(config.audioDevices.game.uid)")
            print("   Available devices: \(availableAudioDevices.map { $0.uid }.joined(separator: ", "))")
        }
        
        selectedChatDevice = availableAudioDevices.first { $0.uid == config.audioDevices.chat.uid }
        if selectedChatDevice == nil {
            print("⚠️ Chat device not found: \(config.audioDevices.chat.uid)")
        }
        
        if let outputUID = config.outputDeviceUid {
            selectedOutputDevice = availableAudioDevices.first { $0.uid == outputUID }
            if selectedOutputDevice == nil {
                print("⚠️ Output device not found: \(outputUID)")
            }
        } else {
            selectedOutputDevice = nil
        }
    }
    
    func updateMenu() {
        let menu = NSMenu()
        
        // Header
        menu.addItem(NSMenuItem(title: "SSChatMix", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // Status
        let statusMenuItem = NSMenuItem(title: statusMessage, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())
        
        // Device selection submenus
        menu.addItem(buildChatMixDeviceMenu())
        menu.addItem(buildGameDeviceMenu())
        menu.addItem(buildChatDeviceMenu())
        menu.addItem(buildOutputDeviceMenu())
        
        // Restart
        if isRunning {
            menu.addItem(NSMenuItem.separator())
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
        
        // Refresh devices
        let refreshItem = NSMenuItem(title: "Refresh Devices", action: #selector(refreshDevices), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        self.statusItem.menu = menu
    }
    
    func buildChatMixDeviceMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "ChatMix Device", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        
        let currentVendorID = config.flatMap { Int($0.hidDevice.vendorId.dropFirst(2), radix: 16) }
        let currentProductID = config.flatMap { Int($0.hidDevice.productId.dropFirst(2), radix: 16) }
        
        if availableHIDDevices.isEmpty {
            let noneItem = NSMenuItem(title: "No devices found", action: nil, keyEquivalent: "")
            noneItem.isEnabled = false
            submenu.addItem(noneItem)
        } else {
            for device in availableHIDDevices {
                let title = "\(device.productName) (VID: \(String(format: "0x%04X", device.vendorID)) PID: \(String(format: "0x%04X", device.productID)))"
                let item = NSMenuItem(title: title, action: #selector(selectChatMixDeviceFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = device
                
                // Add checkmark if this is the current device
                if device.vendorID == currentVendorID && device.productID == currentProductID {
                    item.state = NSControl.StateValue.on
                }
                
                submenu.addItem(item)
            }
        }
        
        menuItem.submenu = submenu
        return menuItem
    }
    
    func buildGameDeviceMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Game Device", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        
        let currentUID = config?.audioDevices.game.uid
        
        if availableAudioDevices.isEmpty {
            let noneItem = NSMenuItem(title: "No devices found", action: nil, keyEquivalent: "")
            noneItem.isEnabled = false
            submenu.addItem(noneItem)
        } else {
            for device in availableAudioDevices {
                let item = NSMenuItem(title: device.name, action: #selector(selectGameDeviceFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = device
                
                if device.uid == currentUID {
                    item.state = NSControl.StateValue.on
                }
                
                submenu.addItem(item)
            }
        }
        
        menuItem.submenu = submenu
        return menuItem
    }
    
    func buildChatDeviceMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Chat Device", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        
        let currentUID = config?.audioDevices.chat.uid
        
        if availableAudioDevices.isEmpty {
            let noneItem = NSMenuItem(title: "No devices found", action: nil, keyEquivalent: "")
            noneItem.isEnabled = false
            submenu.addItem(noneItem)
        } else {
            for device in availableAudioDevices {
                let item = NSMenuItem(title: device.name, action: #selector(selectChatDeviceFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = device
                
                if device.uid == currentUID {
                    item.state = NSControl.StateValue.on
                }
                
                submenu.addItem(item)
            }
        }
        
        menuItem.submenu = submenu
        return menuItem
    }
    
    func buildOutputDeviceMenu() -> NSMenuItem {
        let menuItem = NSMenuItem(title: "Output Device", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        
        let currentUID = config?.outputDeviceUid
        
        if availableAudioDevices.isEmpty {
            let noneItem = NSMenuItem(title: "No devices found", action: nil, keyEquivalent: "")
            noneItem.isEnabled = false
            submenu.addItem(noneItem)
        } else {
            for device in availableAudioDevices {
                let item = NSMenuItem(title: device.name, action: #selector(selectOutputDeviceFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = device
                
                if device.uid == currentUID {
                    item.state = NSControl.StateValue.on
                }
                
                submenu.addItem(item)
            }
        }
        
        menuItem.submenu = submenu
        return menuItem
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
                print("❌ Game device not found: \(config.audioDevices.game.uid)")
                return
            }
            
            guard let chatDeviceID = try audioController.findDevice(byUID: config.audioDevices.chat.uid) else {
                statusMessage = "❌ Chat device not found"
                print("❌ Chat device not found: \(config.audioDevices.chat.uid)")
                return
            }
            
            guard let outputUID = config.outputDeviceUid,
                  let outputDeviceID = try audioController.findDevice(byUID: outputUID) else {
                statusMessage = "❌ Output device not found"
                print("❌ Output device not found: \(config.outputDeviceUid ?? "nil")")
                return
            }
            
            print("🎚️  Starting audio monitoring...")
            print("   Game input: Device \(gameDeviceID)")
            print("   Chat input: Device \(chatDeviceID)")
            print("   Output: Device \(outputDeviceID)")
            
            // Configure HID controller
            let vendorID = Int(config.hidDevice.vendorId.dropFirst(2), radix: 16) ?? 0x1038
            let productID = Int(config.hidDevice.productId.dropFirst(2), radix: 16) ?? 0x2202
            
            print("🎮 Configuring HID controller...")
            print("   VendorID: \(String(format: "0x%04X", vendorID))")
            print("   ProductID: \(String(format: "0x%04X", productID))")
            
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
            
            print("✅ Audio monitoring started")
            
            // Set up HID callback
            hidController?.onDialChanged = { [weak self, weak monitor] gameVol, chatVol in
                // Update audio volumes immediately (time-critical)
                monitor?.updateVolumes(
                    game: Float(gameVol) / 100.0,
                    chat: Float(chatVol) / 100.0
                )
                
                // Update UI asynchronously (non-blocking)
                DispatchQueue.main.async { [weak self] in
                    self?.gameVolume = gameVol
                    self?.chatVolume = chatVol
                }
            }
            
            // Start listening
            print("🎮 Starting HID controller...")
            try hidController?.start()
            print("✅ HID controller started")
            
            isRunning = true
            statusMessage = "✅ Running"
            
            print("")
            print("✅ ChatMix Controller started")
            print("   Move the dial to test...")
            
        } catch AudioMonitorError.permissionDenied {
            print("❌ Microphone permission denied")
            statusMessage = "🎤 Microphone permission required"
            isRunning = false
            
            // Show alert to user
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Microphone Permission Required"
                alert.informativeText = "SSChatMix needs microphone access to capture audio from virtual devices.\n\nPlease grant microphone permission in:\nSystem Settings > Privacy & Security > Microphone\n\nThen restart the app."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "OK")
                
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    // Open System Settings to Privacy > Microphone
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        } catch {
            print("❌ Controller start failed: \(error)")
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
    
    @objc func selectChatMixDeviceFromMenu(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? ChatMixDevice else { return }
        selectChatMixDevice(device)
    }
    
    @objc func selectGameDeviceFromMenu(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? AudioDeviceInfo else { return }
        selectGameDevice(device)
    }
    
    @objc func selectChatDeviceFromMenu(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? AudioDeviceInfo else { return }
        selectChatDevice(device)
    }
    
    @objc func selectOutputDeviceFromMenu(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? AudioDeviceInfo else { return }
        selectOutputDevice(device)
    }
    
    // Public methods for SettingsView to call
    func selectChatMixDevice(_ device: ChatMixDevice) {
        updateHIDDevice(device)
    }
    
    func selectGameDevice(_ device: AudioDeviceInfo) {
        updateGameDevice(device)
    }
    
    func selectChatDevice(_ device: AudioDeviceInfo) {
        updateChatDevice(device)
    }
    
    func selectOutputDevice(_ device: AudioDeviceInfo) {
        updateOutputDevice(device)
    }
    
    @objc func refreshDevices() {
        loadAvailableDevices()
        updateMenu()
    }
    
    func updateHIDDevice(_ device: ChatMixDevice) {
        if config == nil {
            // Create minimal config with this device
            config = Config(
                audioDevices: AudioDevicesConfig(
                    game: AudioDeviceConfig(id: "", name: "Not configured", uid: "", isAggregate: false),
                    chat: AudioDeviceConfig(id: "", name: "Not configured", uid: "", isAggregate: false)
                ),
                hidDevice: HIDDeviceConfig(
                    vendorId: String(format: "0x%04X", device.vendorID),
                    productId: String(format: "0x%04X", device.productID)
                ),
                launchAgentEnabled: false,
                monitoringMode: true,
                outputDeviceUid: nil
            )
        } else if let currentConfig = config {
            config = Config(
                audioDevices: currentConfig.audioDevices,
                hidDevice: HIDDeviceConfig(
                    vendorId: String(format: "0x%04X", device.vendorID),
                    productId: String(format: "0x%04X", device.productID)
                ),
                launchAgentEnabled: currentConfig.launchAgentEnabled,
                monitoringMode: currentConfig.monitoringMode,
                outputDeviceUid: currentConfig.outputDeviceUid
            )
        }
        
        saveAndRestart()
    }
    
    func updateGameDevice(_ device: AudioDeviceInfo) {
        if config == nil {
            // Create minimal config with this device
            config = Config(
                audioDevices: AudioDevicesConfig(
                    game: AudioDeviceConfig(
                        id: String(device.id),
                        name: device.name,
                        uid: device.uid,
                        isAggregate: device.isAggregate
                    ),
                    chat: AudioDeviceConfig(id: "", name: "Not configured", uid: "", isAggregate: false)
                ),
                hidDevice: HIDDeviceConfig(vendorId: "0x0000", productId: "0x0000"),
                launchAgentEnabled: false,
                monitoringMode: true,
                outputDeviceUid: nil
            )
        } else if let currentConfig = config {
            config = Config(
                audioDevices: AudioDevicesConfig(
                    game: AudioDeviceConfig(
                        id: String(device.id),
                        name: device.name,
                        uid: device.uid,
                        isAggregate: device.isAggregate
                    ),
                    chat: currentConfig.audioDevices.chat
                ),
                hidDevice: currentConfig.hidDevice,
                launchAgentEnabled: currentConfig.launchAgentEnabled,
                monitoringMode: currentConfig.monitoringMode,
                outputDeviceUid: currentConfig.outputDeviceUid
            )
        }
        
        saveAndRestart()
    }
    
    func updateChatDevice(_ device: AudioDeviceInfo) {
        if config == nil {
            // Create minimal config with this device
            config = Config(
                audioDevices: AudioDevicesConfig(
                    game: AudioDeviceConfig(id: "", name: "Not configured", uid: "", isAggregate: false),
                    chat: AudioDeviceConfig(
                        id: String(device.id),
                        name: device.name,
                        uid: device.uid,
                        isAggregate: device.isAggregate
                    )
                ),
                hidDevice: HIDDeviceConfig(vendorId: "0x0000", productId: "0x0000"),
                launchAgentEnabled: false,
                monitoringMode: true,
                outputDeviceUid: nil
            )
        } else if let currentConfig = config {
            config = Config(
                audioDevices: AudioDevicesConfig(
                    game: currentConfig.audioDevices.game,
                    chat: AudioDeviceConfig(
                        id: String(device.id),
                        name: device.name,
                        uid: device.uid,
                        isAggregate: device.isAggregate
                    )
                ),
                hidDevice: currentConfig.hidDevice,
                launchAgentEnabled: currentConfig.launchAgentEnabled,
                monitoringMode: currentConfig.monitoringMode,
                outputDeviceUid: currentConfig.outputDeviceUid
            )
        }
        
        saveAndRestart()
    }
    
    func updateOutputDevice(_ device: AudioDeviceInfo) {
        if config == nil {
            // Create minimal config with this device
            config = Config(
                audioDevices: AudioDevicesConfig(
                    game: AudioDeviceConfig(id: "", name: "Not configured", uid: "", isAggregate: false),
                    chat: AudioDeviceConfig(id: "", name: "Not configured", uid: "", isAggregate: false)
                ),
                hidDevice: HIDDeviceConfig(vendorId: "0x0000", productId: "0x0000"),
                launchAgentEnabled: false,
                monitoringMode: true,
                outputDeviceUid: device.uid
            )
        } else if let currentConfig = config {
            config = Config(
                audioDevices: currentConfig.audioDevices,
                hidDevice: currentConfig.hidDevice,
                launchAgentEnabled: currentConfig.launchAgentEnabled,
                monitoringMode: currentConfig.monitoringMode,
                outputDeviceUid: device.uid
            )
        }
        
        saveAndRestart()
    }
    
    func saveAndRestart() {
        guard let config = config else { return }
        
        do {
            try configManager.save(config)
            print("✅ Config saved to: \(configManager.getConfigPath())")
            print("   Game: \(config.audioDevices.game.name)")
            print("   Chat: \(config.audioDevices.chat.name)")
            print("   Output: \(config.outputDeviceUid ?? "not set")")
            print("   HID: \(config.hidDevice.vendorId):\(config.hidDevice.productId)")
            
            // Update selected devices for UI
            updateSelectedDevicesFromConfig()
            
            stopController()
            startController()
            updateMenu()
        } catch {
            print("❌ Failed to save config: \(error)")
            statusMessage = "❌ Failed to save config"
        }
    }
    
    @objc func showSettings() {
        // Refresh device lists and selections before showing window
        // Do this on background thread to avoid blocking audio
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Load devices on background thread
            let hidController = HIDController()
            let hidDevices = hidController.listChatMixDevices()
            
            var audioDevices: [AudioDeviceInfo] = []
            do {
                audioDevices = try self.audioController.listOutputDevices()
            } catch {
                print("⚠️ Failed to load audio devices: \(error)")
            }
            
            // Update on main thread (batched to minimize blocking)
            DispatchQueue.main.async {
                self.availableHIDDevices = hidDevices
                self.availableChatMixDevices = hidDevices
                self.availableAudioDevices = audioDevices
                self.updateSelectedDevicesFromConfig()
                
                // Now show window with fresh data
                let settingsView = SettingsView(controller: self)
                let hostingController = NSHostingController(rootView: settingsView)
                
                let window = NSWindow(contentViewController: hostingController)
                window.title = "SSChatMix Settings"
                window.styleMask = [.titled, .closable, .resizable]
                window.setContentSize(NSSize(width: 550, height: 600))
                window.center()
                
                self.settingsWindow = window
                self.settingsWindow?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
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
