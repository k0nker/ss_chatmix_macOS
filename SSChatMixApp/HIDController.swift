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
    
    // Dedicated thread for HID processing (isolated from main thread)
    // This prevents UI operations (modals, Settings window) from blocking HID input,
    // which would starve audio processing and cause crackling
    private var hidThread: Thread?
    private var hidRunLoop: CFRunLoop?
    
    // Debouncing for volume changes
    private var lastUpdateTime: Date = Date.distantPast
    private var lastGameVolume: Int = -1
    private var lastChatVolume: Int = -1
    private let debounceInterval: TimeInterval = 0.05  // 50ms debounce
    
    // Track logged report IDs to avoid spam
    private var loggedReportIDs = Set<UInt8>()
    
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
            print("HID device not detected - VID: \(String(format: "0x%04X", vendorID)) PID: \(String(format: "0x%04X", productID))")
            print("   This might be normal if the device hasn't been plugged in yet")
        } else {
            print("HID device detected")
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
        
        // Start background thread with its own run loop
        // This isolates HID processing from main thread blocking (modals, etc.)
        let semaphore = DispatchSemaphore(value: 0)
        var startError: Error?
        
        hidThread = Thread { [weak self] in
            guard let self = self else { return }
            
            // Get the run loop for this thread
            self.hidRunLoop = CFRunLoopGetCurrent()
            
            // Schedule HID manager on this thread's run loop
            IOHIDManagerScheduleWithRunLoop(
                manager,
                self.hidRunLoop!,
                CFRunLoopMode.defaultMode.rawValue
            )
            
            let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            
            if openResult != kIOReturnSuccess {
                startError = SSChatMixError.hidControllerFailed("Failed to open HID manager (result: \(openResult))")
                semaphore.signal()
                return
            }
            
            print("   HID manager opened successfully on background thread, listening for reports...")
            semaphore.signal()
            
            // Run the run loop
            CFRunLoopRun()
        }
        
        hidThread?.qualityOfService = .userInteractive
        hidThread?.start()
        
        // Wait for thread to start
        semaphore.wait()
        
        if let error = startError {
            throw error
        }
    }
    
    public func stop() {
        guard let manager = manager else { return }
        
        // Stop on the background thread
        if let runLoop = hidRunLoop {
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                runLoop,
                CFRunLoopMode.defaultMode.rawValue
            )
            
            // Stop the run loop
            CFRunLoopStop(runLoop)
        }
        
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        
        self.manager = nil
        self.device = nil
        self.hidRunLoop = nil
        self.hidThread = nil
    }
    
    // MARK: - Input Handling
    
    private func handleInputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        _ = IOHIDElementGetUsagePage(element)
        
        let dataLength = IOHIDValueGetLength(value)
        let dataPtr = IOHIDValueGetBytePtr(value)
        
        guard dataLength >= 3 else { 
            print("HID report too short: \(dataLength) bytes")
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
            if !loggedReportIDs.contains(reportID) {
                print("HID report with ID \(String(format: "0x%02X", reportID)) (expected 0x45)")
                loggedReportIDs.insert(reportID)
            }
        }
    }
}

