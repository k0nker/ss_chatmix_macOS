# SSChatMix macOS

Native macOS controller for SteelSeries Arctis Nova ChatMix dial.

I put this together because SteelSeries does not support SONAR on macOS, which means their newer software driven ChatMix does not work outside of Windows.

## How It Works

1. **Select two virtual audio devices** - You need two separate virtual outputs (like BlackHole 2ch and BlackHole 16ch)
2. **Select physical output** - Choose your actual headphones/speakers where you want to hear the audio
3. **Real-time audio mixing** - Reads from both virtual devices, applies volume control, mixes them, and outputs to your physical device
4. **Route audio as preferred** - EITHER Direct game audio to one virtual device, chat/voice apps to the other OR Default audio set to one of your virtual outputs and then apps you want on the other channel to that virtual device.
5. **Turn the dial** - Adjusts the mix levels in real-time before combining to your headphones

**Performance:** < 0.5% CPU usage using CoreAudio Audio Units

### Recommended: BlackHole Virtual Audio Driver

I recommend [BlackHole](https://github.com/ExistentialAudio/BlackHole) for virtual audio devices. Install both:
- **BlackHole 2ch** - For one audio source (e.g., game audio)
- **BlackHole 16ch** - For another audio source (e.g., chat/Discord)

```bash
brew install blackhole-2ch blackhole-16ch
```

## Features

✅ **Single self-contained binary** - no external dependencies  
✅ **Direct HID communication** - native IOKit integration  
✅ **Real-time audio mixing** - CoreAudio Audio Units for ultra-low latency  
✅ **Dual virtual device support** - Mix two independent audio sources  
✅ **Debounced volume control** - Smooth dial tracking (50ms)  
✅ **Auto-start at login** - optional launch agent  
✅ **Single-instance enforcement** - PID file prevents duplicates  
✅ **Full CLI interface** - setup, status, device management

## Requirements

- macOS 13.0+
- SteelSeries Arctis Nova with ChatMix dial (Nova 7, Nova Pro, etc.)
- Two virtual audio devices ([BlackHole](https://github.com/ExistentialAudio/BlackHole) recommended)
- Swift 5.9+ (for building from source)

## Installation

### Build from source

```bash
# Clone the repository
cd ss_chatmix_macOS

# Build release binary
swift build -c release

# Copy binary to /usr/local/bin
cp .build/release/sschatmix /usr/local/bin/
```

## Usage

### Initial Setup

**Step 1: Install BlackHole** (if you haven't already)

```bash
brew install blackhole-2ch blackhole-16ch
```

**Step 2: Run the setup wizard**

```bash
sschatmix --setup
```

The wizard will:
1. Detect your ChatMix device and let you select it (if multiple detected)
2. Let you select the first virtual device (e.g., BlackHole 16ch for game audio)
3. Let you select the second virtual device (e.g., BlackHole 2ch for chat audio)
4. Let you select your physical output device (your actual headphones/speakers)
5. Set physical output device to 100% volume (for accurate mixing)
6. Configure auto-start at login
7. Auto-start the controller in background

**Step 3: Route your applications**

- Set **game apps** or general system output to to your first virtual device (e.g., BlackHole 16ch)
- Set **chat apps** (Discord, Zoom, etc.) output or any app you want controlled separately with ChatMix to your second virtual device (e.g., BlackHole 2ch)
- Audio is automatically mixed and routed to your physical output

💡 **Tip:** Use macOS Audio MIDI Setup or per-app audio settings to route audio to the virtual devices.

### Running

The controller starts automatically after setup and at login (if enabled).

```bash
# Check if running
sschatmix --status

# Start manually if needed
sschatmix
```

Turn the dial - volumes adjust automatically!

### CLI Commands

```bash
# Show current configuration and status
sschatmix --status

# Change audio devices
sschatmix --device

# Debug HID device detection
sschatmix --debug

# Enable/disable auto-start at login
sschatmix --login
sschatmix --login-disable

# Stop and remove all configuration
# (also resets all device volumes to 100%)
sschatmix --reset

# Show all available commands
sschatmix --help
```

💡 **Note:** Running `--reset` restores all configured device volumes (game, chat, and physical output) to 100% before cleaning up.

## Technical Details

### HID Device Reading
Uses IOKit to read USB HID reports from the ChatMix dial:
- Vendor ID: 0x1038 (SteelSeries)
- Usage Page: 0xFF00 (ChatMix interface)
- Report format: `[0x45, game_volume, chat_volume]`

### Real-Time Audio Processing
Uses CoreAudio Audio Units for zero-latency mixing:
- Reads from two virtual input devices simultaneously
- Applies independent volume control (0.0-1.0 scale)
- Mixes streams in real-time
- Outputs combined audio to physical device

### Volume Control
- Game volume: Controlled by left side of dial (0-100%)
- Chat volume: Controlled by right side of dial (0-100%)
- 50ms debouncing prevents dial jitter

## Development

```bash
# Build debug version
swift build

# Run debug version
swift run sschatmix --setup

# Run tests
swift test
```

## Project Structure

```
ss_chatmix_macOS/
├── Package.swift
├── Sources/
│   ├── sschatmix/
│   │   └── main.swift              # CLI entry point
│   └── SSChatMixCore/
│       ├── Config.swift             # Configuration models
│       ├── ConfigManager.swift      # Settings persistence
│       ├── AudioController.swift    # CoreAudio device interface
│       ├── AudioMonitor.swift       # Real-time audio mixing engine
│       ├── HIDController.swift      # IOKit HID interface
│       ├── ProcessManager.swift     # PID file management
│       ├── LaunchAgentManager.swift # Launch agent management
│       ├── SetupCommand.swift       # Interactive setup wizard
│       ├── RunCommand.swift         # Main controller loop
│       ├── StatusCommand.swift      # Status display
│       ├── DeviceCommand.swift      # Device selection
│       ├── DebugCommand.swift       # Device detection debug
│       ├── AggregateCommand.swift   # Aggregate device utilities
│       ├── LoginCommand.swift       # Launch agent control
│       └── ResetCommand.swift       # Reset configuration
└── README.md
```

## Troubleshooting

### ChatMix device not detected
- Ensure the headset is turned on and connected
- Try unplugging and reconnecting the USB transmitter
- Run `sschatmix --debug` to see detected devices

### Volume not changing
- Check device selection with `sschatmix --status`
- Ensure the virtual audio devices still exist (run `brew list | grep blackhole`)
- Verify apps are routing audio to the correct virtual devices
- Try `sschatmix --device` to reconfigure

### No audio output
- Verify BlackHole is installed: `brew list blackhole-2ch blackhole-16ch`
- Check that apps are outputting to the virtual devices
- Ensure the physical output device is selected correctly in setup

### Launch agent not working
- Check if controller is running: `ps aux | grep sschatmix`
- Verify binary exists: `which sschatmix`
- Check launch agent: `launchctl list | grep com.k0nker.sschatmix`

## License

MIT

