# Halo

**A Dynamic Island for your Mac's notch.** Halo turns the area around the MacBook notch into a
living, glanceable island: what's playing, synced lyrics, battery and AirPods alerts, weather,
a file tray and more. On Macs without a notch, or on external displays, Halo draws a virtual
island at the top of the screen.

Halo is free, open source (MIT) and lightweight: native Swift/SwiftUI, event-driven, ~0% CPU at rest.

> 🇫🇷 **En bref :** Halo transforme la zone de l'encoche du MacBook en « île dynamique » :
> lecture en cours, paroles synchronisées, alertes batterie et AirPods, météo, bac à fichiers…
> Sur les Mac sans encoche et les écrans externes, une île virtuelle s'affiche en haut de l'écran.
> Gratuit, open source, natif et léger. Interface en anglais et en français.

_Screenshots coming soon._

## Features

| Status | Feature |
| --- | --- |
| ✅ | Island aligned with the notch, expands on hover or click, virtual island on other displays |
| ✅ | Now Playing (Apple Music, Spotify, Deezer, browsers…) with playback controls |
| ✅ | Synced lyrics, cached on your Mac |
| ✅ | Battery and charging alerts |
| 🚧 | AirPods and Bluetooth audio alerts with battery levels |
| 🚧 | Weather |
| 🚧 | File tray (drag and drop, Quick Look, AirDrop) |
| 🚧 | Audio output picker |

## Requirements

- macOS 26 (Tahoe) or later, including macOS 27 (Golden Gate)
- Apple Silicon Mac (a notch is optional)

## Installation

Download the latest `.dmg` from the [Releases](https://github.com/NxRitsu/Halo/releases) page and
drag Halo to your Applications folder.

Halo is free and open source, and its builds aren't notarized by Apple for now. The first time you
open it, macOS refuses to launch it:

1. Try to open Halo once, then dismiss the warning.
2. Open **System Settings → Privacy & Security**.
3. Scroll down and click **Open Anyway** next to the message about Halo, then confirm.

Halo has no Dock icon. Right-click the island or use the menu bar icon to open its settings.

### Updates

Halo can update itself: on the second launch it asks whether to check for updates automatically,
and you can change this or check by hand in **Settings → General**. Updates are verified with a
signature before they are installed.

Without notarization, macOS sees each update as a new app, so permissions such as Accessibility may
have to be granted again afterwards. If the option no longer works, remove Halo from the list in
**System Settings → Privacy & Security → Accessibility** and add it back.

## Privacy

Halo has **no analytics, no telemetry and no account**. Only three kinds of network requests ever
leave your Mac, and all of them can be disabled:

| Request | Data sent | Why |
| --- | --- | --- |
| Lyrics ([LRCLIB](https://lrclib.net)) | Track title, artist, album, duration | To fetch synced lyrics |
| Weather ([Open-Meteo](https://open-meteo.com)) | Approximate location (reduced accuracy) | To show the current weather |
| Updates ([GitHub](https://github.com/NxRitsu/Halo/releases)) | Nothing but the request itself, which reveals your IP address to GitHub, like any download | To find and download new versions |

Everything else (media info, battery, Bluetooth, files) stays on your Mac.

Halo only asks for the Accessibility permission if you choose to show playback around the notch
"when there's room". It then reads the position of menu bar items, not their titles or anything
else, so the island doesn't cover them.

## Building from source

```sh
brew install xcodegen
git clone https://github.com/NxRitsu/Halo.git
cd Halo
xcodegen generate
open Halo.xcodeproj        # or: xcodebuild -scheme Halo -configuration Debug build
```

The `.xcodeproj` is generated from `project.yml` and is not committed. By default the app is signed
ad hoc. To sign with your own identity, copy `Local.xcconfig.example` to `Local.xcconfig` and set
your team ID. Debug builds don't update themselves.

## FAQ

**Does Halo work without a notch?**
Yes. Halo shows a virtual island centered at the top of the screen, and you can choose to show it
on every display.

**Why does Halo use private Apple APIs?**
Some features (such as reading what's playing system-wide) have no public API. Each of these
features turns itself off cleanly, with an explanation in Settings, if the API is unavailable on
your macOS version.

**How much CPU does it use?**
Halo is event-driven: it reacts to system notifications instead of polling. At rest it should sit
at ~0% CPU.

**How do I report a bug?**
Open an issue and paste the report from **Settings → Diagnostics → Copy report**.

## Credits

- Lyrics provided by [LRCLIB](https://lrclib.net).
- Weather data by [Open-Meteo](https://open-meteo.com) (CC BY 4.0).
- Updates powered by [Sparkle](https://sparkle-project.org).

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for details.

## License

[MIT](LICENSE)
