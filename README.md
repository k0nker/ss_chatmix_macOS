# SSChatMix macOS

Native macOS app for SteelSeries Arctis Nova ChatMix dial.

SteelSeries SONAR doesn't work on macOS, which means the ChatMix dial on newer Arctis Nova headsets is useless outside of Windows. This app fixes that.

![macOS Menu Bar App](https://img.shields.io/badge/Platform-macOS%2015.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## How It Works

SSChatMix includes **built-in virtual audio devices** - no third-party tools required!

1. **SSChatMix Game** and **SSChatMix Chat** - Two virtual output devices created by the HAL plugin
2. **Route your audio** - Direct game audio to SSChatMix Game, chat/voice apps to SSChatMix Chat
3. **Shared memory transfer** - Plugin writes audio data to POSIX shared memory (~170ms ring buffers)
4. **Hardware-accelerated mixing** - App uses vDSP (Accelerate framework) to mix and scale audio
5. **Turn the dial** - Game/chat balance adjusts in real-time with ultra-low latency

**Benefits:**
- ✅ **No microphone permissions required!**
- ✅ **Shared memory architecture** (no audio capture API)
- ✅ **Low latency** (~42ms IO period, ~170ms max buffer)
- ✅ **Zero CPU mixing** with hardware acceleration
- ⚠️  **Note:** Audio may stutter when apps that require microphone access are opened (macOS CoreAudio limitation)

**Performance:** < 0.5% CPU, hardware-accelerated audio mixing

## Features

✅ **Native macOS app** - menu bar interface, no terminal required  
✅ **Auto-updates** - Sparkle framework keeps you up to date  
✅ **Settings window** - easy device selection and configuration  
✅ **Launch at login** - optional auto-start  
✅ **Real-time audio mixing** - CoreAudio Audio Units for ultra-low latency  
✅ **Background thread HID** - dial input never blocks, even with open dialogs  
✅ **Visual feedback** - live volume bars in Settings window

## Requirements

- macOS 15.0+
- SteelSeries Arctis Nova with ChatMix dial (Nova 7, Nova Pro, etc.)

## Installation

### Download Release

1. Download the latest release from [Releases](https://github.com/k0nker/ss_chatmix_macOS/releases)
2. **Install the HAL Plugin first:**
   - Open `SSChatMixPlugin-X.X.pkg` and follow the installer
   - This creates the SSChatMix Game and SSChatMix Chat virtual devices
3. **Install the app:**
   - Open `SSChatMix-X.X.dmg`
   - Drag **SSChatMix** to the **Applications** folder
4. **Verify installation:**
   ```bash
   system_profiler SPAudioDataType | grep SSChatMix
   ```
   You should see "SSChatMix Game" and "SSChatMix Chat"
5. Launch SSChatMix from Applications

On first launch, you may need to allow the app in **System Settings > Privacy & Security**.

💡 **Important:** Always install the plugin package before the app to ensure version compatibility.

## Usage

### Initial Setup

1. **Launch SSChatMix** from Applications
2. **Click the menu bar icon** (🎧) and select **Settings...**
3. **Configure devices:**
   - **ChatMix Dial**: Select your SteelSeries device
   - **Game Audio**: Select "SSChatMix Game"
   - **Chat Audio**: Select "SSChatMix Chat"
   - **Output**: Select your physical headphones/speakers
4. **Click "Start"** (or the controller starts automatically)

### Route Your Applications

- Set **game apps** to output to **SSChatMix Game**
- Set **chat apps** (Discord, Zoom, etc.) to output to **SSChatMix Chat**
- Optional: Set one of the virtual devices as the default sound output to have all audio route to that channel
- **Turn the dial** - volumes adjust in real-time!

💡 **Tip:** Use macOS Audio MIDI Setup or per-app audio settings to route audio to virtual devices.

### Menu Bar Controls

Click the menu bar icon (🎧) to:
- **Settings...** - Configure devices and view live mix levels
- **Start/Stop** - Control the audio mixer
- **Check for Updates...** - Manually check for new versions
- **About** - View app info and visit GitHub
- **Quit** - Exit the app

### Settings Window

The Settings window shows:
- **Device selection** - Change devices without restarting
- **Live volume bars** - See game/chat mix in real-time as you turn the dial
- **Launch at login** - Auto-start when you log in
- **Auto-updates** - Automatically check for new versions (default: enabled)

## Technical Details

### Architecture

- **HAL Audio Plugin (C++)** - CoreAudio driver creating virtual output devices
  - Two devices: **SSChatMix Game** and **SSChatMix Chat**
  - Each device writes incoming audio to POSIX shared memory (`/ssc.game`, `/ssc.chat`)
  - Ring buffer: 8192 frames (~170ms capacity at 48kHz)
  - IO period: 2048 frames (~42ms latency)
  - Bundle ID: `com.k0nker.SSChatMixPlugin`
  - Location: `/Library/Audio/Plug-Ins/HAL/SSChatMixPlugin.driver`
  
- **Menu bar app (Swift)** - SwiftUI interface with NSStatusItem
  - Reads audio from shared memory ring buffers
  - Hardware-accelerated mixing with vDSP (Accelerate framework)
  - Background HID thread for ChatMix dial input
  - Volume control mapped from dial position (0-100 range)
  - Sparkle auto-updates with EdDSA signed releases
  
### Shared Memory Architecture

1. **Apps output to SSChatMix virtual devices** → CoreAudio routes to HAL plugin
2. **HAL plugin writes to shared memory** → POSIX `shm_open()` with atomic ring buffers
3. **Swift app reads from shared memory** → Lock-free atomic read/write positions
4. **vDSP hardware mixing** → `vDSP_vsmul`, `vDSP_vsma`, `vDSP_vclip` for zero-CPU mixing
5. **Output to physical device** → Scaled, mixed, clipped audio to headphones/speakers

**Benefits:**
- No microphone permissions (not using audio capture API)
- No loopback deadlocks (shared memory is unidirectional)
- Ultra-low CPU usage (hardware acceleration)
- Works with all apps (virtual devices available system-wide)

### HID Device Reading

- Vendor ID: 0x1038 (SteelSeries)
- Usage Page: 0xFF00 (ChatMix interface)
- Report format: `[0x45, game_volume, chat_volume]`
- Background thread prevents UI operations from blocking dial input

### Volume Control

- Dial position mapped to 0-100 volume range
- Live volume visualization in Settings window
- Hardware mixing applies volume scaling with vDSP
- Volume persists across app restarts

## Troubleshooting

### SSChatMix devices not showing up
- Verify the plugin is installed:
  ```bash
  ls -la /Library/Audio/Plug-Ins/HAL/ | grep SSChatMix
  ```
- Restart the audio service:
  ```bash
  sudo killall coreaudiod
  ```
- Check if devices registered:
  ```bash
  system_profiler SPAudioDataType | grep SSChatMix
  ```
- Open Audio MIDI Setup app to verify devices are visible

### ChatMix device not detected
- Ensure the headset is turned on and connected
- Try unplugging and reconnecting the USB transmitter
- Check the device list in Settings

### Volume not changing
- Verify apps are outputting to the correct virtual devices
- Check Settings window to see if live volume bars are moving
- Try restarting the controller from the menu

### No audio output
- Ensure the HAL plugin is installed (see Installation section)
- Verify SSChatMix devices are visible in Audio MIDI Setup
- Check that apps are outputting to the virtual devices (Game/Chat Audio)
- Ensure the Output device is selected correctly in Settings

### Crackling audio
- Close and reopen the Settings window
- The app uses throttled updates and background threading to prevent audio issues
- If crackling persists, try restarting the app

### Audio stuttering at startup or when opening certain apps
- **Expected behavior:** Audio will briefly stutter when apps requiring microphone access are opened (Teams, Zoom, Discord, etc.)
- **Cause:** macOS CoreAudio is torn down and rebuilt when microphone permissions change
- **This is a macOS limitation,** not a bug in SSChatMix
- The audio will resume normally after a few seconds
- No workaround is currently possible at the plugin level

### App won't start
- Allow the app if it's blocked in **System Settings > Privacy & Security**
- Try moving the app to Applications and launching from there
- Check Console.app for SSChatMix logs if issues persist

### Updates not working
- Check Settings > Updates > "Automatically check for updates" is enabled
- Manually check with **Check for Updates...** from the menu
- Ensure you have an internet connection

### Plugin version mismatch
- The app checks plugin version on startup
- If versions don't match, you'll see an alert with download instructions
- Always install the plugin package (.pkg) before the app (.dmg)
- Download both from the same release on GitHub

---

## Legacy - Releases Prior to 1.1

**Note:** Version 1.1 and later include built-in virtual devices. The information below applies to older releases that required BlackHole.

### Using BlackHole (Legacy Method - Pre-1.1)

Earlier versions of SSChatMix required [BlackHole](https://github.com/ExistentialAudio/BlackHole) for virtual audio devices:

1. Install BlackHole:
   ```bash
   brew install blackhole-2ch blackhole-16ch
   ```
2. Route game audio to BlackHole 16ch
3. Route chat audio to BlackHole 2ch
4. SSChatMix would capture from these devices and mix

**Why we moved away from BlackHole:**
- Required microphone permissions
- Relied on audio capture API instead of shared memory
- Additional external dependency to install and maintain
- Less control over latency and buffer sizes

If you're still using a pre-1.1 release, we recommend updating to the latest version for the improved architecture.

---

## License

MIT

