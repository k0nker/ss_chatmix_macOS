#!/usr/bin/env swift

import CoreAudio
import Foundation

// Get all audio devices
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

if status != noErr {
    print("Error getting device list size: \(status)")
    exit(1)
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

if status != noErr {
    print("Error getting device list: \(status)")
    exit(1)
}

print("Found \(devices.count) audio devices:")
print("")

for deviceID in devices {
    // Get device name
    var nameAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceNameCFString,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var name: CFString = "" as CFString
    var nameSize = UInt32(MemoryLayout<CFString>.size)
    
    status = AudioObjectGetPropertyData(
        deviceID,
        &nameAddress,
        0,
        nil,
        &nameSize,
        &name
    )
    
    let deviceName = (status == noErr) ? (name as String) : "Unknown"
    
    // Get device UID
    var uidAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var uid: CFString = "" as CFString
    var uidSize = UInt32(MemoryLayout<CFString>.size)
    
    status = AudioObjectGetPropertyData(
        deviceID,
        &uidAddress,
        0,
        nil,
        &uidSize,
        &uid
    )
    
    let deviceUID = (status == noErr) ? (uid as String) : "Unknown"
    
    if deviceName.contains("SSChatMix") || deviceUID.contains("SSChatMix") {
        print("✅ Device ID: \(deviceID)")
        print("   Name: \(deviceName)")
        print("   UID: \(deviceUID)")
        print("")
    }
}
