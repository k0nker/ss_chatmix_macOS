import Foundation
import CoreAudio

public struct AudioDeviceInfo: Hashable {
    public let id: AudioDeviceID
    public let name: String
    public let uid: String
    public let isAggregate: Bool
    
    public init(id: AudioDeviceID, name: String, uid: String, isAggregate: Bool) {
        self.id = id
        self.name = name
        self.uid = uid
        self.isAggregate = isAggregate
    }
}

public class AudioController {
    
    public init() {}
    
    // MARK: - Device Listing
    
    public func listOutputDevices() throws -> [AudioDeviceInfo] {
        var devices: [AudioDeviceInfo] = []
        
        // Get device list from CoreAudio
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        
        guard status == noErr else {
            throw SSChatMixError.audioControllerFailed("Failed to get device list size")
        }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var audioDevices = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &audioDevices
        )
        
        guard status == noErr else {
            throw SSChatMixError.audioControllerFailed("Failed to get device list")
        }
        
        // Filter for output devices and get their info
        for deviceID in audioDevices {
            if isOutputDevice(deviceID) {
                let name = try getDeviceName(deviceID)
                let uid = try getDeviceUID(deviceID)
                let isAggregate = checkIfAggregate(uid)
                devices.append(AudioDeviceInfo(
                    id: deviceID,
                    name: name,
                    uid: uid,
                    isAggregate: isAggregate
                ))
            }
        }
        
        return devices
    }
    
    public func findDevice(byUID uid: String) throws -> AudioDeviceID? {
        let devices = try listOutputDevices()
        return devices.first(where: { $0.uid == uid })?.id
    }
    
    // MARK: - Volume Control
    
    public func setVolume(_ volume: Float, for deviceID: AudioDeviceID) throws {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var volumeValue = volume / 100.0 // Convert 0-100 to 0.0-1.0
        let dataSize = UInt32(MemoryLayout<Float>.size)
        
        let status = AudioObjectSetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            dataSize,
            &volumeValue
        )
        
        guard status == noErr else {
            throw SSChatMixError.audioControllerFailed("Failed to set volume")
        }
    }
    
    public func getVolume(for deviceID: AudioDeviceID) throws -> Float {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var volume: Float = 0
        var dataSize = UInt32(MemoryLayout<Float>.size)
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize,
            &volume
        )
        
        guard status == noErr else {
            throw SSChatMixError.audioControllerFailed("Failed to get volume")
        }
        
        return volume * 100.0 // Convert 0.0-1.0 to 0-100
    }
    
    // MARK: - Aggregate Device Management
    
    public func createAggregateDevice(name: String, sourceDeviceUID: String) throws -> (deviceID: AudioDeviceID, uid: String) {
        var deviceID: AudioDeviceID = 0
        
        // Create unique UID for this aggregate device
        let aggregateUID = "com.k0nker.sschatmix.aggregate.\(UUID().uuidString)"
        
        // Configure aggregate device
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: name,
            kAudioAggregateDeviceUIDKey as String: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey as String: 0,
            kAudioAggregateDeviceSubDeviceListKey as String: [sourceDeviceUID]
        ]
        
        // Create it
        let status = AudioHardwareCreateAggregateDevice(
            description as CFDictionary,
            &deviceID
        )
        
        guard status == noErr else {
            throw SSChatMixError.aggregateCreationFailed
        }
        
        return (deviceID, aggregateUID)
    }
    
    public func createMultiOutputAggregate(
        name: String,
        gameDeviceUID: String,
        chatDeviceUID: String
    ) throws -> (deviceID: AudioDeviceID, uid: String) {
        var deviceID: AudioDeviceID = 0
        
        // Create unique UID for this aggregate device
        let aggregateUID = "com.k0nker.sschatmix.aggregate.\(UUID().uuidString)"
        
        print("[AudioController] Creating MULTI-OUTPUT device with:")
        print("  Name: \(name)")
        print("  UID: \(aggregateUID)")
        print("  Game UID: \(gameDeviceUID)")
        print("  Chat UID: \(chatDeviceUID)")
        
        // Configure MULTI-OUTPUT device (not aggregate)
        // CRITICAL: kAudioAggregateDeviceIsStackedKey = 1 creates a Multi-Output Device
        let subDevices = [gameDeviceUID as CFString, chatDeviceUID as CFString] as CFArray
        
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: name,
            kAudioAggregateDeviceUIDKey as String: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey as String: 0,
            kAudioAggregateDeviceIsStackedKey as String: 1,  // THIS makes it a Multi-Output Device!
            kAudioAggregateDeviceSubDeviceListKey as String: subDevices,
            kAudioAggregateDeviceMasterSubDeviceKey as String: gameDeviceUID as CFString
        ]
        
        print("[AudioController] Description keys: \(description.keys)")
        
        // Create it
        let status = AudioHardwareCreateAggregateDevice(
            description as CFDictionary,
            &deviceID
        )
        
        guard status == noErr else {
            print("[AudioController] Failed with status: \(status)")
            throw SSChatMixError.aggregateCreationFailed
        }
        
        print("[AudioController] Successfully created multi-output device ID: \(deviceID)")
        
        return (deviceID, aggregateUID)
    }
    
    public func removeAggregateDevice(deviceID: AudioDeviceID) throws {
        let status = AudioHardwareDestroyAggregateDevice(deviceID)
        guard status == noErr else {
            throw SSChatMixError.aggregateRemovalFailed
        }
    }
    
    public func renameAggregateDevice(
        oldDeviceID: AudioDeviceID,
        newName: String,
        sourceDeviceUID: String
    ) throws -> (deviceID: AudioDeviceID, uid: String) {
        try removeAggregateDevice(deviceID: oldDeviceID)
        return try createAggregateDevice(name: newName, sourceDeviceUID: sourceDeviceUID)
    }
    
    // MARK: - Private Helpers
    
    private func isOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        
        return dataSize > 0
    }
    
    private func getDeviceName(_ deviceID: AudioDeviceID) throws -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize,
            &name
        )
        
        guard status == noErr else {
            throw SSChatMixError.audioControllerFailed("Failed to get device name")
        }
        
        return name as String
    }
    
    private func getDeviceUID(_ deviceID: AudioDeviceID) throws -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var uid: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize,
            &uid
        )
        
        guard status == noErr else {
            throw SSChatMixError.audioControllerFailed("Failed to get device UID")
        }
        
        return uid as String
    }
    
    private func checkIfAggregate(_ uid: String) -> Bool {
        return uid.contains("Aggregate") || uid.contains("com.k0nker.sschatmix.aggregate")
    }
}
