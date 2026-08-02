import Foundation

public class ResetCommand {
    private let configManager = ConfigManager()
    private let audioController = AudioController()
    private let launchManager = LaunchAgentManager()
    private let processManager = ProcessManager()
    
    public init() {}
    
    public func execute() throws {
        print("🔄 Resetting ChatMix configuration...\n")
        
        // Stop running process first
        if processManager.isAlreadyRunning() {
            print("Stopping running controller...")
            try processManager.killRunningProcess()
            print("  ✅ Controller stopped\n")
        }
        
        // Load config to get aggregate devices to remove
        if configManager.exists() {
            do {
                let config = try configManager.load()
                
                // Reset volumes to 100% before cleanup
                print("Resetting device volumes to 100%...")
                
                // Reset game device volume
                if let gameDeviceID = try audioController.findDevice(byUID: config.audioDevices.game.uid) {
                    do {
                        try audioController.setVolume(100.0, for: gameDeviceID)
                        print("  ✅ Game device: \(config.audioDevices.game.name) → 100%")
                    } catch {
                        print("  ⚠️  Could not set game device volume")
                    }
                } else {
                    print("  ⚠️  Game device not found: \(config.audioDevices.game.name)")
                }
                
                // Reset chat device volume
                if let chatDeviceID = try audioController.findDevice(byUID: config.audioDevices.chat.uid) {
                    do {
                        try audioController.setVolume(100.0, for: chatDeviceID)
                        print("  ✅ Chat device: \(config.audioDevices.chat.name) → 100%")
                    } catch {
                        print("  ⚠️  Could not set chat device volume")
                    }
                } else {
                    print("  ⚠️  Chat device not found: \(config.audioDevices.chat.name)")
                }
                
                // Reset physical output device volume (if in monitoring mode)
                if let outputUID = config.outputDeviceUid {
                    if let outputDeviceID = try audioController.findDevice(byUID: outputUID) {
                        do {
                            try audioController.setVolume(100.0, for: outputDeviceID)
                            print("  ✅ Output device → 100%")
                        } catch {
                            print("  ⚠️  Could not set output device volume")
                        }
                    } else {
                        print("  ⚠️  Output device not found")
                    }
                }
                print()
                
                // Collect all aggregate UIDs to remove (including main aggregate)
                var aggregatesToRemove: [AggregateDeviceInfo] = config.createdAggregateDevices
                if let mainAggregate = config.mainAggregateDevice,
                   !aggregatesToRemove.contains(where: { $0.uid == mainAggregate.uid }) {
                    aggregatesToRemove.append(mainAggregate)
                }
                
                // Remove any aggregate devices we created
                if !aggregatesToRemove.isEmpty {
                    print("Removing aggregate devices...")
                    for aggregate in aggregatesToRemove {
                        if let deviceID = try audioController.findDevice(byUID: aggregate.uid) {
                            do {
                                try audioController.removeAggregateDevice(deviceID: deviceID)
                                print("  ✅ Removed: \(aggregate.name)")
                            } catch {
                                print("  ⚠️  Failed to remove: \(aggregate.name) - \(error.localizedDescription)")
                            }
                        } else {
                            print("  ⚠️  Not found (may be already deleted): \(aggregate.name)")
                        }
                    }
                    print()
                }
                
                // Remove launch agent if it was installed
                if config.launchAgentEnabled && launchManager.isInstalled() {
                    print("Removing launch agent...")
                    try launchManager.uninstall()
                    print("✅ Launch agent removed\n")
                }
            } catch {
                print("⚠️  Could not load config, skipping aggregate device cleanup\n")
            }
        }
        
        // Delete config file
        if configManager.exists() {
            try configManager.delete()
            print("✅ Configuration deleted")
        } else {
            print("⚠️  No configuration found")
        }
        
        print("\n✅ Reset complete!")
        print("Run 'sschatmix --setup' to configure again.")
    }
}
