# SSChatMix Menu Bar App (macOS)

This branch contains the menu bar app version of SSChatMix alongside the CLI tool.

## Overview

The `macapp` branch adds a native macOS menu bar application while keeping the CLI tool. Both share the same `SSChatMixCore` library.

### What's Included

- **CLI Tool** (`sschatmix`) - Original command-line interface
- **Menu Bar App** (`SSChatMixApp`) - Native SwiftUI menu bar application
- **Shared Core** (`SSChatMixCore`) - Audio and HID control logic

## Building in Xcode

### Option 1: Open Package.swift (Recommended)

1. **Open the project:**
   ```bash
   open Package.swift
   ```
   
2. **Select the SSChatMixApp scheme** in Xcode toolbar

3. **Build and run:**
   - Press `Cmd+R` to run in debug mode
   - Press `Cmd+B` to build

4. **Find the built app:**
   ```
   .build/debug/SSChatMixApp.app
   ```

### Option 2: Build with Swift Package Manager

```bash
# Build both CLI and app
swift build

# Run the menu bar app
.build/debug/SSChatMixApp

# Run the CLI
.build/debug/sschatmix --help
```

## Creating a Distributable App

### Step 1: Archive in Xcode

1. Open `Package.swift` in Xcode
2. Select **SSChatMixApp** scheme
3. Set target to **Any Mac**
4. Product → Archive
5. Organizer window will open with your archive

### Step 2: Export for Distribution

1. In Organizer, select your archive
2. Click **Distribute App**
3. Choose **Copy App** (for non-App Store distribution)
4. Select **Development** or **Developer ID** (requires Apple Developer account)
5. Export

### Step 3: Sign the App

If you have an Apple Developer account:

```bash
# Sign with Developer ID
codesign --deep --force --verify --verbose \
  --sign "Developer ID Application: Your Name" \
  --options runtime \
  --entitlements SSChatMixApp.entitlements \
  SSChatMix.app
```

### Step 4: Create DMG for Distribution

```bash
# Create a DMG
hdiutil create -volname "SSChatMix" \
  -srcfolder SSChatMix.app \
  -ov -format UDZO \
  SSChatMix.dmg

# Sign the DMG
codesign --sign "Developer ID Application: Your Name" SSChatMix.dmg
```

### Step 5: Notarize (Required for macOS 10.15+)

```bash
# Submit for notarization
xcrun notarytool submit SSChatMix.dmg \
  --keychain-profile "AC_PASSWORD" \
  --wait

# Staple the notarization ticket
xcrun stapler staple SSChatMix.dmg
```

**Note:** Notarization requires:
- Apple Developer Program membership ($99/year)
- App-specific password from Apple ID
- Stored in keychain with profile name (use `xcrun notarytool store-credentials`)

## Menu Bar App Features

### UI Elements

- **Menu Bar Icon:** 🎚️ Shows ChatMix status
- **Volume Display:** Real-time game/chat volume percentages
- **Status Indicator:** Running/stopped/not configured
- **Quick Actions:**
  - Restart controller
  - Change devices
  - View status
  - Preferences
  - Quit

### Preferences Window

- Configuration status display
- Device information
- Controller status
- Quick access to setup/device selection
- Reset configuration

## App Configuration

The menu bar app uses the same configuration as the CLI tool:
- Config location: `~/Library/Application Support/com.k0nker.sschatmix/config.json`
- PID file: `~/Library/Application Support/com.k0nker.sschatmix/sschatmix.pid`

### Initial Setup

On first launch:
1. Click the menu bar icon
2. Select "Setup..."
3. This opens Terminal and runs `sschatmix --setup`
4. Follow the setup wizard
5. The controller starts automatically

### Making it Menu Bar Only

The app is configured with `LSUIElement=true` in Info.plist, which makes it:
- Run without a Dock icon
- Not appear in Cmd+Tab app switcher
- Only visible in menu bar

To change this behavior, modify `LSUIElement` in the Info.plist.

## Info.plist Configuration

Create `Info.plist` in the app bundle with these keys:

```xml
<key>LSUIElement</key>
<true/>
<key>CFBundleIdentifier</key>
<string>com.k0nker.sschatmix</string>
<key>CFBundleName</key>
<string>SSChatMix</string>
<key>LSMinimumSystemVersion</key>
<string>13.0</string>
```

## Code Signing Requirements

For distribution outside the App Store, you need:

1. **Developer ID Application Certificate**
   - Obtained from Apple Developer Program
   - Used to sign the app

2. **App-Specific Password**
   - Generated in Apple ID account settings
   - Used for notarization

3. **Hardened Runtime**
   - Enabled via `--options runtime` flag
   - Required for notarization

## Entitlements

Create `SSChatMixApp.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.usb</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
```

These entitlements allow:
- USB HID device access (ChatMix dial)
- Audio input (for monitoring virtual devices)

## Distribution via GitHub Releases

1. **Create a release:**
   ```bash
   git tag -a v1.0.0 -m "Release version 1.0.0"
   git push origin v1.0.0
   ```

2. **Upload assets:**
   - `SSChatMix.dmg` (signed and notarized)
   - `sschatmix` (CLI binary, signed)
   - `README.md`
   - `INSTALL.md`

3. **Release notes template:**
   ```markdown
   ## What's New
   - Native menu bar app
   - Real-time volume display
   - Preferences window
   - CLI tool included
   
   ## Installation
   
   ### Menu Bar App
   1. Download `SSChatMix.dmg`
   2. Open and drag to Applications
   3. Launch from Applications or Spotlight
   
   ### CLI Tool
   1. Download `sschatmix`
   2. `chmod +x sschatmix`
   3. `mv sschatmix /usr/local/bin/`
   
   ## Requirements
   - macOS 13.0+
   - SteelSeries Arctis Nova headset
   - BlackHole virtual audio driver
   ```

## Troubleshooting

### "App is damaged and can't be opened"

This means the app isn't signed or notarized. Either:
- Sign and notarize the app properly
- Or remove quarantine: `xattr -cr SSChatMix.app`

### App won't start

- Check Console.app for error messages
- Verify BlackHole is installed
- Run `sschatmix --debug` from Terminal to check device detection

### Menu bar icon doesn't appear

- Make sure `LSUIElement` is `true` in Info.plist
- Check if app is running: `ps aux | grep SSChatMixApp`

## Development Tips

### Hot Reloading

Xcode supports hot reloading for SwiftUI:
1. Build and run in Xcode
2. Edit SwiftUI views
3. Changes appear without full rebuild

### Debugging

- Use `print()` statements (output goes to Xcode console)
- Set breakpoints in Xcode
- Use `po` command in debugger to inspect values

### Testing Without Installation

You can run the app directly from build output:
```bash
swift build
.build/debug/SSChatMixApp
```

## Comparison: CLI vs Menu Bar App

| Feature | CLI | Menu Bar App |
|---------|-----|--------------|
| Visual feedback | ❌ | ✅ Real-time display |
| Terminal required | ✅ | ❌ |
| Auto-start | Launch agent | Login item |
| Setup wizard | Interactive CLI | Opens Terminal |
| Device selection | Text menu | Opens Terminal |
| Status check | `--status` flag | Always visible |
| Distribution | Single binary | .app bundle |
| Code signing | Simple | Requires notarization |

## Future Enhancements

Potential features for the menu bar app:
- [ ] Inline device selection (no Terminal)
- [ ] Visual volume sliders
- [ ] Keyboard shortcuts
- [ ] Sparkle auto-updates
- [ ] Custom menu bar icons
- [ ] Notification center integration
- [ ] Sound output switching via menu

## Contributing

Both CLI and menu bar app share the same core library. When contributing:
- Keep `SSChatMixCore` UI-agnostic
- Test changes against both CLI and app
- Maintain backward compatibility with existing configs

## License

MIT
