import Foundation

public class LaunchAgentManager {
    private let launchAgentDirectory: URL
    private let launchAgentFile: URL
    private let launchAgentLabel = "com.k0nker.sschatmix"
    
    public init() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        self.launchAgentDirectory = homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
        self.launchAgentFile = launchAgentDirectory
            .appendingPathComponent("\(launchAgentLabel).plist")
    }
    
    public func install() throws {
        // Create LaunchAgents directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: launchAgentDirectory.path) {
            try FileManager.default.createDirectory(
                at: launchAgentDirectory,
                withIntermediateDirectories: true
            )
        }
        
        // Get the path to the binary
        guard let binaryPath = getBinaryPath() else {
            throw SSChatMixError.launchAgentFailed("Could not determine binary path")
        }
        
        // Create plist content
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(launchAgentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(binaryPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>StandardOutPath</key>
            <string>/tmp/sschatmix.log</string>
            <key>StandardErrorPath</key>
            <string>/tmp/sschatmix.error.log</string>
        </dict>
        </plist>
        """
        
        // Write plist file
        try plist.write(to: launchAgentFile, atomically: true, encoding: .utf8)
        
        // Load the agent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", launchAgentFile.path]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw SSChatMixError.launchAgentFailed("Failed to load launch agent")
        }
    }
    
    public func uninstall() throws {
        guard FileManager.default.fileExists(atPath: launchAgentFile.path) else {
            // Already uninstalled
            return
        }
        
        // Unload the agent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", launchAgentFile.path]
        
        try process.run()
        process.waitUntilExit()
        
        // Remove plist file
        try FileManager.default.removeItem(at: launchAgentFile)
    }
    
    public func isInstalled() -> Bool {
        return FileManager.default.fileExists(atPath: launchAgentFile.path)
    }
    
    private func getBinaryPath() -> String? {
        // Get the path to the currently running executable
        let executablePath = CommandLine.arguments[0]
        
        // If it's a relative path, make it absolute
        if executablePath.hasPrefix("/") {
            return executablePath
        } else {
            let currentDirectory = FileManager.default.currentDirectoryPath
            return "\(currentDirectory)/\(executablePath)"
        }
    }
}
