import AppKit
import SwiftUI
import Combine
import CoreAudio
import Sparkle

class MenuBarController: NSObject, NSApplicationDelegate, ObservableObject {
    var statusItem: NSStatusItem!
    
    // Core components running in-process
    private var hidController: HIDController?
    private var audioController = AudioController()
    private var audioRouter: AudioRouter?
    
    // Device IDs for volume control
    private var gameDeviceID: AudioDeviceID?
    private var chatDeviceID: AudioDeviceID?
    
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
        // Set app icon for Dock, notifications, etc.
        NSApplication.shared.applicationIconImage = createAppIcon()
        
        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = createMenuBarIcon()
            button.image?.isTemplate = true
        }
        
        // Load available devices asynchronously to avoid blocking main thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.loadAvailableDevices()
            
            // Build menu on main thread after devices loaded
            DispatchQueue.main.async {
                self?.updateMenu()
            }
        }
        
        // Load config if exists
        if configManager.exists() {
            do {
                config = try configManager.load()
                print("Loaded config from: \(configManager.getConfigPath())")
                print("   Game: \(config!.audioDevices.game.name)")
                print("   Chat: \(config!.audioDevices.chat.name)")
                print("   Output: \(config!.outputDeviceUid ?? "not set")")
                print("   HID: \(config!.hidDevice.vendorId):\(config!.hidDevice.productId)")
                
                // Start controller (no permissions needed!)
                startController()
            } catch {
                print("Config error: \(error)")
                statusMessage = "Config error"
            }
        } else {
            print("No config file found at: \(configManager.getConfigPath())")
            print("   Using SSChatMix defaults...")
            tryCreateDefaultConfig()
        }
    }
    
    // MARK: - App Icon
    
    /// Creates the app icon for Dock, notifications, etc. (no status indicator)
    private func createAppIcon() -> NSImage {
        let iconSize = NSSize(width: 512, height: 512)
        let image = NSImage(size: iconSize)
        
        image.lockFocus()
        
        // Draw rounded rectangle background (macOS icon style)
        let backgroundRect = NSRect(x: 0, y: 0, width: iconSize.width, height: iconSize.height)
        let cornerRadius: CGFloat = iconSize.width * 0.225 // Standard macOS icon corner radius
        let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: cornerRadius, yRadius: cornerRadius)
        
        // Use gradient background
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.2, green: 0.5, blue: 0.8, alpha: 1.0),
            NSColor(calibratedRed: 0.1, green: 0.3, blue: 0.6, alpha: 1.0)
        ])
        gradient?.draw(in: backgroundPath, angle: -45)
        
        // Draw headphones symbol (background layer)
        if let headphonesSymbol = NSImage(systemSymbolName: "headphones", accessibilityDescription: "Audio") {
            let symbolSize = NSSize(width: 380, height: 380)
            let symbolRect = NSRect(x: 66, y: 66, width: symbolSize.width, height: symbolSize.height)
            NSColor.white.withAlphaComponent(0.9).setFill()
            headphonesSymbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
        
        // Draw play icon on top (centered, slightly smaller)
        if let playSymbol = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play") {
            let playSize = NSSize(width: 180, height: 180)
            let playRect = NSRect(
                x: (iconSize.width - playSize.width) / 2 + 10,
                y: (iconSize.height - playSize.height) / 2,
                width: playSize.width,
                height: playSize.height
            )
            NSColor.white.setFill()
            playSymbol.draw(in: playRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
        
        image.unlockFocus()
        image.isTemplate = false
        
        return image
    }
    
    // MARK: - Menu Bar Icon
    
    /// Creates a custom menu bar icon with play symbol and headphones
    private func createMenuBarIcon() -> NSImage {
        let iconSize = NSSize(width: 22, height: 22)
        let image = NSImage(size: iconSize)
        
        image.lockFocus()
        
        // Draw headphones symbol (background layer)
        if let headphonesSymbol = NSImage(systemSymbolName: "headphones", accessibilityDescription: "Audio") {
            let symbolSize = NSSize(width: 18, height: 18)
            let symbolRect = NSRect(x: 2, y: 2, width: symbolSize.width, height: symbolSize.height)
            headphonesSymbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
        
        // Draw play icon on top (centered, slightly smaller)
        if let playSymbol = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play") {
            let playSize = NSSize(width: 9, height: 9)
            let playRect = NSRect(
                x: (iconSize.width - playSize.width) / 2 + 0.5,
                y: (iconSize.height - playSize.height) / 2,
                width: playSize.width,
                height: playSize.height
            )
            playSymbol.draw(in: playRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
        
        image.unlockFocus()
        image.isTemplate = true  // Template mode to adapt to menu bar theme
        
        return image
    }
    
    /// Updates the menu bar icon based on current status
    private func updateMenuBarIcon() {
        if let button = statusItem.button {
            button.image = createMenuBarIcon()
        }
    }
    
    // MARK: - Device Management
    
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
                print("ChatMix device not found in available list: VID=\(String(format: "0x%04X", vendorID)) PID=\(String(format: "0x%04X", productID))")
            }
        }
        
        // Find selected audio devices
        selectedGameDevice = availableAudioDevices.first { $0.uid == config.audioDevices.game.uid }
        if selectedGameDevice == nil {
            print("Game device not found: \(config.audioDevices.game.uid)")
            print("   Available devices: \(availableAudioDevices.map { $0.uid }.joined(separator: ", "))")
        }
        
        selectedChatDevice = availableAudioDevices.first { $0.uid == config.audioDevices.chat.uid }
        if selectedChatDevice == nil {
            print("Chat device not found: \(config.audioDevices.chat.uid)")
        }
        
        if let outputUID = config.outputDeviceUid {
            selectedOutputDevice = availableAudioDevices.first { $0.uid == outputUID }
            if selectedOutputDevice == nil {
                print("Output device not found: \(outputUID)")
            }
        } else {
            selectedOutputDevice = nil
        }
    }
    
    // MARK: - Default Configuration
    
    /// Try to create a default configuration using SSChatMix devices
    private func tryCreateDefaultConfig() {
        do {
            // Try to find SSChatMix devices
            guard let gameDevice = try audioController.findSSChatMixGameDevice(),
                  let chatDevice = try audioController.findSSChatMixChatDevice() else {
                print("SSChatMix devices not found - user must configure manually")
                statusMessage = "Configure devices in Settings"
                return
            }
            
            print("Found SSChatMix devices - creating default config")
            print("   Game: \(gameDevice.name)")
            print("   Chat: \(chatDevice.name)")
            
            // Find first non-virtual output device as default
            let devices = try audioController.listOutputDevices()
            guard let outputDevice = devices.first(where: { !$0.name.contains("SSChatMix") && !$0.name.contains("BlackHole") }) else {
                print("No physical output device found")
                statusMessage = "Configure output device in Settings"
                return
            }
            
            // Create default config
            let defaultConfig = Config(
                audioDevices: AudioDevicesConfig(
                    game: AudioDeviceConfig(
                        id: String(gameDevice.id),
                        name: gameDevice.name,
                        uid: gameDevice.uid,
                        isAggregate: false
                    ),
                    chat: AudioDeviceConfig(
                        id: String(chatDevice.id),
                        name: chatDevice.name,
                        uid: chatDevice.uid,
                        isAggregate: false
                    )
                ),
                hidDevice: HIDDeviceConfig(
                    vendorId: "0x1038",
                    productId: "0x2202"
                ),
                launchAgentEnabled: false,
                outputDeviceUid: outputDevice.uid
            )
            
            try configManager.save(defaultConfig)
            config = defaultConfig
            
            print("Created default config with output: \(outputDevice.name)")
            print("Starting controller...")
            
            // Reload devices and start
            loadAvailableDevices()
            startController()
            
        } catch {
            print("Failed to create default config: \(error)")
            statusMessage = "Configure devices in Settings"
        }
    }
    
    // MARK: - Menu Bar
    
    func updateMenu() {
        let menu = NSMenu()
        
        // Header
        menu.addItem(NSMenuItem(title: "SSChatMix", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // Status with icon
        let statusMenuItem = NSMenuItem(title: statusMessage, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        
        // Add appropriate icon based on status
        if isRunning {
            statusMenuItem.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Running")
            statusMenuItem.image?.isTemplate = false
            if let image = statusMenuItem.image {
                let tinted = image.withSymbolConfiguration(.init(paletteColors: [.systemGreen]))
                statusMenuItem.image = tinted
            }
        } else if statusMessage.contains("permission") {
            statusMenuItem.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning")
            statusMenuItem.image?.isTemplate = false
            if let image = statusMenuItem.image {
                let tinted = image.withSymbolConfiguration(.init(paletteColors: [.systemYellow]))
                statusMenuItem.image = tinted
            }
        } else if statusMessage.contains("not found") || statusMessage.contains("Error") {
            statusMenuItem.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Error")
            statusMenuItem.image?.isTemplate = false
            if let image = statusMenuItem.image {
                let tinted = image.withSymbolConfiguration(.init(paletteColors: [.systemRed]))
                statusMenuItem.image = tinted
            }
        } else {
            statusMenuItem.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Status")
            statusMenuItem.image?.isTemplate = false
            if let image = statusMenuItem.image {
                let tinted = image.withSymbolConfiguration(.init(paletteColors: [.systemGray]))
                statusMenuItem.image = tinted
            }
        }
        
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())
        
        // Device selection submenus
        menu.addItem(buildChatMixDeviceMenu())
        menu.addItem(buildGameDeviceMenu())
        menu.addItem(buildChatDeviceMenu())
        menu.addItem(buildOutputDeviceMenu())
        
        menu.addItem(NSMenuItem.separator())
        
        // Restart (always visible - can start if stopped, or restart if running)
        let restartItem = NSMenuItem(title: isRunning ? "Restart Controller" : "Start Controller", action: #selector(restartController), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)
        
        // Reload (always visible)
        let reloadItem = NSMenuItem(title: "Reload", action: #selector(reloadConfig), keyEquivalent: "R")
        reloadItem.target = self
        menu.addItem(reloadItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Check for Updates
        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        
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
        
        // Update menu bar icon to reflect current status
        updateMenuBarIcon()
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
            statusMessage = "Not configured"
            return
        }
        
        // Stop existing controller
        stopController()
        
        do {
            // Find audio devices (SSChatMix virtual devices)
            guard let foundGameDeviceID = try audioController.findDevice(byUID: config.audioDevices.game.uid) else {
                statusMessage = "Game device not found"
                print("Game device not found: \(config.audioDevices.game.uid)")
                print("   Make sure SSChatMixPlugin is installed at /Library/Audio/Plug-Ins/HAL/")
                return
            }
            
            guard let foundChatDeviceID = try audioController.findDevice(byUID: config.audioDevices.chat.uid) else {
                statusMessage = "Chat device not found"
                print("Chat device not found: \(config.audioDevices.chat.uid)")
                print("   Make sure SSChatMixPlugin is installed at /Library/Audio/Plug-Ins/HAL/")
                return
            }
            
            // Store device IDs for volume control
            self.gameDeviceID = foundGameDeviceID
            self.chatDeviceID = foundChatDeviceID
            
            print("Found SSChatMix devices:")
            print("   Game: Device \(foundGameDeviceID)")
            print("   Chat: Device \(foundChatDeviceID)")
            print("")
            
            // Find output device
            guard let outputUID = config.outputDeviceUid,
                  let foundOutputDeviceID = try audioController.findDevice(byUID: outputUID) else {
                statusMessage = "Output device not found"
                print("Output device not found: \(config.outputDeviceUid ?? "none")")
                return
            }
            
            print("Output device: \(foundOutputDeviceID)")
            print("")
            print("Audio Flow:")
            print("  1. Apps write to SSChatMix virtual output streams")
            print("  2. Plugin stores in ring buffers (loopback)")
            print("  3. Swift app reads from SSChatMix input streams")
            print("  4. Swift app mixes Game + Chat with volumes")
            print("  5. Swift app writes to physical output device")
            print("")
            
            // Configure HID controller
            let vendorID = Int(config.hidDevice.vendorId.dropFirst(2), radix: 16) ?? 0x1038
            let productID = Int(config.hidDevice.productId.dropFirst(2), radix: 16) ?? 0x2202
            
            print("Configuring HID controller...")
            print("   VendorID: \(String(format: "0x%04X", vendorID))")
            print("   ProductID: \(String(format: "0x%04X", productID))")
            
            hidController = HIDController()
            hidController?.configure(vendorID: vendorID, productID: productID)
            
            // Set up HID callback to control volumes
            hidController?.onDialChanged = { [weak self] gameVol, chatVol in
                guard let self = self else { return }
                
                // Update audio router volumes (real-time mixing)
                self.audioRouter?.updateVolumes(game: Float(gameVol), chat: Float(chatVol))
                
                // Update UI asynchronously (non-blocking)
                DispatchQueue.main.async {
                    self.gameVolume = gameVol
                    self.chatVolume = chatVol
                }
            }
            
            // Start listening to HID
            print("Starting HID controller...")
            try hidController?.start()
            print("HID controller started")
            
            // Start audio routing
            print("Starting audio router...")
            let router = AudioRouter(
                gameDeviceID: foundGameDeviceID,
                chatDeviceID: foundChatDeviceID,
                outputDeviceID: foundOutputDeviceID
            )
            try router.start()
            router.updateVolumes(game: 50.0, chat: 50.0) // Initial 50/50 balance
            self.audioRouter = router
            print("Audio router started")
            
            isRunning = true
            statusMessage = "Running"
            
            // Update menu to show new status
            updateMenu()
            
            print("")
            print("✅ SSChatMix started successfully!")
            print("   Move the dial to adjust Game/Chat balance")
            print("   Audio is now routing through loopback devices")
            print("")
            
        } catch {
            print("Controller start failed: \(error)")
            statusMessage = "Error: \(error.localizedDescription)"
            isRunning = false
            updateMenuBarIcon()
        }
    }
    
    func stopController() {
        audioRouter?.stop()
        audioRouter = nil
        hidController?.stop()
        hidController = nil
        gameDeviceID = nil
        chatDeviceID = nil
        isRunning = false
        updateMenuBarIcon()
    }
    
    @objc func restartController() {
        stopController()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startController()
        }
    }
    
    @objc func reloadConfig() {
        print("🔄 Reloading configuration...")
        
        // Stop current controller if running
        stopController()
        
        // Reload config
        if configManager.exists() {
            do {
                config = try configManager.load()
                print("✅ Config reloaded from: \(configManager.getConfigPath())")
                print("   Game: \(config!.audioDevices.game.name)")
                print("   Chat: \(config!.audioDevices.chat.name)")
                print("   Output: \(config!.outputDeviceUid ?? "not set")")
                print("   HID: \(config!.hidDevice.vendorId):\(config!.hidDevice.productId)")
                
                // Refresh device lists
                loadAvailableDevices()
                
                // Restart with new config
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.startController()
                    self?.updateMenu()
                }
            } catch {
                print("❌ Config reload error: \(error)")
                statusMessage = "Config error"
                updateMenu()
            }
        } else {
            print("⚠️ No config file found at: \(configManager.getConfigPath())")
            statusMessage = "Not configured"
            updateMenu()
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
            print("Config saved to: \(configManager.getConfigPath())")
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
            print("Failed to save config: \(error)")
            statusMessage = "Failed to save config"
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
                print("Failed to load audio devices: \(error)")
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
                window.styleMask = [.titled, .closable]
                window.setContentSize(NSSize(width: 600, height: 400))
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
        alert.addButton(withTitle: "View on GitHub")
        alert.alertStyle = .informational
        
        let response = alert.runModal()
        
        // If user clicked "View on GitHub" (second button)
        if response == .alertSecondButtonReturn {
            if let url = URL(string: "https://github.com/k0nker/ss_chatmix_macOS") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    @objc func checkForUpdates() {
        SparkleUpdaterViewModel.shared.checkForUpdates()
    }
    
    @objc func quit() {
        stopController()
        NSApplication.shared.terminate(nil)
    }
}
