import SwiftUI
import Combine
import SSChatMixCore

struct DeviceSelectionView: View {
    let onSave: (Config) -> Void
    
    @StateObject private var viewModel = DeviceSelectionViewModel()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Configure Devices")
                .font(.title)
            
            Text("Select your audio devices and ChatMix controller")
                .foregroundColor(.secondary)
            
            Divider()
            
            // HID Device
            GroupBox("ChatMix Device") {
                if viewModel.hidDevices.isEmpty {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Searching...")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                } else {
                    Picker("Device:", selection: $viewModel.selectedHID) {
                        ForEach(viewModel.hidDevices, id: \.productID) { device in
                            Text("\(device.productName) (VID: \(String(format: "0x%04X", device.vendorID)) PID: \(String(format: "0x%04X", device.productID)))").tag(device as ChatMixDevice?)
                        }
                    }
                    .labelsHidden()
                }
            }
            
            // Game Device
            GroupBox("Game Audio Device") {
                Picker("Device:", selection: $viewModel.selectedGame) {
                    ForEach(viewModel.audioDevices, id: \.uid) { device in
                        Text(device.name).tag(device as AudioDeviceInfo?)
                    }
                }
                .labelsHidden()
            }
            
            // Chat Device
            GroupBox("Chat Audio Device") {
                Picker("Device:", selection: $viewModel.selectedChat) {
                    ForEach(viewModel.audioDevices, id: \.uid) { device in
                        Text(device.name).tag(device as AudioDeviceInfo?)
                    }
                }
                .labelsHidden()
            }
            
            // Output Device
            GroupBox("Output Device (Headphones/Speakers)") {
                Picker("Device:", selection: $viewModel.selectedOutput) {
                    ForEach(viewModel.audioDevices, id: \.uid) { device in
                        Text(device.name).tag(device as AudioDeviceInfo?)
                    }
                }
                .labelsHidden()
            }
            
            Spacer()
            
            HStack {
                Button("Refresh") {
                    viewModel.loadDevices()
                }
                
                Spacer()
                
                Button("Save") {
                    if let config = viewModel.createConfig() {
                        onSave(config)
                    }
                }
                .disabled(!viewModel.isValid)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 600, height: 500)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .onAppear {
            viewModel.loadDevices()
        }
    }
}

@MainActor
class DeviceSelectionViewModel: ObservableObject {
    @Published var hidDevices: [ChatMixDevice] = []
    @Published var audioDevices: [AudioDeviceInfo] = []
    
    @Published var selectedHID: ChatMixDevice?
    @Published var selectedGame: AudioDeviceInfo?
    @Published var selectedChat: AudioDeviceInfo?
    @Published var selectedOutput: AudioDeviceInfo?
    
    @Published var showError = false
    @Published var errorMessage = ""
    
    private let hidController = HIDController()
    private let audioController = AudioController()
    
    var isValid: Bool {
        selectedHID != nil &&
        selectedGame != nil &&
        selectedChat != nil &&
        selectedOutput != nil
    }
    
    func loadDevices() {
        // Load HID devices
        do {
            hidDevices = try hidController.listChatMixDevices()
            if hidDevices.count == 1 {
                selectedHID = hidDevices[0]
            }
        } catch {
            errorMessage = "Failed to find ChatMix devices: \(error.localizedDescription)"
            showError = true
        }
        
        // Load audio devices
        do {
            audioDevices = try audioController.listOutputDevices()
        } catch {
            errorMessage = "Failed to load audio devices: \(error.localizedDescription)"
            showError = true
        }
    }
    
    func createConfig() -> Config? {
        guard let hid = selectedHID,
              let game = selectedGame,
              let chat = selectedChat,
              let output = selectedOutput else {
            return nil
        }
        
        return Config(
            audioDevices: AudioDevicesConfig(
                game: AudioDeviceConfig(
                    id: UUID().uuidString,
                    name: game.name,
                    uid: game.uid,
                    isAggregate: false
                ),
                chat: AudioDeviceConfig(
                    id: UUID().uuidString,
                    name: chat.name,
                    uid: chat.uid,
                    isAggregate: false
                )
            ),
            hidDevice: HIDDeviceConfig(
                vendorId: String(format: "0x%04X", hid.vendorID),
                productId: String(format: "0x%04X", hid.productID)
            ),
            launchAgentEnabled: false,
            monitoringMode: true,
            outputDeviceUid: output.uid
        )
    }
}
