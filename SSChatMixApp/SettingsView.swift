import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var controller: MenuBarController
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    
    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLoginItemEnabled(newValue)
                    }
            } header: {
                Text("General")
            }
            
            Section {
                Picker("ChatMix Device:", selection: Binding(
                    get: { controller.selectedChatMixDevice ?? controller.availableChatMixDevices.first },
                    set: { device in
                        if let device = device {
                            controller.selectChatMixDevice(device)
                        }
                    }
                )) {
                    Text("Select Device...").tag(nil as ChatMixDevice?)
                    ForEach(controller.availableChatMixDevices, id: \.self) { device in
                        Text("\(device.productName) (VID: \(String(format: "0x%04X", device.vendorID)) PID: \(String(format: "0x%04X", device.productID)))")
                            .tag(device as ChatMixDevice?)
                    }
                }
                .labelsHidden()
                
                if let device = controller.selectedChatMixDevice {
                    HStack {
                        Text("Status:")
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(controller.isRunning ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(controller.isRunning ? "Connected" : "Not Running")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("ChatMix Dial")
            } footer: {
                Text("Select your SteelSeries Arctis Nova ChatMix dial.")
                    .font(.caption)
            }
            
            Section {
                Picker("Game Audio:", selection: Binding(
                    get: { controller.selectedGameDevice ?? controller.availableAudioDevices.first },
                    set: { device in
                        if let device = device {
                            controller.selectGameDevice(device)
                        }
                    }
                )) {
                    Text("Select Device...").tag(nil as AudioDeviceInfo?)
                    ForEach(controller.availableAudioDevices, id: \.self) { device in
                        Text(device.name).tag(device as AudioDeviceInfo?)
                    }
                }
                .labelsHidden()
                
                Picker("Chat Audio:", selection: Binding(
                    get: { controller.selectedChatDevice ?? controller.availableAudioDevices.first },
                    set: { device in
                        if let device = device {
                            controller.selectChatDevice(device)
                        }
                    }
                )) {
                    Text("Select Device...").tag(nil as AudioDeviceInfo?)
                    ForEach(controller.availableAudioDevices, id: \.self) { device in
                        Text(device.name).tag(device as AudioDeviceInfo?)
                    }
                }
                .labelsHidden()
            } header: {
                Text("Virtual Audio Devices")
            } footer: {
                Text("Route game audio to the first device and chat/Discord to the second device.")
                    .font(.caption)
            }
            
            Section {
                Picker("Output Device:", selection: Binding(
                    get: { controller.selectedOutputDevice ?? controller.availableAudioDevices.first },
                    set: { device in
                        if let device = device {
                            controller.selectOutputDevice(device)
                        }
                    }
                )) {
                    Text("Select Device...").tag(nil as AudioDeviceInfo?)
                    ForEach(controller.availableAudioDevices, id: \.self) { device in
                        Text(device.name).tag(device as AudioDeviceInfo?)
                    }
                }
                .labelsHidden()
            } header: {
                Text("Physical Output")
            } footer: {
                Text("Your actual headphones or speakers where you'll hear the mixed audio.")
                    .font(.caption)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "gamecontroller.fill")
                            .foregroundColor(.blue)
                        Text("Game Volume: \(controller.gameVolume)%")
                        Spacer()
                        ProgressView(value: Double(controller.gameVolume), total: 100)
                            .frame(width: 100)
                    }
                    
                    HStack {
                        Image(systemName: "message.fill")
                            .foregroundColor(.green)
                        Text("Chat Volume: \(controller.chatVolume)%")
                        Spacer()
                        ProgressView(value: Double(controller.chatVolume), total: 100)
                            .frame(width: 100)
                    }
                }
            } header: {
                Text("Live Volume Mix")
            } footer: {
                Text("Adjust the ChatMix dial to change the balance.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 550, height: 600)
        .onAppear {
            // Load current login item status
            updateLoginItemStatus()
        }
    }
    
    private func setLoginItemEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                print("✅ Login item enabled")
            } else {
                try SMAppService.mainApp.unregister()
                print("❌ Login item disabled")
            }
        } catch {
            print("⚠️ Failed to set login item: \(error)")
        }
    }
    
    private func updateLoginItemStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

