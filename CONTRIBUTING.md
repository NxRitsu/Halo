# Contributing to Halo

Thanks for your interest! Bug reports, ideas and pull requests are welcome.

## Getting started

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
2. Run `xcodegen generate` at the repository root, then open `Halo.xcodeproj`.
3. Optional: copy `Local.xcconfig.example` to `Local.xcconfig` to sign with your own team.

Never commit `Halo.xcodeproj`: edit `project.yml` instead.

## Guidelines

- **Native and light.** Swift 6, SwiftUI, AppKit where needed. Avoid dependencies unless clearly justified.
- **Event-driven.** Use system notifications, IOKit/CoreAudio callbacks and KVO, never polling.
  Timers are only allowed while an animation or playback is visible.
- **No telemetry.** Do not add network requests beyond the ones listed in the README's Privacy section.
- **Graceful degradation.** Features based on private APIs must disable themselves cleanly when unavailable.
- **Localization.** All user-facing strings go through `Localizable.xcstrings` (English and French).
- **English** for code, comments, commit messages and technical documentation.
- **Licenses.** Only MIT-compatible third-party code, credited in `THIRD_PARTY_NOTICES.md`. No GPL code.

## Pull requests

- Keep pull requests focused, and describe what you changed and how you tested it.
- Make sure the project builds without warnings.
- Add an entry to the `Unreleased` section of `CHANGELOG.md`.

## Releasing (maintainers)

1. In `CHANGELOG.md`, rename `Unreleased` to the new version with its date, and add an empty
   `Unreleased` section above it.
2. Commit, then push a tag: `git tag v1.2.3 && git push origin main v1.2.3`.

The `Release` workflow builds the app, attaches the `.dmg`, the `.zip` and the `appcast.xml` to a new
GitHub release, and takes the notes from the changelog. Existing installations find the update
through the appcast of the latest release. Its secrets are listed at the top of
`.github/workflows/release.yml`. Running the workflow by hand is a dry run that publishes nothing.

To build locally: `brew install xcodegen create-dmg`, then `scripts/build-release.sh 1.2.3`.

The private key that signs updates only exists in the maintainer's keychain and in a GitHub secret.
If it's lost, existing installations can no longer be updated automatically.
