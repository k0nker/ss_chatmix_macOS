#!/usr/bin/swift
import CoreAudio
import Foundation

func findDeviceByUID(_ uid: String) -> AudioDeviceID? {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var dataSize: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0,
        nil,
        &dataSize
    )
    
    guard status == kAudioHardwareNoError else {
        print("Error getting device list size: \(status)")
        return nil
    }
    
    let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
    
    status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0,
        nil,
        &dataSize,
        &deviceIDs
    )
    
    guard status == kAudioHardwareNoError else {
        print("Error getting device list: \(status)")
        return nil
    }
    
    // Search for device with matching UID
    for deviceID in deviceIDs {
        var uidPropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceUID: CFString = "" as CFString
        var uidDataSize = UInt32(MemoryLayout<CFString>.size)
        
        status = AudioObjectGetPropertyData(
            deviceID,
            &uidPropertyAddress,
            0,
            nil,
            &uidDataSize,
            &deviceUID
        )
        
        if status == kAudioHardwareNoError && (deviceUID as String) == uid {
            return deviceID
        }
    }
    
    return nil
}

func getDeviceStreams(_ deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> [AudioStreamID] {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var dataSize: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(
        deviceID,
        &propertyAddress,
        0,
        nil,
        &dataSize
    )
    
    guard status == kAudioHardwareNoError else {
        print("Error getting stream list size: \(status)")
        return []
    }
    
    let streamCount = Int(dataSize) / MemoryLayout<AudioStreamID>.size
    guard streamCount > 0 else {
        print("No streams found")
        return []
    }
    
    var streamIDs = [AudioStreamID](repeating: 0, count: streamCount)
    
    status = AudioObjectGetPropertyData(
        deviceID,
        &propertyAddress,
        0,
        nil,
        &dataSize,
        &streamIDs
    )
    
    guard status == kAudioHardwareNoError else {
        print("Error getting stream list: \(status)")
        return []
    }
    
    return streamIDs
}

// Main test
print("Testing SSChatMix Loopback Architecture\n")

// Find Game Device
if let gameDeviceID = findDeviceByUID("SSChatMixGameDevice") {
    print("✅ Found SSChatMixGameDevice (ID: \(gameDeviceID))")
    
    // Check for input streams
    let inputStreams = getDeviceStreams(gameDeviceID, scope: kAudioObjectPropertyScopeInput)
    print("  Input streams: \(inputStreams.count)")
    for (index, streamID) in inputStreams.enumerated() {
        print("    Stream \(index): \(streamID)")
    }
    
    // Check for output streams
    let outputStreams = getDeviceStreams(gameDeviceID, scope: kAudioObjectPropertyScopeOutput)
    print("  Output streams: \(outputStreams.count)")
    for (index, streamID) in outputStreams.enumerated() {
        print("    Stream \(index): \(streamID)")
    }
    
    if inputStreams.count > 0 && outputStreams.count > 0 {
        print("  ✅ Device has BOTH input and output streams (loopback ready)")
    } else {
        print("  ❌ Device missing required streams")
    }
} else {
    print("❌ SSChatMixGameDevice not found")
}

print("")

// Find Chat Device
if let chatDeviceID = findDeviceByUID("SSChatMixChatDevice") {
    print("✅ Found SSChatMixChatDevice (ID: \(chatDeviceID))")
    
    // Check for input streams
    let inputStreams = getDeviceStreams(chatDeviceID, scope: kAudioObjectPropertyScopeInput)
    print("  Input streams: \(inputStreams.count)")
    for (index, streamID) in inputStreams.enumerated() {
        print("    Stream \(index): \(streamID)")
    }
    
    // Check for output streams
    let outputStreams = getDeviceStreams(chatDeviceID, scope: kAudioObjectPropertyScopeOutput)
    print("  Output streams: \(outputStreams.count)")
    for (index, streamID) in outputStreams.enumerated() {
        print("    Stream \(index): \(streamID)")
    }
    
    if inputStreams.count > 0 && outputStreams.count > 0 {
        print("  ✅ Device has BOTH input and output streams (loopback ready)")
    } else {
        print("  ❌ Device missing required streams")
    }
} else {
    print("❌ SSChatMixChatDevice not found")
}

print("\n✅ Loopback test complete!")
