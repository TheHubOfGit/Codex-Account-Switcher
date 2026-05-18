# Codex Account Switcher

Codex Account Switcher is a native macOS menu bar app for monitoring and switching between locally authenticated Codex accounts. It reads the `codex-auth` account registry, summarizes quota state, and can switch accounts before relaunching the official Codex desktop app.

## Prerequisites

- macOS 13 or newer.
- Swift 6 / Xcode command line tools.
- `codex-auth` installed and available from `/opt/homebrew/bin`, `/usr/local/bin`, or your shell `PATH`.
- At least one account configured through `codex-auth login` or `codex-auth import`.

The app depends on `codex-auth` for account discovery, quota refreshes, account switching, auto-switch settings, and threshold updates. Without it, the menu bar app can launch but will report that account state is unavailable.

## Build

```bash
./scripts/build_app.sh
```

The script runs `swift build`, creates a local app bundle at `dist/Codex Account Switcher.app`, generates the app icon, and ad-hoc signs the bundle when possible.

## Build a DMG

After building the app bundle, package it into a local DMG with:

```bash
rm -rf "dist/dmg-staging"
mkdir -p "dist/dmg-staging"
cp -R "dist/Codex Account Switcher.app" "dist/dmg-staging/"
hdiutil create \
  -volname "Codex Account Switcher" \
  -srcfolder "dist/dmg-staging" \
  -ov \
  -format UDZO \
  "dist/Codex Account Switcher.dmg"
```

The generated disk image will be written to `dist/Codex Account Switcher.dmg`.

## Run

```bash
open "dist/Codex Account Switcher.app"
```

The app appears in the macOS menu bar. It reads account state from `~/.codex/accounts/registry.json` and uses `codex-auth` commands for refresh, switch, and settings actions.

## Test

```bash
swift test
```

## Notes

- Manual switches relaunch the official Codex desktop app.
- Auto-switch notifications require notification permission.
- Build output is intentionally ignored; rebuild locally with `./scripts/build_app.sh`.
