# Quick Start: Menu Bar App

## For Developers

### Open in Xcode

```bash
# From the project directory
open Package.swift
```

In Xcode:
1. Select **SSChatMixApp** scheme (next to Run button)
2. Press `Cmd+R` to build and run
3. Look for the slider icon (🎚️) in your menu bar

### Build from Command Line

```bash
# Build the app
swift build --product SSChatMixApp

# Run it
.build/debug/SSChatMixApp
```

## For End Users

### Prerequisites

1. **Install BlackHole:**
   ```bash
   brew install blackhole-2ch blackhole-16ch
   ```

2. **Install the CLI tool** (needed for setup):
   ```bash
   # Build and install
   swift build -c release --product sschatmix
   sudo cp .build/release/sschatmix /usr/local/bin/
   ```

### First Time Setup

1. **Launch the menu bar app:**
   ```bash
   .build/debug/SSChatMixApp
   ```

2. **Click the menu bar icon** (slider symbol)

3. **Select "Setup..."**
   - This opens Terminal
   - Follow the setup wizard
   - Select your devices
   - Controller starts automatically

4. **The menu bar icon shows:**
   - ✅ Running / ⚠️ Stopped
   - Current game and chat volumes
   - Quick access to all features

### Build for Distribution

1. **Open in Xcode:**
   ```bash
   open Package.swift
   ```

2. **Select SSChatMixApp scheme**

3. **Product → Archive**

4. **Distribute:**
   - For yourself: Choose "Copy App"
   - For others: Sign with Developer ID and notarize

## Current Limitations

The menu bar app currently launches Terminal for:
- Initial setup (`--setup`)
- Device selection (`--device`)
- Configuration reset (`--reset`)

This is because these operations require interactive text input. A future version may add native SwiftUI dialogs for these.

## Features

✅ **Menu bar presence** - Always visible status  
✅ **Real-time monitoring** - See current mix levels  
✅ **Quick restart** - Fix disconnections instantly  
✅ **Preferences** - Native settings window  
✅ **No Dock icon** - Stays in menu bar only  
✅ **Shares config** - Uses same settings as CLI  

## Troubleshooting

**App doesn't appear:**
- Check Activity Monitor for "SSChatMixApp"
- Look in ALL menu bar areas (it might be hidden)
- Try building in release mode: `swift build -c release --product SSChatMixApp`

**Can't open in Xcode:**
- Make sure Xcode Command Line Tools are installed:
  ```bash
  xcode-select --install
  ```

**"No such module SSChatMixCore":**
- Clean build folder: `swift package clean`
- Rebuild: `swift build`

## Next Steps

See [README_MACAPP.md](README_MACAPP.md) for:
- Full Xcode setup guide
- Code signing instructions
- Notarization process
- Distribution via GitHub releases
