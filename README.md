# SSChatMix macOS

Native macOS app for SteelSeries Arctis Nova ChatMix dial.

SteelSeries SONAR doesn't work on macOS, which means the ChatMix dial on newer Arctis Nova headsets is useless outside of Windows. This app fixes that.

![macOS Menu Bar App](https://img.shields.io/badge/Platform-macOS%2015.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## How It Works

### Using SSChatMix Native Devices (Recommended - Built-in!)

SSChatMix now includes **built-in virtual audio devices** (no BlackHole required!):
1. **SSChatMix Game** - Route game audio here
2. **SSChatMix Chat** - Route chat/voice apps here
3. The HAL plugin handles audio routing to your output device
4. Select them in Settings and you're ready!

**Benefits:**
- ✅ **No microphone permissions required!**
- ✅ **No audio cutouts from Teams/etc**
- ✅ **Plugin-level audio routing** (system-level, not app-level)

### Using BlackHole (Legacy Method)

1. **Two virtual audio devices** - You need two separate virtual outputs (like BlackHole 2ch and BlackHole 16ch)
2. **Route your audio** - Direct game audio to one virtual device, chat/voice apps to the other
3. **Real-time mixing** - The app reads from both virtual devices, applies your dial position, mixes them together, and outputs to your headphones
4. **Turn the dial** - Game/chat balance adjusts in real-time

**Performance:** < 0.5% CPU, zero-latency audio mixing with CoreAudio

### Recommended: BlackHole Virtual Audio Driver (Optional)

**NEW**: SSChatMix now includes built-in virtual devices! BlackHole is optional if you prefer to use it instead.

Install [BlackHole](https://github.com/ExistentialAudio/BlackHole) for additional virtual audio devices:

```bash
brew install blackhole-2ch blackhole-16ch
```

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
- Two virtual audio devices ([BlackHole](https://github.com/ExistentialAudio/BlackHole) recommended)

## Installation

### Download Release

1. Download the latest `SSChatMix-X.X.X.dmg` from [Releases](https://github.com/k0nker/ss_chatmix_macOS/releases)
2. Open the DMG
3. Drag **SSChatMix** to the **Applications** folder
4. **Install the HAL Plugin** (for SSChatMix virtual devices):
   ```bash
   sudo cp -R SSChatMixPlugin.driver /Library/Audio/Plug-Ins/HAL/
   sudo killall coreaudiod
   ```
5. Verify devices are installed:
   ```bash
   system_profiler SPAudioDataType | grep SSChatMix
   ```
   You should see "SSChatMix Game" and "SSChatMix Chat"
6. Launch SSChatMix from Applications

On first launch, you may need to allow the app in **System Settings > Privacy & Security**.

### Install BlackHole (if you haven't already)

```bash
brew install blackhole-2ch blackhole-16ch
```

## Usage

### Initial Setup

1. **Launch SSChatMix** from Applications
2. **Click the menu bar icon** (🎧) and select **Settings...**
3. **Configure devices:**
   - **ChatMix Dial**: Select your SteelSeries device
   - **Game Audio**: Select "SSChatMix Game" (or BlackHole 16ch if using BlackHole)
   - **Chat Audio**: Select "SSChatMix Chat" (or BlackHole 2ch if using BlackHole)
   - **Output**: Select your physical headphones/speakers
4. **Click "Start"** (or the controller starts automatically)

### Route Your Applications

- Set **game apps** to output to **SSChatMix Game** (or your Game Audio device)
- Set **chat apps** (Discord, Zoom, etc.) to output to **SSChatMix Chat** (or your Chat Audio device)
- Optional: Set one of the virtual channels as the default sound output to have all audio route to that channel.
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

**Current Status**: Loopback devices implemented, Swift app routing in progress.

- **HAL Audio Plugin** - Virtual devices with loopback architecture (Background Music pattern)
  - Each device has **input stream** + **output stream**
  - Apps write to output → Stored in ring buffer
  - User-space app reads from input → Fetches from ring buffer
  - ✅ Plugin complete and working (tested)
  
- **Menu bar app** - SwiftUI interface with NSStatusItem
  - Background HID thread for ChatMix dial input
  - Volume control via HID dial
  - ⚠️ TODO: Audio routing implementation (read from loopback devices, mix, output to physical device)
  
- **Sparkle auto-updates** - EdDSA signed releases for security

### How It Works (Target Architecture)

1. **Apps output to SSChatMix virtual devices** (Game or Chat) → Writes to output stream
2. **HAL plugin stores audio in ring buffers** (loopback pattern, no deadlock)
3. **Swift app reads from virtual device input streams** (loopback from ring buffers)
4. **Swift app applies volume control** (from ChatMix dial position)
5. **Swift app mixes Game + Chat audio** (with volume scaling)
6. **Swift app writes to user-selected physical output device** (headphones/speakers)
7. **No microphone permissions needed** - plugin provides loopback, not capture

**Current Implementation**: Steps 1-2 complete (plugin loopback working). Steps 3-6 need Swift implementation.

### HID Device Reading

- Vendor ID: 0x1038 (SteelSeries)
- Usage Page: 0xFF00 (ChatMix interface)
- Report format: `[0x45, game_volume, chat_volume]`
- Background thread prevents UI operations from blocking dial input

### Volume Control

- Dial position mapped to 0-100 volume range
- Volume set directly on SSChatMix virtual devices via CoreAudio API
- HAL plugin reads volume controls and applies during mixing
- 50ms debouncing prevents dial jitter

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
- If using SSChatMix devices: ensure plugin is installed and devices are visible
- If using BlackHole: verify it's installed with `brew list blackhole-2ch blackhole-16ch`
- Check that apps are outputting to the virtual devices (Game/Chat Audio)
- Ensure the Output device is selected correctly in Settings

### Crackling audio
- Close and reopen the Settings window
- The app uses throttled updates and background threading to prevent audio issues
- If crackling persists, try restarting the app

### App won't start
- Allow the app if it's blocked in **System Settings > Privacy & Security**
- Try moving the app to Applications and launching from there
- Check Console.app for SSChatMix logs if issues persist

### Updates not working
- Check Settings > Updates > "Automatically check for updates" is enabled
- Manually check with **Check for Updates...** from the menu
- Ensure you have an internet connection

## License

MIT

