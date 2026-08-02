import Foundation

public class AggregateCommand {
    private let configManager = ConfigManager()
    private let audioController = AudioController()
    
    public init() {}
    
    public func create(name: String, source: String) throws {
        guard configManager.exists() else {
            throw SSChatMixError.noConfiguration
        }
        
        let config = try configManager.load()
        
        // Find source device
        let devices = try audioController.listOutputDevices()
        guard let sourceDevice = devices.first(where: { $0.name == source }) else {
            print("❌ Source device '\(source)' not found")
            print("\nAvailable devices:")
            for device in devices {
                print("  - \(device.name)")
            }
            return
        }
        
        // Create aggregate
        let result = try audioController.createAggregateDevice(
            name: name,
            sourceDeviceUID: sourceDevice.uid
        )
        
        // Track it in config
        var aggregates = config.createdAggregateDevices
        aggregates.append(AggregateDeviceInfo(
            uid: result.uid,
            name: name,
            sourceDeviceUID: sourceDevice.uid
        ))
        
        let updatedConfig = Config(
            audioDevices: config.audioDevices,
            hidDevice: config.hidDevice,
            launchAgentEnabled: config.launchAgentEnabled,
            createdAggregateDevices: aggregates
        )
        
        try configManager.save(updatedConfig)
        
        print("✅ Created aggregate device: '\(name)'")
    }
    
    public func remove(name: String) throws {
        guard configManager.exists() else {
            throw SSChatMixError.noConfiguration
        }
        
        let config = try configManager.load()
        
        // Find the aggregate in our tracking list
        guard let aggregate = config.createdAggregateDevices.first(where: { $0.name == name }) else {
            print("❌ Aggregate device '\(name)' not found in tracked devices")
            return
        }
        
        // Find and remove the device
        if let deviceID = try audioController.findDevice(byUID: aggregate.uid) {
            try audioController.removeAggregateDevice(deviceID: deviceID)
        }
        
        // Remove from tracking
        var aggregates = config.createdAggregateDevices
        aggregates.removeAll { $0.name == name }
        
        let updatedConfig = Config(
            audioDevices: config.audioDevices,
            hidDevice: config.hidDevice,
            launchAgentEnabled: config.launchAgentEnabled,
            createdAggregateDevices: aggregates
        )
        
        try configManager.save(updatedConfig)
        
        print("✅ Removed aggregate device: '\(name)'")
    }
    
    public func rename(oldName: String, newName: String) throws {
        guard configManager.exists() else {
            throw SSChatMixError.noConfiguration
        }
        
        let config = try configManager.load()
        
        // Find the aggregate
        guard let aggregate = config.createdAggregateDevices.first(where: { $0.name == oldName }) else {
            print("❌ Aggregate device '\(oldName)' not found")
            return
        }
        
        // Find device ID and recreate with new name
        if let oldDeviceID = try audioController.findDevice(byUID: aggregate.uid),
           let sourceUID = aggregate.sourceDeviceUID {
            let result = try audioController.renameAggregateDevice(
                oldDeviceID: oldDeviceID,
                newName: newName,
                sourceDeviceUID: sourceUID
            )
            
            // Update tracking
            var aggregates = config.createdAggregateDevices
            aggregates.removeAll { $0.name == oldName }
            aggregates.append(AggregateDeviceInfo(
                uid: result.uid,
                name: newName,
                sourceDeviceUID: sourceUID
            ))
            
            let updatedConfig = Config(
                version: config.version,
                audioDevices: config.audioDevices,
                hidDevice: config.hidDevice,
                launchAgentEnabled: config.launchAgentEnabled,
                createdAggregateDevices: aggregates,
                mainAggregateDevice: config.mainAggregateDevice
            )
            
            try configManager.save(updatedConfig)
            
            print("✅ Renamed: '\(oldName)' → '\(newName)'")
        } else {
            print("⚠️  Cannot rename multi-output aggregates. Use --setup to recreate.")
        }
    }
    
    public func list() throws {
        guard configManager.exists() else {
            throw SSChatMixError.noConfiguration
        }
        
        let config = try configManager.load()
        
        if config.createdAggregateDevices.isEmpty {
            print("No aggregate devices created by sschatmix")
            return
        }
        
        print("Aggregate devices created by sschatmix:\n")
        for aggregate in config.createdAggregateDevices {
            print("  • \(aggregate.name)")
            print("    UID: \(aggregate.uid)")
            if let sourceUID = aggregate.sourceDeviceUID {
                print("    Source: \(sourceUID)")
            } else {
                print("    Type: Multi-output aggregate")
            }
            print()
        }
    }
}
