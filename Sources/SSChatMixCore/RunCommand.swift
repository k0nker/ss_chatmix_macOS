import Foundation

public class RunCommand {
    private let configManager = ConfigManager()
    private let audioController = AudioController()
    private let hidController = HIDController()
    private let processManager = ProcessManager()
    private var audioMonitor: AudioMonitor?
    
    public init() {}
    
    public func execute() throws {
        // Check if already running
        if processManager.isAlreadyRunning() {
            print("⚠️  ChatMix controller is already running!")
            print("   Run 'sschatmix --reset' to stop it.")
            return
        }
        
        // Check for configuration
        guard configManager.exists() else {
            throw SSChatMixError.noConfiguration
        }
        
        let config = try configManager.load()
        
        // Find audio devices
        guard let gameDeviceID = try audioController.findDevice(byUID: config.audioDevices.game.uid) else {
            throw SSChatMixError.deviceNotFound
        }
        
        guard let chatDeviceID = try audioController.findDevice(byUID: config.audioDevices.chat.uid) else {
            throw SSChatMixError.deviceNotFound
        }
        
        // Write PID file
        try processManager.writePID()
        
        // Configure HID controller with device from config
        let vendorID = Int(config.hidDevice.vendorId.dropFirst(2), radix: 16) ?? 0x1038
        let productID = Int(config.hidDevice.productId.dropFirst(2), radix: 16) ?? 0x2202
        hidController.configure(vendorID: vendorID, productID: productID)
        
        // Set up cleanup on exit
        signal(SIGINT) { _ in
            let pm = ProcessManager()
            pm.removePID()
            exit(0)
        }
        signal(SIGTERM) { _ in
            let pm = ProcessManager()
            pm.removePID()
            exit(0)
        }
        
        print("🎧 ChatMix Controller Started")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("HID Device: VID:\(config.hidDevice.vendorId) PID:\(config.hidDevice.productId)")
        print("Game device: \(config.audioDevices.game.name)")
        print("Chat device: \(config.audioDevices.chat.name)")
        
        if config.monitoringMode {
            // Monitoring mode: Mix two virtual devices to physical output
            guard let outputUID = config.outputDeviceUid else {
                print("❌ No output device UID in config!")
                throw SSChatMixError.deviceNotFound
            }
            
            print("🔍 Looking for output device: \(outputUID)")
            
            guard let outputDeviceID = try audioController.findDevice(byUID: outputUID) else {
                print("❌ Failed to find output device with UID: \(outputUID)")
                let devices = try audioController.listOutputDevices()
                print("Available devices:")
                for device in devices {
                    print("  - \(device.name) [\(device.uid)]")
                }
                throw SSChatMixError.deviceNotFound
            }
            
            print("✅ Found output device ID: \(outputDeviceID)")
            
            print("Output device: \(outputUID)")
            print("Mode: Real-time monitoring & mixing")
            print("\nListening for dial changes... (Press Ctrl+C to stop)\n")
            
            // Create and start audio monitor
            let monitor = AudioMonitor(
                gameDeviceID: gameDeviceID,
                chatDeviceID: chatDeviceID,
                outputDeviceID: outputDeviceID
            )
            try monitor.start()
            self.audioMonitor = monitor
            
            // Set up HID callback for volume updates
            hidController.onDialChanged = { gameVolume, chatVolume in
                // Update monitor volumes (0-100 range to 0.0-1.0)
                monitor.updateVolumes(
                    game: Float(gameVolume) / 100.0,
                    chat: Float(chatVolume) / 100.0
                )
                print("🎮 Game: \(gameVolume)% | 💬 Chat: \(chatVolume)%")
            }
            
        } else {
            // Direct volume control mode
            if let mainAggregate = config.mainAggregateDevice {
                print("Aggregate: \(mainAggregate.name)")
            }
            print("Mode: Direct volume control")
            print("\nListening for dial changes... (Press Ctrl+C to stop)\n")
            
            // Set up HID callback for direct volume control
            hidController.onDialChanged = { gameVolume, chatVolume in
                do {
                    // Set game device volume
                    try self.audioController.setVolume(Float(gameVolume), for: gameDeviceID)
                    
                    // Set chat device volume
                    try self.audioController.setVolume(Float(chatVolume), for: chatDeviceID)
                    
                    print("🎮 Game: \(gameVolume)% | 💬 Chat: \(chatVolume)%")
                } catch {
                    print("❌ Error setting volume: \(error.localizedDescription)")
                }
            }
        }
        
        // Start listening to HID
        try hidController.start()
        
        // Set up signal handler for clean shutdown
        signal(SIGINT) { _ in
            print("\n\n⏹️  Stopping ChatMix controller...")
            exit(0)
        }
        
        // Run loop
        RunLoop.current.run()
    }
}
