# SSChatMix Installer

## Installation

Double-click `SSChatMixPlugin-1.0.0.pkg` or run from Terminal:

```bash
sudo installer -pkg SSChatMixPlugin-1.0.0.pkg -target /
```

The installer will:
1. Install SSChatMixPlugin.driver to `/Library/Audio/Plug-Ins/HAL/`
2. Set correct ownership (root:wheel) and permissions (755)
3. Clean up macOS metadata files
4. Restart CoreAudio daemon to load the plugin
5. Verify SSChatMix virtual devices appear in the system

## Verification

After installation, check that the virtual devices are available:

```bash
system_profiler SPAudioDataType | grep SSChatMix
```

You should see:
- SSChatMix Game
- SSChatMix Chat

## Installation Log

The installer writes detailed logs to `/tmp/sschatmix-install.log`

## Troubleshooting

If devices don't appear after installation:

1. Check the installation log:
   ```bash
   cat /tmp/sschatmix-install.log
   ```

2. Manually restart CoreAudio:
   ```bash
   sudo killall coreaudiod
   ```

3. Verify plugin ownership:
   ```bash
   ls -l /Library/Audio/Plug-Ins/HAL/SSChatMixPlugin.driver
   ```
   
   Should show: `drwxr-xr-x ... root  wheel ... SSChatMixPlugin.driver`

## Uninstallation

To remove the plugin:

```bash
sudo rm -rf /Library/Audio/Plug-Ins/HAL/SSChatMixPlugin.driver
sudo killall coreaudiod
```

## Building from Source

To rebuild the installer package:

```bash
cd /path/to/ss_chatmix_macOS
./build_plugin_installer.sh
```

The new package will be created in `installer/output/`
