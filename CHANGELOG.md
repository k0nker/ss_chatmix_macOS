# SSChatMix Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
### Changed
### Fixed
### Removed

## [1.0.2] - 2026-08-03

### Added
- Real-time ChatMix dial monitoring
- Live volume visualization in Settings window
- Automatic updates via Sparkle
- Native macOS menu bar app
- Settings window with device configuration
- Auto-update toggle in Settings (default: enabled)
- GitHub repository link in About dialog
- Background HID thread prevents UI blocking

### Fixed
- Audio crackling when opening Settings/About dialogs
- Threading architecture to prevent main thread blocking
- UI update throttling (250ms) to reduce audio thread starvation

## [1.0.0] - YYYY-MM-DD

### Added
- Initial release
- Real-time audio monitoring and mixing
- SteelSeries ChatMix dial integration
- Dual virtual audio device support (Game/Chat)
- Configurable output device selection
- Volume control via dial rotation
- Settings interface

### Requirements
- macOS 13.0 or later
- SteelSeries ChatMix compatible dial
- Two virtual audio devices (Game and Chat channels)

---

## Version Format

We use [Semantic Versioning](https://semver.org/):
- **Major.Minor.Patch** (e.g., 1.2.3)
- **Major**: Breaking changes
- **Minor**: New features (backward compatible)
- **Patch**: Bug fixes

## Categories

- **Added**: New features
- **Changed**: Changes to existing functionality
- **Deprecated**: Soon-to-be removed features
- **Removed**: Removed features
- **Fixed**: Bug fixes
- **Security**: Security improvements
