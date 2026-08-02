import Foundation

public class ConfigManager {
    private let configDirectory: URL
    private let configFile: URL
    
    public init() {
        // Config location: ~/Library/Application Support/com.k0nker.sschatmix/config.json
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        
        self.configDirectory = appSupport.appendingPathComponent("com.k0nker.sschatmix")
        self.configFile = configDirectory.appendingPathComponent("config.json")
    }
    
    public func load() throws -> Config {
        guard FileManager.default.fileExists(atPath: configFile.path) else {
            throw SSChatMixError.noConfiguration
        }
        
        let data = try Data(contentsOf: configFile)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        return try decoder.decode(Config.self, from: data)
    }
    
    public func save(_ config: Config) throws {
        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: configDirectory.path) {
            try FileManager.default.createDirectory(
                at: configDirectory,
                withIntermediateDirectories: true
            )
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        
        let data = try encoder.encode(config)
        try data.write(to: configFile)
    }
    
    public func exists() -> Bool {
        return FileManager.default.fileExists(atPath: configFile.path)
    }
    
    public func delete() throws {
        if FileManager.default.fileExists(atPath: configFile.path) {
            try FileManager.default.removeItem(at: configFile)
        }
    }
    
    public func getConfigPath() -> String {
        return configFile.path
    }
}
