import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var controller: MenuBarController
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with status
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SSChatMix")
                        .font(.title2)
                        .fontWeight(.semibold)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(controller.isRunning ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(controller.isRunning ? "Running" : "Not Running")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLoginItemEnabled(newValue)
                    }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Main content in two columns
            HStack(alignment: .top, spacing: 20) {
                // Left column - Device Selection
                VStack(alignment: .leading, spacing: 16) {
                    Text("Devices")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        DevicePickerRow(
                            icon: "dial.medium",
                            label: "ChatMix Dial",
                            selection: $controller.selectedChatMixDevice,
                            devices: controller.availableChatMixDevices
                        ) { device in
                            "\(device.productName)"
                        } onChange: { device in
                            if let device = device {
                                controller.selectChatMixDevice(device)
                            }
                        }
                        
                        DevicePickerRow(
                            icon: "gamecontroller.fill",
                            label: "Game Audio",
                            selection: $controller.selectedGameDevice,
                            devices: controller.availableAudioDevices
                        ) { device in
                            device.name
                        } onChange: { device in
                            if let device = device {
                                controller.selectGameDevice(device)
                            }
                        }
                        
                        DevicePickerRow(
                            icon: "message.fill",
                            label: "Chat Audio",
                            selection: $controller.selectedChatDevice,
                            devices: controller.availableAudioDevices
                        ) { device in
                            device.name
                        } onChange: { device in
                            if let device = device {
                                controller.selectChatDevice(device)
                            }
                        }
                        
                        DevicePickerRow(
                            icon: "headphones",
                            label: "Output",
                            selection: $controller.selectedOutputDevice,
                            devices: controller.availableAudioDevices
                        ) { device in
                            device.name
                        } onChange: { device in
                            if let device = device {
                                controller.selectOutputDevice(device)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
                
                // Right column - Live Mix
                VStack(alignment: .leading, spacing: 16) {
                    Text("Live Mix")
                        .font(.headline)
                    
                    VStack(spacing: 16) {
                        VolumeBar(
                            icon: "gamecontroller.fill",
                            label: "Game",
                            value: controller.gameVolume,
                            color: .blue
                        )
                        
                        VolumeBar(
                            icon: "message.fill",
                            label: "Chat",
                            value: controller.chatVolume,
                            color: .green
                        )
                    }
                    
                    Text("Adjust the ChatMix dial to change the balance.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .frame(width: 600, height: 400)
        .onAppear {
            updateLoginItemStatus()
        }
    }
    
    private func setLoginItemEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                print("Login item enabled")
            } else {
                try SMAppService.mainApp.unregister()
                print("Login item disabled")
            }
        } catch {
            print("Failed to set login item: \(error)")
        }
    }
    
    private func updateLoginItemStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// Reusable device picker row component
struct DevicePickerRow<T: Hashable>: View {
    let icon: String
    let label: String
    @Binding var selection: T?
    let devices: [T]
    let deviceLabel: (T) -> String
    let onChange: (T?) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .frame(width: 16)
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Picker("", selection: $selection) {
                Text("Select Device...").tag(nil as T?)
                ForEach(devices, id: \.self) { device in
                    Text(deviceLabel(device)).tag(device as T?)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selection) { _, newValue in
                onChange(newValue)
            }
        }
    }
}

// Reusable volume bar component
struct VolumeBar: View {
    let icon: String
    let label: String
    let value: Int
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 16)
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(value)%")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .controlBackgroundColor))
                    
                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.7))
                        .frame(width: geometry.size.width * CGFloat(value) / 100)
                }
            }
            .frame(height: 8)
        }
    }
}

