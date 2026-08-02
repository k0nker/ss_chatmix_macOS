import SwiftUI
import SSChatMixCore

struct SettingsView: View {
    let config: Config?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title)
            
            Divider()
            
            if let config = config {
                GroupBox("Current Configuration") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Game Device:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(config.audioDevices.game.name)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Chat Device:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(config.audioDevices.chat.name)
                                .foregroundColor(.secondary)
                        }
                        
                        if let outputUID = config.outputDeviceUid {
                            HStack {
                                Text("Output:")
                                    .fontWeight(.medium)
                                Spacer()
                                Text(outputUID)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        
                        HStack {
                            Text("HID Device:")
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(config.hidDevice.vendorId):\(config.hidDevice.productId)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                GroupBox("Info") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• The controller runs inside this menu bar app")
                        Text("• Volume changes are processed in real-time")
                        Text("• Config stored in Application Support folder")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            } else {
                Text("No configuration found. Use 'Select Devices...' to configure.")
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 500, height: 300)
    }
}
