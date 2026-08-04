import SwiftUI
import ServiceManagement
import Sparkle
import Combine

struct SettingsView: View {
    @ObservedObject var controller: MenuBarController
    @ObservedObject private var updater = SparkleUpdaterViewModel.shared
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    
    // Throttled volume values to prevent UI overload during rapid dial changes
    @State private var displayGameVolume: Int = 50
    @State private var displayChatVolume: Int = 50
    
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
                        
                        // Game and Chat devices are locked to SSChatMix virtual devices
                        HStack(spacing: 8) {
                            Image(systemName: "gamecontroller.fill")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Game Audio")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("SSChatMix Game")
                                    .font(.system(size: 12))
                            }
                            Spacer()
                            Image(systemName: "lock.fill")
                                .foregroundColor(.secondary)
                                .font(.caption2)
                        }
                        .padding(.vertical, 4)
                        .help("Game audio source is locked to the SSChatMix Game virtual device")
                        
                        HStack(spacing: 8) {
                            Image(systemName: "message.fill")
                                .foregroundColor(.green)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Chat Audio")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("SSChatMix Chat")
                                    .font(.system(size: 12))
                            }
                            Spacer()
                            Image(systemName: "lock.fill")
                                .foregroundColor(.secondary)
                                .font(.caption2)
                        }
                        .padding(.vertical, 4)
                        .help("Chat audio source is locked to the SSChatMix Chat virtual device")
                        
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
                            value: displayGameVolume,
                            color: .blue
                        )
                        
                        VolumeBar(
                            icon: "message.fill",
                            label: "Chat",
                            value: displayChatVolume,
                            color: .green
                        )
                    }
                    
                    Text("Adjust the ChatMix dial to change the balance.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    
                    Divider()
                        .padding(.vertical, 12)
                    
                    // Updates section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Updates")
                            .font(.headline)
                        
                        Toggle("Automatically check for updates", isOn: Binding(
                            get: { updater.automaticallyChecksForUpdates },
                            set: { updater.setAutomaticallyChecksForUpdates($0) }
                        ))
                        .toggleStyle(.switch)
                        
                        Button(action: {
                            updater.checkForUpdates()
                        }) {
                            Text("Check for Updates...")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!updater.canCheckForUpdates)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .frame(width: 600, height: 400)
        .onAppear {
            updateLoginItemStatus()
            // Initialize display volumes
            displayGameVolume = controller.gameVolume
            displayChatVolume = controller.chatVolume
        }
        // Throttle volume updates to prevent UI overload (max 4 updates/sec instead of 20/sec)
        .onReceive(controller.$gameVolume.throttle(for: .milliseconds(250), scheduler: RunLoop.main, latest: true)) { newValue in
            displayGameVolume = newValue
        }
        .onReceive(controller.$chatVolume.throttle(for: .milliseconds(250), scheduler: RunLoop.main, latest: true)) { newValue in
            displayChatVolume = newValue
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

