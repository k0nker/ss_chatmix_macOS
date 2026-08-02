import Foundation

public class ReloadCommand {
    private let configManager = ConfigManager()
    private let processManager = ProcessManager()
    
    public init() {}
    
    public func execute() throws {
        print("🔄 Reloading ChatMix controller...")
        print()
        
        // Check for configuration
        guard configManager.exists() else {
            throw SSChatMixError.noConfiguration
        }
        
        // Stop running process if any
        if processManager.isAlreadyRunning() {
            print("⏹️  Stopping current process...")
            try processManager.killRunningProcess()
            print("   ✅ Process stopped")
            print()
        } else {
            print("ℹ️  No running process found")
            print()
        }
        
        // Start controller in background
        print("🚀 Starting controller in background...")
        
        let binaryPath = "/usr/local/bin/sschatmix"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        task.arguments = [binaryPath]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        
        try task.run()
        
        // Give it a moment to start
        usleep(500_000) // 500ms
        
        if processManager.isAlreadyRunning() {
            print("   ✅ Controller restarted successfully!")
            print()
            print("💡 Turn your dial to test it.")
        } else {
            print("   ⚠️  Controller may not have started.")
            print("   Try running 'sschatmix' manually to see error messages.")
        }
    }
}
