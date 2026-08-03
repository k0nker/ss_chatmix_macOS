import Foundation

// MARK: - Configuration Models

public struct Config: Codable {
    public let version: String
    public let audioDevices: AudioDevicesConfig
    public let hidDevice: HIDDeviceConfig
    public let launchAgentEnabled: Bool
    public let createdAggregateDevices: [AggregateDeviceInfo]
    public let mainAggregateDevice: AggregateDeviceInfo?  // The multi-output device combining game+chat
    public let monitoringMode: Bool  // If true, use AudioMonitor to mix virtual devices to physical output
    public let outputDeviceUid: String?  // Physical output device UID when in monitoring mode
    public let lastGameVolume: Int?  // Last known game volume from dial (0-100)
    public let lastChatVolume: Int?  // Last known chat volume from dial (0-100)
    
    public init(
        version: String = "1.0",
        audioDevices: AudioDevicesConfig,
        hidDevice: HIDDeviceConfig,
        launchAgentEnabled: Bool,
        createdAggregateDevices: [AggregateDeviceInfo] = [],
        mainAggregateDevice: AggregateDeviceInfo? = nil,
        monitoringMode: Bool = false,
        outputDeviceUid: String? = nil,
        lastGameVolume: Int? = nil,
        lastChatVolume: Int? = nil
    ) {
        self.version = version
        self.audioDevices = audioDevices
        self.hidDevice = hidDevice
        self.launchAgentEnabled = launchAgentEnabled
        self.createdAggregateDevices = createdAggregateDevices
        self.mainAggregateDevice = mainAggregateDevice
        self.monitoringMode = monitoringMode
        self.outputDeviceUid = outputDeviceUid
        self.lastGameVolume = lastGameVolume
        self.lastChatVolume = lastChatVolume
    }
}

public struct AudioDevicesConfig: Codable {
    public let game: AudioDeviceConfig
    public let chat: AudioDeviceConfig
    
    public init(game: AudioDeviceConfig, chat: AudioDeviceConfig) {
        self.game = game
        self.chat = chat
    }
}

public struct AudioDeviceConfig: Codable {
    public let id: String
    public let name: String
    public let uid: String
    public let isAggregate: Bool
    public let sourceDeviceUID: String?
    
    public init(
        id: String,
        name: String,
        uid: String,
        isAggregate: Bool,
        sourceDeviceUID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.uid = uid
        self.isAggregate = isAggregate
        self.sourceDeviceUID = sourceDeviceUID
    }
}

public struct HIDDeviceConfig: Codable {
    public let vendorId: String
    public let productId: String
    
    public init(vendorId: String, productId: String) {
        self.vendorId = vendorId
        self.productId = productId
    }
}

public struct AggregateDeviceInfo: Codable {
    public let uid: String
    public let name: String
    public let sourceDeviceUID: String?  // Optional for backward compatibility
    
    public init(uid: String, name: String, sourceDeviceUID: String? = nil) {
        self.uid = uid
        self.name = name
        self.sourceDeviceUID = sourceDeviceUID
    }
}

// MARK: - Error Types

public enum SSChatMixError: Error, LocalizedError {
    case noConfiguration
    case configurationInvalid
    case deviceNotFound
    case hidDeviceNotFound
    case audioControllerFailed(String)
    case hidControllerFailed(String)
    case launchAgentFailed(String)
    case invalidSelection
    case aggregateCreationFailed
    case aggregateRemovalFailed
    
    public var errorDescription: String? {
        switch self {
        case .noConfiguration:
            return "No configuration found. Run 'sschatmix --setup' to get started."
        case .configurationInvalid:
            return "Configuration file is invalid or corrupted."
        case .deviceNotFound:
            return "Configured audio device not found."
        case .hidDeviceNotFound:
            return "No ChatMix device found. Make sure your headset is connected and turned on."
        case .audioControllerFailed(let message):
            return "Audio controller error: \(message)"
        case .hidControllerFailed(let message):
            return "HID controller error: \(message)"
        case .launchAgentFailed(let message):
            return "Launch agent error: \(message)"
        case .invalidSelection:
            return "Invalid selection."
        case .aggregateCreationFailed:
            return "Failed to create aggregate device."
        case .aggregateRemovalFailed:
            return "Failed to remove aggregate device."
        }
    }
}
