import SwiftUI
import SSChatMixCore

struct SetupWizardView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = SetupWizardViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("ChatMix Setup Wizard")
                .font(.title)
                .padding(.top)
            
            switch viewModel.currentStep {
            case .hidDevice:
                HIDDeviceSelectionView(viewModel: viewModel)
            case .gameDevice:
                AudioDeviceSelectionView(
                    title: "Select Game Audio Device",
                    subtitle: "Choose the virtual device for game audio",
                    devices: viewModel.outputDevices,
                    selectedDevice: $viewModel.selectedGameDevice,
                    viewModel: viewModel
                )
            case .chatDevice:
                AudioDeviceSelectionView(
                    title: "Select Chat Audio Device",
                    subtitle: "Choose the virtual device for chat audio",
                    devices: viewModel.outputDevices,
                    selectedDevice: $viewModel.selectedChatDevice,
                    viewModel: viewModel
                )
            case .outputDevice:
                AudioDeviceSelectionView(
                    title: "Select Physical Output Device",
                    subtitle: "Choose your headphones/speakers (where you'll hear the mix)",
                    devices: viewModel.outputDevices,
                    selectedDevice: $viewModel.selectedOutputDevice,
                    viewModel: viewModel
                )
            case .complete:
                CompletionView(viewModel: viewModel, dismiss: dismiss)
            }
            
            Spacer()
            
            // Navigation buttons
            if viewModel.currentStep != .complete {
                HStack {
                    if viewModel.currentStep != .hidDevice {
                        Button("Back") {
                            viewModel.previousStep()
                        }
                    }
                    
                    Spacer()
                    
                    Button(viewModel.currentStep == .outputDevice ? "Finish" : "Next") {
                        viewModel.nextStep()
                    }
                    .disabled(!viewModel.canProceed)
                }
                .padding()
            }
        }
        .frame(width: 600, height: 500)
        .padding()
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

struct HIDDeviceSelectionView: View {
    @ObservedObject var viewModel: SetupWizardViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Select ChatMix Device")
                .font(.headline)
            
            Text("Connect your SteelSeries Arctis headset and select it below:")
                .foregroundColor(.secondary)
            
            if viewModel.hidDevices.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Searching for devices...")
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                List(viewModel.hidDevices, id: \.productId) { device in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name)
                                .font(.body)
                            Text("VID: \(device.vendorId) PID: \(device.productId)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if viewModel.selectedHIDDevice?.productId == device.productId {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectedHIDDevice = device
                    }
                }
                .frame(height: 200)
            }
            
            Button("Refresh Device List") {
                viewModel.loadDevices()
            }
            .buttonStyle(.borderless)
        }
    }
}

struct AudioDeviceSelectionView: View {
    let title: String
    let subtitle: String
    let devices: [AudioDeviceInfo]
    @Binding var selectedDevice: AudioDeviceInfo?
    @ObservedObject var viewModel: SetupWizardViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title)
                .font(.headline)
            
            Text(subtitle)
                .foregroundColor(.secondary)
            
            List(devices, id: \.uid) { device in
                HStack {
                    VStack(alignment: .leading) {
                        Text(device.name)
                            .font(.body)
                        Text(device.uid)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if selectedDevice?.uid == device.uid {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedDevice = device
                }
            }
            .frame(height: 250)
        }
    }
}

struct CompletionView: View {
    @ObservedObject var viewModel: SetupWizardViewModel
    let dismiss: DismissAction
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Setup Complete!")
                .font(.title)
            
            Text("Your ChatMix controller is now configured and starting...")
                .foregroundColor(.secondary)
            
            if viewModel.isStarting {
                ProgressView()
                    .scaleEffect(0.8)
            }
            
            Button("Done") {
                dismiss()
            }
            .padding(.top)
        }
    }
}

@MainActor
class SetupWizardViewModel: ObservableObject {
    enum Step {
        case hidDevice, gameDevice, chatDevice, outputDevice, complete
    }
    
    @Published var currentStep: Step = .hidDevice
    @Published var hidDevices: [ChatMixDevice] = []
    @Published var outputDevices: [AudioDeviceInfo] = []
    
    @Published var selectedHIDDevice: ChatMixDevice?
    @Published var selectedGameDevice: AudioDeviceInfo?
    @Published var selectedChatDevice: AudioDeviceInfo?
    @Published var selectedOutputDevice: AudioDeviceInfo?
    
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var isStarting = false
    
    private let hidController = HIDController()
    private let audioController = AudioController()
    private let configManager = ConfigManager()
    private let processManager = ProcessManager()
    
    var canProceed: Bool {
        switch currentStep {
        case .hidDevice: return selectedHIDDevice != nil
        case .gameDevice: return selectedGameDevice != nil
        case .chatDevice: return selectedChatDevice != nil
        case .outputDevice: return selectedOutputDevice != nil
        case .complete: return false
        }
    }
    
    func loadDevices() {
        // Load HID devices
        do {
            hidDevices = try hidController.listChatMixDevices()
            if hidDevices.count == 1 {
                selectedHIDDevice = hidDevices[0]
            }
        } catch {
            errorMessage = "Failed to find ChatMix devices: \(error.localizedDescription)"
            showError = true
        }
        
        // Load audio devices
        do {
            outputDevices = try audioController.listOutputDevices()
        } catch {
            errorMessage = "Failed to load audio devices: \(error.localizedDescription)"
            showError = true
        }
    }
    
    func nextStep() {
        switch currentStep {
        case .hidDevice:
            currentStep = .gameDevice
        case .gameDevice:
            currentStep = .chatDevice
        case .chatDevice:
            currentStep = .outputDevice
        case .outputDevice:
            saveConfiguration()
        case .complete:
            break
        }
    }
    
    func previousStep() {
        switch currentStep {
        case .hidDevice:
            break
        case .gameDevice:
            currentStep = .hidDevice
        case .chatDevice:
            currentStep = .gameDevice
        case .outputDevice:
            currentStep = .chatDevice
        case .complete:
            currentStep = .outputDevice
        }
    }
    
    func saveConfiguration() {
        guard let hid = selectedHIDDevice,
              let game = selectedGameDevice,
              let chat = selectedChatDevice,
              let output = selectedOutputDevice else {
            return
        }
        
        let config = Config(
            audioDevices: Config.AudioDevices(
                game: Config.AudioDevice(uid: game.uid, name: game.name),
                chat: Config.AudioDevice(uid: chat.uid, name: chat.name)
            ),
            hidDevice: Config.HIDDeviceConfig(
                vendorId: hid.vendorId,
                productId: hid.productId
            ),
            monitoringMode: true,
            outputDeviceUid: output.uid
        )
        
        do {
            try configManager.save(config)
            
            // Set output device to 100%
            if let outputID = try audioController.findDevice(byUID: output.uid) {
                try audioController.setVolume(100, for: outputID)
            }
            
            currentStep = .complete
            startController()
        } catch {
            errorMessage = "Failed to save configuration: \(error.localizedDescription)"
            showError = true
        }
    }
    
    func startController() {
        isStarting = true
        
        // Kill any existing process
        try? processManager.killRunningProcess()
        
        // Wait a moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            // Start controller via nohup
            let binaryPath = "/usr/local/bin/sschatmix"
            let command = "nohup \(binaryPath) > /dev/null 2>&1 &"
            
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["-c", command]
            
            do {
                try task.run()
                self?.isStarting = false
            } catch {
                self?.errorMessage = "Failed to start controller: \(error.localizedDescription)"
                self?.showError = true
                self?.isStarting = false
            }
        }
    }
}
