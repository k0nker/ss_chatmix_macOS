import Foundation
import IOKit.hid

public struct ChatMixDevice: Hashable {
    public let vendorID: Int
    public let productID: Int
    public let productName: String
    public let usagePage: Int
    
    public init(vendorID: Int, productID: Int, productName: String, usagePage: Int) {
        self.vendorID = vendorID
        self.productID = productID
        self.productName = productName
        self.usagePage = usagePage
    }
}

public class HIDController {
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    public var onDialChanged: ((Int, Int) -> Void)?
    
    // Debouncing for volume changes
    private var lastUpdateTime: Date = Date.distantPast
    private var lastGameVolume: Int = -1
    private var lastChatVolume: Int = -1
    private let debounceInterval: TimeInterval = 0.05  // 50ms debounce
    
    // Device IDs - configurable
    private var vendorID: Int = 0x1038  // SteelSeries (default)
    private var productID: Int = 0x2202 // Default, but should be configured
    private let usagePage = 0xFF00 // ChatMix interface
    
    public init() {}
    
    // Configure with specific device IDs
    public func configure(vendorID: Int, productID: Int) {
        self.vendorID = vendorID
        self.productID = productID
    }
    
    // MARK: - Device Detection
    
    public func detectDevice() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        let matchingDict: [String: Any] = [
            kIOHIDVendorIDKey: vendorID,
            kIOHIDPrimaryUsagePageKey: usagePage
        ]
        
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        
        let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        
        return deviceSet?.isEmpty == false
    }
    
    public func listSteelSeriesDevices() -> [(productID: Int, productName: String, usagePage: Int)] {
        var devices: [(Int, String, Int)] = []
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        let matchingDict: [String: Any] = [
            kIOHIDVendorIDKey: 0x1038  // SteelSeries
        ]
        
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        
        if let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in deviceSet {
                let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
                let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
                let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
                devices.append((pid, productName, usage))
            }
        }
        
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        return devices
    }
    
    // List only ChatMix-capable devices (UsagePage 0xFF00)
    public func listChatMixDevices() -> [ChatMixDevice] {
        var devices: [ChatMixDevice] = []
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        let matchingDict: [String: Any] = [
            kIOHIDVendorIDKey: 0x1038,  // SteelSeries
            kIOHIDPrimaryUsagePageKey: 0xFF00  // ChatMix interface
        ]
        
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        
        if let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in deviceSet {
                let vid = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
                let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
                let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"
                let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
                
                devices.append(ChatMixDevice(
                    vendorID: vid,
                    productID: pid,
                    productName: productName,
                    usagePage: usage
                ))
            }
        }
        
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        return devices
    }
    
    // MARK: - Start Listening
    
    public func start() throws {
        // First check if device is detectable
        if !detectDevice() {
            print("⚠️  HID device not detected - VID: \(String(format: "0x%04X", vendorID)) PID: \(String(format: "0x%04X", productID))")
            print("   This might be normal if the device hasn't been plugged in yet")
        } else {
            print("✅ HID device detected")
        }
        
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        guard let manager = manager else {
            throw SSChatMixError.hidControllerFailed("Failed to create HID manager")
        }
        
        let matchingDict: [String: Any] = [
            kIOHIDVendorIDKey: vendorID,
            kIOHIDProductIDKey: productID,
            kIOHIDPrimaryUsagePageKey: usagePage
        ]
        
        print("   Matching: VID=\(String(format: "0x%04X", vendorID)) PID=\(String(format: "0x%04X", productID)) UsagePage=\(String(format: "0x%04X", usagePage))")
        
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)
        
        // Set up input value callback
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { context, result, sender, value in
            guard let context = context else { return }
            let controller = Unmanaged<HIDController>.fromOpaque(context).takeUnretainedValue()
            controller.handleInputValue(value)
        }, context)
        
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetCurrent(),
            CFRunLoopMode.defaultMode.rawValue
        )
        
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        
        guard openResult == kIOReturnSuccess else {
            throw SSChatMixError.hidControllerFailed("Failed to open HID manager (result: \(openResult))")
        }
        
        print("   HID manager opened successfully, listening for reports...")
    }
    
    public func stop() {
        guard let manager = manager else { return }
        
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetCurrent(),
            CFRunLoopMode.defaultMode.rawValue
        )
        
        self.manager = nil
        self.device = nil
    }
    
    // MARK: - Input Handling
    
    private func handleInputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        
        let dataLength = IOHIDValueGetLength(value)
        let dataPtr = IOHIDValueGetBytePtr(value)
        
        guard dataLength >= 3 else { 
            print("⚠️  HID report too short: \(dataLength) bytes")
            return 
        }
        
        // Report format: [0x45, game_volume, chat_volume]
        let reportID = dataPtr[0]
        
        if reportID == 0x45 {
            let gameVolume = Int(dataPtr[1])  // 0-100
            let chatVolume = Int(dataPtr[2])  // 0-100
            
            // Debounce: Only call callback if values changed AND enough time passed
            let now = Date()
            let timeSinceLastUpdate = now.timeIntervalSince(lastUpdateTime)
            
            if (gameVolume != lastGameVolume || chatVolume != lastChatVolume) && timeSinceLastUpdate >= debounceInterval {
                lastGameVolume = gameVolume
                lastChatVolume = chatVolume
                lastUpdateTime = now
                
                // Call the callback with both volumes
                onDialChanged?(gameVolume, chatVolume)
            }
        } else {
            // Log unexpected report IDs (but only once per ID to avoid spam)
            static var loggedReportIDs = Set<UInt8>()
            if !loggedReportIDs.contains(reportID) {
                print("ℹ️  HID report with ID \(String(format: "0x%02X", reportID)) (expected 0x45)")
                loggedReportIDs.insert(reportID)
            }
        }
    }
}
