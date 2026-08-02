import Foundation

public class LoginCommand {
    private let configManager = ConfigManager()
    private let launchManager = LaunchAgentManager()
    
    public init() {}
    
    public func execute(disable: Bool) throws {
        guard configManager.exists() else {
            throw SSChatMixError.noConfiguration
        }
        
        let config = try configManager.load()
        
        if disable {
            // Disable launch agent
            if launchManager.isInstalled() {
                try launchManager.uninstall()
                print("✅ Launch agent disabled")
            } else {
                print("⚠️  Launch agent is not installed")
            }
            
            // Update config
            let updatedConfig = Config(
                audioDevices: config.audioDevices,
                hidDevice: config.hidDevice,
                launchAgentEnabled: false,
                createdAggregateDevices: config.createdAggregateDevices
            )
            try configManager.save(updatedConfig)
        } else {
            // Enable launch agent
            if launchManager.isInstalled() {
                print("⚠️  Launch agent is already installed")
            } else {
                try launchManager.install()
                print("✅ Launch agent installed - sschatmix will start at login")
            }
            
            // Update config
            let updatedConfig = Config(
                audioDevices: config.audioDevices,
                hidDevice: config.hidDevice,
                launchAgentEnabled: true,
                createdAggregateDevices: config.createdAggregateDevices
            )
            try configManager.save(updatedConfig)
        }
    }
}
