import Foundation

public class StatusCommand {
    private let configManager = ConfigManager()
    private let hidController = HIDController()
    private let launchManager = LaunchAgentManager()
    
    public init() {}
    
    public func execute() throws {
        print("📊 ChatMix Status\n")
        
        // Check if configured
        guard configManager.exists() else {
            print("⚠️  Not configured")
            print("Run 'sschatmix --setup' to get started.")
            return
        }
        
        let config = try configManager.load()
        
        // ChatMix device status
        print("📱 ChatMix Device:")
        print("   VID: \(config.hidDevice.vendorId) PID: \(config.hidDevice.productId)")
        if hidController.detectDevice() {
            print("   ✅ Connected")
        } else {
            print("   ❌ Not detected")
        }
        print()
        
        // Audio devices
        print("🔊 Audio Devices:")
        print("   Game: \(config.audioDevices.game.name)")
        if config.audioDevices.game.isAggregate {
            print("         [Aggregate device]")
        }
        print("   Chat: \(config.audioDevices.chat.name)")
        if config.audioDevices.chat.isAggregate {
            print("         [Aggregate device]")
        }
        print()
        
        // Aggregate devices
        if !config.createdAggregateDevices.isEmpty {
            print("🎛️  Created Aggregate Devices:")
            for aggregate in config.createdAggregateDevices {
                print("   • \(aggregate.name)")
            }
            print()
        }
        
        // Launch agent
        print("🚀 Launch Agent:")
        if launchManager.isInstalled() {
            print("   ✅ Enabled (starts at login)")
        } else {
            print("   ❌ Disabled")
        }
        print()
        
        // Config file location
        print("⚙️  Configuration:")
        print("   \(configManager.getConfigPath())")
    }
}
