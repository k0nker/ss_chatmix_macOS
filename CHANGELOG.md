# SSChatMix Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- Custom app icon with headphones and play symbol
- Sparkle auto-update integration
- Menu bar icon with headphones + play design
- Settings window with update checking
- Reload option to refresh configuration without restarting

### Changed
- App now runs as menu bar only utility (LSUIElement)
- Improved permission flow for microphone access

### Fixed
- HAL audio overload from blocking semaphore
- Lock-free ring buffer for real-time audio processing
- Microphone permission race condition
- EdDSA signature verification with Sparkle

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
