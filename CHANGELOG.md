# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-11-02

### Added

- Alerts when Bluetooth audio devices connect or disconnect, with the model icon, the battery of
  each earbud and of the case, and the volume.
- Devices settings: connected audio devices and, on AirPods that support it, the listening mode
  (experimental).
- Bluetooth status in the Diagnostics tab and its report.

### Changed

- Releases are signed with a stable self-signed certificate, so permissions survive updates.
  Updating from 0.1.0 asks for the Accessibility permission one last time.
- The island asks again for the Accessibility permission when a new version has lost it, instead of
  silently covering the menus, and the settings can reopen Halo once it is granted.

## [0.1.0] - 2026-11-02

### Added

- Project scaffolding: XcodeGen project, CI, license and documentation.
- Island window aligned with the notch, with a virtual island on displays without one.
- Expansion on hover (adjustable delay) or click, with spring animations.
- Option to show the island on the built-in display, the main display or all displays.
- Island hidden while an app is in full screen (optional).
- Settings window (General, Island), menu bar icon (optional) and launch at login.
- English and French localization.
- Now Playing: artwork and equalizer around the notch, expanded player with seekable progress
  bar and playback controls. Works with any app reporting to the system (Music, Spotify, browsers…).
- Synced lyrics from LRCLIB in the expanded player, cached on disk, with a Lyrics settings tab.
- Battery alerts when the power adapter is connected or disconnected and when the charge is low
  (adjustable thresholds), and a low battery indicator on the compact island, with a Devices
  settings tab.
- macOS 27 (Golden Gate) support, with a CI build against the macOS 27 SDK.
- Option to show the playback artwork and equalizer around the notch always, never, or only when
  they wouldn't cover menu bar items (this last mode needs the Accessibility permission).
- On macOS 27, Halo's controls are disabled when macOS would send them to another app than the
  one on screen, such as a paused video. They come back when that app closes or when playback is
  resumed in the app on screen. Music and Spotify keep working through AppleScript.
- App icon.
- Software updates with Sparkle, with an option in the General settings. Debug builds don't update
  themselves.
- Diagnostics settings tab: live CPU and memory usage, measured only while the tab is open, the
  state of each service, and a report to copy into bug reports. It contains no personal data and
  is never sent anywhere.
- Release workflow: a version tag publishes a `.dmg`, a `.zip` and an update feed on GitHub. Builds
  are signed ad hoc, and Developer ID signing with notarization turns on when its secrets exist.
