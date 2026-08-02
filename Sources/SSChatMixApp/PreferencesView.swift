import SwiftUI
import SSChatMixCore

struct PreferencesView: View {
    @StateObject private var viewModel = PreferencesViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading) {
                    Text("SSChatMix")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("ChatMix Controller for macOS")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            
            Divider()
            
            // Configuration status
            GroupBox(label: Label("Status", systemImage: "info.circle")) {
                VStack(alignment: .leading, spacing: 12) {
                    if viewModel.isConfigured {
                        HStack {
                            Text("Configuration:")
                            Spacer()
                            Text("✅ Complete")
                                .foregroundColor(.green)
                        }
                        
                        if let config = viewModel.config {
                            HStack {
                                Text("Game Device:")
                                Spacer()
                                Text(config.audioDevices.game.name)
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text("Chat Device:")
                                Spacer()
                                Text(config.audioDevices.chat.name)
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text("HID Device:")
                                Spacer()
                                Text("\(config.hidDevice.vendorId):\(config.hidDevice.productId)")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack {
                            Text("Controller:")
                            Spacer()
                            Text(viewModel.isRunning ? "✅ Running" : "⚠️ Stopped")
                                .foregroundColor(viewModel.isRunning ? .green : .orange)
                        }
                    } else {
                        HStack {
                            Text("Configuration:")
                            Spacer()
                            Text("⚠️ Not configured")
                                .foregroundColor(.orange)
                        }
                        
                        Text("Run the setup wizard from the menu bar or use the button below.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            
            // Actions
            GroupBox(label: Label("Actions", systemImage: "gearshape")) {
                VStack(spacing: 12) {
                    if viewModel.isConfigured {
                        Button(action: viewModel.restartController) {
                            Label("Restart Controller", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        
                        Button(action: viewModel.openDeviceSelection) {
                            Label("Change Devices", systemImage: "speaker.wave.2")
                                .frame(maxWidth: .infinity)
                        }
                        
                        Button(action: viewModel.openStatus) {
                            Label("View Status", systemImage: "list.bullet")
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        Button(action: viewModel.runSetup) {
                            Label("Run Setup Wizard", systemImage: "wand.and.stars")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    
                    if viewModel.isConfigured {
                        Divider()
                        
                        Button(action: viewModel.reset) {
                            Label("Reset Configuration", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .foregroundColor(.red)
                    }
                }
                .padding()
            }
            
            Spacer()
            
            // Footer
            VStack(spacing: 4) {
                Text("SSChatMix v1.0.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Link("View on GitHub", destination: URL(string: "https://github.com/k0nker/ss_chatmix_macOS")!)
                    .font(.caption)
            }
            .padding(.bottom)
        }
        .frame(width: 500, height: 600)
        .padding()
        .onAppear {
            viewModel.refresh()
        }
    }
}

class PreferencesViewModel: ObservableObject {
    @Published var isConfigured = false
    @Published var isRunning = false
    @Published var config: Config?
    
    private let configManager = ConfigManager()
    private let processManager = ProcessManager()
    
    func refresh() {
        isConfigured = configManager.exists()
        isRunning = processManager.isAlreadyRunning()
        
        if isConfigured {
            config = try? configManager.load()
        }
    }
    
    func restartController() {
        try? processManager.killRunningProcess()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            let runCommand = RunCommand()
            DispatchQueue.global(qos: .userInitiated).async {
                try? runCommand.execute()
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.refresh()
            }
        }
    }
    
    func openDeviceSelection() {
        openTerminalCommand("sschatmix --device")
    }
    
    func openStatus() {
        openTerminalCommand("sschatmix --status")
    }
    
    func runSetup() {
        openTerminalCommand("sschatmix --setup")
    }
    
    func reset() {
        let alert = NSAlert()
        alert.messageText = "Reset Configuration"
        alert.informativeText = "This will remove all settings and stop the controller. Are you sure?"
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        if alert.runModal() == .alertFirstButtonReturn {
            openTerminalCommand("sschatmix --reset")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.refresh()
            }
        }
    }
    
    private func openTerminalCommand(_ command: String) {
        let script = "tell application \"Terminal\" to do script \"\(command)\""
        if let scriptObject = NSAppleScript(source: script) {
            var error: NSDictionary?
            scriptObject.executeAndReturnError(&error)
        }
    }
}

#Preview {
    PreferencesView()
}
