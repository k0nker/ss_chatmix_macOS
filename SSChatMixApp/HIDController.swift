import Foundation
import IOKit.hid
import Darwin

// Load IOHIDDeviceOpenSync from IOKit framework (not exposed in Swift's IOKit.hid)
private let _iokitHandle: UnsafeMutableRawPointer? = {
    dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
}()
private let IOHIDDeviceOpenSync: (IOHIDDevice, UInt32) -> IOReturn = {
    guard let handle = _iokitHandle else { return { _, _ in kIOReturnInternalError } }
    guard let symbol = dlsym(handle, "IOHIDDeviceOpenSync") else { return { _, _ in kIOReturnInternalError } }
    return unsafeBitCast(symbol, to: ((IOHIDDevice, UInt32) -> IOReturn).self)
}()

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
    
    // Query synchronization
    private var lastReportData: [UInt8] = []
    private var querySemaphore = DispatchSemaphore(value: 0)
    private var isWaitingForQuery = false
    
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
            
            // Extract the actual IOHIDDevice from the manager's device set for query support
            let queryManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            let queryMatching: [String: Any] = [
                kIOHIDVendorIDKey: self.vendorID,
                kIOHIDProductIDKey: self.productID,
                kIOHIDPrimaryUsagePageKey: self.usagePage
            ]
            IOHIDManagerSetDeviceMatching(queryManager, queryMatching as CFDictionary)
            IOHIDManagerOpen(queryManager, IOOptionBits(kIOHIDOptionsTypeNone))
            if let deviceSet = IOHIDManagerCopyDevices(queryManager) as? Set<IOHIDDevice>,
               let firstDevice = deviceSet.first {
                // Open the device so we can send feature report queries
                let openResult = IOHIDDeviceOpenSync(firstDevice, IOOptionBits(kIOHIDOptionsTypeNone))
                if openResult == kIOReturnSuccess {
                    self.device = firstDevice
                    let devName = IOHIDDeviceGetProperty(firstDevice, kIOHIDProductKey as CFString) as? String ?? "unknown"
                    print("   Device extracted and opened for query support: \(devName)")
                } else {
                    print("   ⚠️  Failed to open device for queries (result: \(openResult))")
                }
            }
            // queryManager is auto-released in Swift; no CFRelease needed
            
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
    
    // MARK: - Query ChatMix Position
    
    /// Query the dongle for the current ChatMix dial position.
    /// Tries multiple known HID query packets for different Arctis generations.
    /// Returns (gameVolume, chatVolume) in range 0-100, or nil if all queries fail.
    public func queryChatMixPosition() -> (gameVolume: Int, chatVolume: Int)? {
        guard let device = device else {
            print("⚠️  No device available for query")
            return nil
        }
        
        // Try Arctis 7/Pro query packet: [0x06, 0x24]
        // Response: 8 bytes, game at byte 2, chat at byte 3, range 191-255
        if let result = tryArctis7Query(device) {
            print("✅ ChatMix position from Arctis 7 query: game=\(result.gameVolume) chat=\(result.chatVolume)")
            return result
        }
        
        // Try Arctis 9 query packet: [0x00, 0x20]
        // Response: 12 bytes, game at byte 9, chat at byte 10, range 0-19
        if let result = tryArctis9Query(device) {
            print("✅ ChatMix position from Arctis 9 query: game=\(result.gameVolume) chat=\(result.chatVolume)")
            return result
        }
        
        // Try Nova 7/7X query packet: [0x00, 0x10]
        // Response: 6 bytes, game at byte 4, chat at byte 5, range 0-100
        if let result = tryNova7Query(device) {
            print("✅ ChatMix position from Nova 7 query: game=\(result.gameVolume) chat=\(result.chatVolume)")
            return result
        }
        
        // Try Nova 5 query packet: [0x00, 0x10]
        // Response: 7 bytes, game at byte 5, chat at byte 6, range 0-100
        if let result = tryNova5Query(device) {
            print("✅ ChatMix position from Nova 5 query: game=\(result.gameVolume) chat=\(result.chatVolume)")
            return result
        }
        
        print("⚠️  All ChatMix query attempts failed — using default volumes (100/100)")
        return nil
    }
    
    /// Send a feature report query and wait for the input report response.
    /// Returns the response data if successful, nil on timeout/failure.
    private func sendQueryAndWait(_ device: IOHIDDevice, featureReport: [UInt8], featureReportID: UInt8, expectedInputReportID: UInt8, responseLength: Int, timeout: TimeInterval = 2.0) -> [UInt8]? {
        // Reset state
        lastReportData = []
        isWaitingForQuery = true
        
        // Send feature report query
        var featureReportData = featureReport
        let featureResult = IOHIDDeviceSetReport(device,
                                                 kIOHIDReportTypeFeature,
                                                 Int(featureReportID),
                                                 &featureReportData,
                                                 featureReport.count)
        guard featureResult == kIOReturnSuccess else {
            print("   Feature report send failed: \(featureResult)")
            return nil
        }
        
        // Wait for input report response
        let waitResult = querySemaphore.wait(timeout: .now() + timeout)
        
        guard waitResult == .success, !lastReportData.isEmpty else {
            print("   Query timeout or no response received")
            return nil
        }
        
        return lastReportData
    }
    
    private func tryArctis7Query(_ device: IOHIDDevice) -> (gameVolume: Int, chatVolume: Int)? {
        // Query: [0x06, 0x24] — feature report ID 0x24
        guard let response = sendQueryAndWait(device,
                                              featureReport: [0x06, 0x24],
                                              featureReportID: 0x24,
                                              expectedInputReportID: 0x45,
                                              responseLength: 8) else {
            return nil
        }
        
        guard response.count >= 4 else { return nil }
        
        let gameRaw = Int(response[2])
        let chatRaw = Int(response[3])
        
        // Values range 191-255, 255 = neutral (center)
        let gameVol = (gameRaw == 0) ? 100 : Int(mapValue(gameRaw, fromMin: 191, fromMax: 255, toMin: 0, toMax: 100))
        let chatVol = (chatRaw == 0) ? 100 : Int(mapValue(chatRaw, fromMin: 191, fromMax: 255, toMin: 0, toMax: 100))
        
        return (gameVol, chatVol)
    }
    
    private func tryArctis9Query(_ device: IOHIDDevice) -> (gameVolume: Int, chatVolume: Int)? {
        // Query: [0x00, 0x20] — feature report ID 0x20
        guard let response = sendQueryAndWait(device,
                                              featureReport: [0x00, 0x20],
                                              featureReportID: 0x20,
                                              expectedInputReportID: 0x01,
                                              responseLength: 12) else {
            return nil
        }
        
        guard response.count >= 11 else { return nil }
        
        let gameRaw = Int(response[9])
        let chatRaw = Int(response[10])
        
        // Values range 0-19
        let gameVol = Int(mapValue(gameRaw, fromMin: 0, fromMax: 19, toMin: 0, toMax: 100))
        let chatVol = Int(mapValue(chatRaw, fromMin: 0, fromMax: 19, toMin: 0, toMax: 100))
        
        return (gameVol, chatVol)
    }
    
    private func tryNova7Query(_ device: IOHIDDevice) -> (gameVolume: Int, chatVolume: Int)? {
        // Query: [0x00, 0x10] — feature report ID 0x10
        guard let response = sendQueryAndWait(device,
                                              featureReport: [0x00, 0x10],
                                              featureReportID: 0x10,
                                              expectedInputReportID: 0x01,
                                              responseLength: 6) else {
            return nil
        }
        
        guard response.count >= 6 else { return nil }
        
        let gameRaw = Int(response[4])
        let chatRaw = Int(response[5])
        
        // Values range 0-100
        return (gameRaw, chatRaw)
    }
    
    private func tryNova5Query(_ device: IOHIDDevice) -> (gameVolume: Int, chatVolume: Int)? {
        // Query: [0x00, 0x10] — feature report ID 0x10
        guard let response = sendQueryAndWait(device,
                                              featureReport: [0x00, 0x10],
                                              featureReportID: 0x10,
                                              expectedInputReportID: 0x01,
                                              responseLength: 7) else {
            return nil
        }
        
        guard response.count >= 7 else { return nil }
        
        let gameRaw = Int(response[5])
        let chatRaw = Int(response[6])
        
        // Values range 0-100
        return (gameRaw, chatRaw)
    }
    
    private func mapValue(_ value: Int, fromMin: Int, fromMax: Int, toMin: Int, toMax: Int) -> Int {
        guard fromMin != fromMax else { return toMin }
        let ratio = Double(value - fromMin) / Double(fromMax - fromMin)
        return toMin + Int(ratio * Double(toMax - toMin))
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
        
        // Check if we're waiting for a query response
        if isWaitingForQuery {
            // Copy the report data and signal the semaphore
            let reportData = [UInt8](UnsafeBufferPointer(start: dataPtr, count: dataLength))
            lastReportData = reportData
            isWaitingForQuery = false
            querySemaphore.signal()
            return
        }
        
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

