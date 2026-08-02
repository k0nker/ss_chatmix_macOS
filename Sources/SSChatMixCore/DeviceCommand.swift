import Foundation

public class DeviceCommand {
    private let configManager = ConfigManager()
    private let audioController = AudioController()
    
    public init() {}
    
    public func execute() throws {
        guard configManager.exists() else {
            throw SSChatMixError.noConfiguration
        }
        
        var config = try configManager.load()
        var createdAggregates = config.createdAggregateDevices
        
        print("🔊 Change Audio Devices\n")
        print("Current configuration:")
        print("  Game: \(config.audioDevices.game.name)")
        print("  Chat: \(config.audioDevices.chat.name)\n")
        
        print("What would you like to change?")
        print("  1. Game device")
        print("  2. Chat device")
        print("  3. Both")
        print("  4. Cancel")
        print("\nChoice (1-4): ", terminator: "")
        fflush(stdout)
        
        guard let input = readLine(),
              let choice = Int(input),
              choice >= 1,
              choice <= 4 else {
            throw SSChatMixError.invalidSelection
        }
        
        var newGameDevice = config.audioDevices.game
        var newChatDevice = config.audioDevices.chat
        
        if choice == 1 || choice == 3 {
            print("\n🎮 Select new GAME device:")
            newGameDevice = try selectDeviceWithAggregateOption(
                label: "game",
                createdAggregates: &createdAggregates
            )
        }
        
        if choice == 2 || choice == 3 {
            print("\n💬 Select new CHAT device:")
            newChatDevice = try selectDeviceWithAggregateOption(
                label: "chat",
                createdAggregates: &createdAggregates
            )
        }
        
        if choice == 4 {
            print("Cancelled.")
            return
        }
        
        // Update config
        let updatedConfig = Config(
            audioDevices: AudioDevicesConfig(
                game: newGameDevice,
                chat: newChatDevice
            ),
            hidDevice: config.hidDevice,
            launchAgentEnabled: config.launchAgentEnabled,
            createdAggregateDevices: createdAggregates
        )
        
        try configManager.save(updatedConfig)
        
        print("\n✅ Devices updated!")
        print("  Game: \(newGameDevice.name)")
        print("  Chat: \(newChatDevice.name)")
    }
    
    private func selectDeviceWithAggregateOption(
        label: String,
        createdAggregates: inout [AggregateDeviceInfo]
    ) throws -> AudioDeviceConfig {
        let devices = try audioController.listOutputDevices()
        
        for (index, device) in devices.enumerated() {
            let marker = device.isAggregate ? " [aggregate]" : ""
            print("   \(index + 1). \(device.name)\(marker)")
        }
        
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
        
        print("\nCreate aggregate device with custom name? (y/n): ", terminator: "")
        fflush(stdout)
        let createAggregate = readLine()?.lowercased().starts(with: "y") ?? false
        
        if createAggregate {
            print("Enter custom name: ", terminator: "")
            fflush(stdout)
            guard let customName = readLine()?.trimmingCharacters(in: .whitespaces),
                  !customName.isEmpty else {
                print("⚠️  Invalid name, using original device")
                return AudioDeviceConfig(
                    id: String(selectedDevice.id),
                    name: selectedDevice.name,
                    uid: selectedDevice.uid,
                    isAggregate: false
                )
            }
            
            let result = try audioController.createAggregateDevice(
                name: customName,
                sourceDeviceUID: selectedDevice.uid
            )
            
            print("✅ Created: \"\(customName)\"")
            
            createdAggregates.append(AggregateDeviceInfo(
                uid: result.uid,
                name: customName,
                sourceDeviceUID: selectedDevice.uid
            ))
            
            return AudioDeviceConfig(
                id: String(result.deviceID),
                name: customName,
                uid: result.uid,
                isAggregate: true,
                sourceDeviceUID: selectedDevice.uid
            )
        }
        
        return AudioDeviceConfig(
            id: String(selectedDevice.id),
            name: selectedDevice.name,
            uid: selectedDevice.uid,
            isAggregate: false
        )
    }
}
