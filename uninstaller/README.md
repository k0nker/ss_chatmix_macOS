# Uninstaller

SSChatMix includes an uninstaller binary at:
```
/Applications/SSChatMix.app/Contents/Resources/uninstall
```

## Usage

**Uninstall everything (app + plugin):**
```bash
sudo /Applications/SSChatMix.app/Contents/Resources/uninstall
```

**Uninstall plugin only:**
```bash
sudo /Applications/SSChatMix.app/Contents/Resources/uninstall --plugin
```

The uninstaller will:
1. Remove the HAL plugin from `/Library/Audio/Plug-Ins/HAL/`
2. Remove the app from `/Applications/` (unless `--plugin` is specified)
3. Restart audio services: `coreaudiod`, `audioaccessoryd`, `audiomxd`, `AirPlayXPCHelper`

## Build

The uninstaller binary is compiled **before the Xcode build** and included as a resource file:

### Build Integration

The `build_and_notarize.sh` script:
1. Compiles `main.swift` → `SSChatMixApp/uninstall` (before `xcodebuild`)
2. Xcode copies it to `SSChatMix.app/Contents/Resources/` during the build (as a resource file)
3. Cleans up `SSChatMixApp/uninstall` after export

This approach avoids:
- ❌ Xcode sandbox violations (can't write to build directory during archive)
- ❌ Code signature invalidation (adding files after signing breaks signatures)

### Manual Build

For standalone testing:
```bash
./uninstaller/build.sh
# or
swiftc -O -o uninstaller/uninstall uninstaller/main.swift
```

**Note**: The compiled `SSChatMixApp/uninstall` is gitignored since it's regenerated on each build.
