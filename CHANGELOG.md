# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- Release workflow: a version tag publishes a `.dmg`, a `.zip` and an update feed on GitHub. Builds
  are signed ad hoc, and Developer ID signing with notarization turns on when its secrets exist.
