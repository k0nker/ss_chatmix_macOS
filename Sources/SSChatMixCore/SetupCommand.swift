import Foundation

public class SetupCommand {
    private let audioController = AudioController()
    private let hidController = HIDController()
    private let configManager = ConfigManager()
    private let processManager = ProcessManager()
    
    public init() {}
    
    public func execute() throws {
        print("🎧 ChatMix Setup Wizard")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
        
        // Detect and let user select ChatMix device
        print("📱 Scanning for SteelSeries ChatMix devices...")
        let chatMixDevices = hidController.listChatMixDevices()
        
        guard !chatMixDevices.isEmpty else {
            print("❌ No ChatMix devices found!")
            print("   Make sure your headset is connected and turned on.")
            throw SSChatMixError.hidDeviceNotFound
        }
        
        print("✅ Found \(chatMixDevices.count) ChatMix device(s)\n")
        
        let selectedHIDDevice: ChatMixDevice
        if chatMixDevices.count == 1 {
            selectedHIDDevice = chatMixDevices[0]
            print("Selected: \(selectedHIDDevice.productName)")
            print("   VID: 0x\(String(selectedHIDDevice.vendorID, radix: 16, uppercase: true))")
            print("   PID: 0x\(String(selectedHIDDevice.productID, radix: 16, uppercase: true))\n")
        } else {
            print("Multiple ChatMix devices detected. Select your device:")
            for (index, device) in chatMixDevices.enumerated() {
                print("   \(index + 1). \(device.productName) (PID: 0x\(String(device.productID, radix: 16, uppercase: true)))")
            }
            print("\nSelect device (1-\(chatMixDevices.count)): ", terminator: "")
            fflush(stdout)
            
            guard let input = readLine(),
                  let choice = Int(input),
                  choice > 0,
                  choice <= chatMixDevices.count else {
                throw SSChatMixError.invalidSelection
            }
            
            selectedHIDDevice = chatMixDevices[choice - 1]
            print("✅ Selected: \(selectedHIDDevice.productName)\n")
        }
        
        print("💡 This tool mixes two virtual audio devices to a physical output.")
        print("   Recommended: Install BlackHole virtual audio drivers")
        print("   https://github.com/ExistentialAudio/BlackHole\n")
        
        // Select GAME device (virtual)
        print("🎮 Select GAME Audio Device")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("(Select a virtual device like BlackHole 16ch)")
        print()
        let gameDevice = try selectDevice(label: "game")
        print()
        
        // Select CHAT device (virtual)
        print("💬 Select CHAT Audio Device")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("(Select a different virtual device like BlackHole 2ch)")
        print()
        let chatDevice = try selectDevice(label: "chat")
        print()
        
        // Select physical output device
        print("🔊 Select Physical OUTPUT Device")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("(Where you want to hear the audio - headphones, speakers, etc.)\n")
        let outputDevice = try selectDevice(label: "output")
        let outputDeviceUid = outputDevice.uid
        print()
        
        // Set physical output device to 100% volume
        print("🔊 Setting output device volume to 100%...")
        if let outputDeviceID = try audioController.findDevice(byUID: outputDeviceUid) {
            try audioController.setVolume(100.0, for: outputDeviceID)
            print("   ✅ Output device volume set to 100%\n")
        } else {
            print("   ⚠️  Could not find output device to set volume\n")
        }
        
        print("✅ Configuration complete!")
        print("   Game (virtual): \(gameDevice.name)")
        print("   Chat (virtual): \(chatDevice.name)")
        print("   Output (physical): \(outputDevice.name)")
        print("\n💡 Set apps to output to the virtual devices.")
        print("   The dial will mix them to your \(outputDevice.name).\n")
        
        // Ask about launch agent
        print("Start at login? (y/n): ", terminator: "")
        fflush(stdout)
        let launchAtLogin = readLine()?.lowercased().starts(with: "y") ?? false
        
        let config = Config(
            audioDevices: AudioDevicesConfig(
                game: gameDevice,
                chat: chatDevice
            ),
            hidDevice: HIDDeviceConfig(
                vendorId: String(format: "0x%X", selectedHIDDevice.vendorID),
                productId: String(format: "0x%X", selectedHIDDevice.productID)
            ),
            launchAgentEnabled: launchAtLogin,
            createdAggregateDevices: [],
            mainAggregateDevice: nil,
            monitoringMode: true,
            outputDeviceUid: outputDeviceUid
        )
        
        if launchAtLogin {
            let launchManager = LaunchAgentManager()
            try launchManager.install()
            print("✅ Launch agent installed\n")
        }
        
        // Save config
        try configManager.save(config)
        
        print("✅ Setup complete!\n")
        
        print("\n🚀 Starting controller in background...")
        
        // Start controller in background using nohup
        let binaryPath = ProcessInfo.processInfo.arguments[0]
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        task.arguments = [binaryPath]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        
        try task.run()
        
        // Give it a moment to start
        usleep(500_000) // 500ms
        
        if processManager.isAlreadyRunning() {
            print("✅ Controller started! Turn your dial to test it.")
        } else {
            print("⚠️  Controller may not have started. Run 'sschatmix' manually.")
        }
        
        print("\n💡 The controller will start automatically at login.")
    }
    
    private func selectDevice(label: String) throws -> AudioDeviceConfig {
        // List available audio devices
        print("Available audio output devices:")
        let devices = try audioController.listOutputDevices()
        
        for (index, device) in devices.enumerated() {
            let marker = device.isAggregate ? " [aggregate]" : ""
            print("   \(index + 1). \(device.name)\(marker)")
        }
        
        // Ask user to select
        print("\nSelect \(label) device (1-\(devices.count)): ", terminator: "")
        fflush(stdout)
        guard let input = readLine(),
              let choice = Int(input),
              choice > 0,
              choice <= devices.count else {
            throw SSChatMixError.invalidSelection
        }
        
        let selectedDevice = devices[choice - 1]
        print("✅ Selected: \(selectedDevice.name)")
        
        return AudioDeviceConfig(
            id: String(selectedDevice.id),
            name: selectedDevice.name,
            uid: selectedDevice.uid,
            isAggregate: false
        )
    }
}
