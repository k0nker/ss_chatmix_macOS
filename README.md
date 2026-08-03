# SSChatMix macOS

Native macOS app for SteelSeries Arctis Nova ChatMix dial.

SteelSeries SONAR doesn't work on macOS, which means the ChatMix dial on newer Arctis Nova headsets is useless outside of Windows. This app fixes that.

![macOS Menu Bar App](https://img.shields.io/badge/Platform-macOS%2013.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## How It Works

1. **Two virtual audio devices** - You need two separate virtual outputs (like BlackHole 2ch and BlackHole 16ch)
2. **Route your audio** - Direct game audio to one virtual device, chat/voice apps to the other
3. **Real-time mixing** - The app reads from both virtual devices, applies your dial position, mixes them together, and outputs to your headphones
4. **Turn the dial** - Game/chat balance adjusts in real-time

**Performance:** < 0.5% CPU, zero-latency audio mixing with CoreAudio

### Recommended: BlackHole Virtual Audio Driver

Install [BlackHole](https://github.com/ExistentialAudio/BlackHole) for virtual audio devices:

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

- macOS 13.0+
- SteelSeries Arctis Nova with ChatMix dial (Nova 7, Nova Pro, etc.)
- Two virtual audio devices ([BlackHole](https://github.com/ExistentialAudio/BlackHole) recommended)

## Installation

### Download Release

1. Download the latest `SSChatMix-X.X.X.dmg` from [Releases](https://github.com/k0nker/ss_chatmix_macOS/releases)
2. Open the DMG
3. Drag **SSChatMix** to the **Applications** folder
4. Launch from Applications

On first launch, you may need to allow the app in **System Settings > Privacy & Security**.

### Install BlackHole (if you haven't already)

```bash
brew install blackhole-2ch blackhole-16ch
```

## Usage

### Initial Setup

1. **Launch SSChatMix** from Applications
2. **Grant microphone permission** when prompted (required to capture audio from virtual devices)
3. **Click the menu bar icon** (🎧) and select **Settings...**
4. **Configure devices:**
   - **ChatMix Dial**: Select your SteelSeries device
   - **Game Audio**: Select first virtual device (e.g., BlackHole 16ch)
   - **Chat Audio**: Select second virtual device (e.g., BlackHole 2ch)
   - **Output**: Select your physical headphones/speakers
5. **Click "Start"** (or the controller starts automatically)

### Route Your Applications

- Set **game apps** to output to your Game Audio device (e.g., BlackHole 16ch)
- Set **chat apps** (Discord, Zoom, etc.) to output to your Chat Audio device (e.g., BlackHole 2ch)
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

- **Menu bar app** - SwiftUI interface with NSStatusItem
- **Background HID thread** - Dedicated thread for ChatMix dial input, isolated from UI
- **Real-time audio mixing** - CoreAudio Audio Units for zero-latency processing
- **Sparkle auto-updates** - EdDSA signed releases for security

### HID Device Reading

- Vendor ID: 0x1038 (SteelSeries)
- Usage Page: 0xFF00 (ChatMix interface)
- Report format: `[0x45, game_volume, chat_volume]`
- Background thread prevents UI operations from blocking dial input

### Audio Processing

- Reads from two virtual input devices simultaneously
- Applies independent volume control (0.0-1.0 scale)
- Mixes streams in real-time with CoreAudio Audio Units
- Outputs combined audio to physical device
- 50ms debouncing prevents dial jitter

## Troubleshooting

### ChatMix device not detected
- Ensure the headset is turned on and connected
- Try unplugging and reconnecting the USB transmitter
- Check the device list in Settings

### Volume not changing
- Verify apps are outputting to the correct virtual devices
- Check Settings window to see if live volume bars are moving
- Try restarting the controller from the menu

### No audio output
- Verify BlackHole is installed: `brew list blackhole-2ch blackhole-16ch`
- Check that apps are outputting to the virtual devices (Game/Chat Audio)
- Ensure the Output device is selected correctly in Settings

### Crackling audio
- Close and reopen the Settings window
- The app uses throttled updates and background threading to prevent audio issues
- If crackling persists, try restarting the app

### App won't start
- Check **System Settings > Privacy & Security > Microphone** - SSChatMix needs permission
- Allow the app if it's blocked in Privacy & Security
- Try moving the app to Applications and launching from there

### Updates not working
- Check Settings > Updates > "Automatically check for updates" is enabled
- Manually check with **Check for Updates...** from the menu
- Ensure you have an internet connection

## License

MIT

