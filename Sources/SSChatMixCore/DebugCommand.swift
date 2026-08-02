import Foundation

public class DebugCommand {
    private let hidController = HIDController()
    private let audioController = AudioController()
    
    public init() {}
    
    public func execute() throws {
        print("🔍 ChatMix Device Debug\n")
        
        // First, list ChatMix-capable devices specifically
        let chatMixDevices = hidController.listChatMixDevices()
        
        if !chatMixDevices.isEmpty {
            print("✅ Found \(chatMixDevices.count) ChatMix-capable device(s):\n")
            for device in chatMixDevices {
                print("📱 \(device.productName)")
                print("   Vendor ID:  0x\(String(device.vendorID, radix: 16, uppercase: true))")
                print("   Product ID: 0x\(String(device.productID, radix: 16, uppercase: true))")
                print("   Usage Page: 0x\(String(device.usagePage, radix: 16, uppercase: true))")
                print("   ✅ ChatMix interface detected")
                print()
            }
        } else {
            print("❌ No ChatMix-capable devices found\n")
        }
        
        // Show all SteelSeries devices for debugging
        print(String(repeating: "─", count: 50))
        print("All SteelSeries Devices:\n")
        
        let devices = hidController.listSteelSeriesDevices()
        
        if devices.isEmpty {
            print("❌ No SteelSeries devices found")
            print("\nMake sure your headset is:")
            print("  • Powered on")
            print("  • USB dongle is connected")
            print("  • Not in use by SteelSeries software")
        } else {
            print("Found \(devices.count) SteelSeries device interface(s):\n")
            for (pid, name, usage) in devices {
                print("📱 \(name)")
                print("   Product ID: 0x\(String(pid, radix: 16, uppercase: true))")
                print("   Usage Page: 0x\(String(usage, radix: 16, uppercase: true))")
                
                if usage == 0xFF00 {
                    print("   ✅ ChatMix interface")
                } else if usage == 0x0C {
                    print("   ℹ️  Media controls interface")
                } else if usage == 0x01 {
                    print("   ℹ️  Audio interface")
                }
                print()
            }
        }
        
        // List audio devices
        print("\n" + String(repeating: "─", count: 50))
        print("🔊 Audio Output Devices\n")
        let audioDevices = try audioController.listOutputDevices()
        for (index, device) in audioDevices.enumerated() {
            print("\(index + 1). \(device.name)")
            print("   ID: \(device.id)")
            print("   UID: \(device.uid)")
            print()
        }
    }
}
