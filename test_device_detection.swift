#!/usr/bin/env swift

import CoreAudio
import Foundation

func findDevice(uid: String) -> AudioDeviceID? {
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
    
    guard status == noErr else {
        print("Error getting device list size: \(status)")
        return nil
    }
    
    let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
    
    status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0,
        nil,
        &dataSize,
        &devices
    )
    
    guard status == noErr else {
        print("Error getting device list: \(status)")
        return nil
    }
    
    for deviceID in devices {
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceUID: CFString = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        
        status = AudioObjectGetPropertyData(
            deviceID,
            &uidAddress,
            0,
            nil,
            &uidSize,
            &deviceUID
        )
        
        if status == noErr && (deviceUID as String) == uid {
            return deviceID
        }
    }
    
    return nil
}

print("Testing SSChatMix device detection...")
print("")

if let gameDevice = findDevice(uid: "SSChatMixGameDevice") {
    print("✅ Found SSChatMix Game Device!")
    print("   Device ID: \(gameDevice)")
    
    // Test volume control
    var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var volume: Float32 = 0.0
    var volumeSize = UInt32(MemoryLayout<Float32>.size)
    
    let status = AudioObjectGetPropertyData(
        gameDevice,
        &volumeAddress,
        0,
        nil,
        &volumeSize,
        &volume
    )
    
    if status == noErr {
        print("   Current Volume: \(volume)")
    } else {
        print("   Volume read error: \(status)")
    }
} else {
    print("❌ SSChatMix Game Device NOT FOUND")
}

print("")

if let chatDevice = findDevice(uid: "SSChatMixChatDevice") {
    print("✅ Found SSChatMix Chat Device!")
    print("   Device ID: \(chatDevice)")
} else {
    print("❌ SSChatMix Chat Device NOT FOUND")
}
