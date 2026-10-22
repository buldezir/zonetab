# ZoneTab: development notes

What the app does and how it behaves is in [README.md](README.md). This file covers building, testing and the code.

## Building

You need Xcode 27 and XcodeGen (`brew install xcodegen`). `project.yml` is the source of truth; `ZoneTab.xcodeproj` is generated and not committed.

To build a Debug version (it includes the `zonetab://` debug hooks), install it to `/Applications` and relaunch:
```bash
scripts/run.sh
```

The same for a build without the debug hooks:
```bash
scripts/run.sh Release
```

`run.sh` quits the running ZoneTab gracefully first, so the native ⌘⇥ switcher is restored before the new build takes over.

Builds are signed with the Developer ID certificate (team `LY2W69ED92`). A stable signature keeps the Accessibility permission across rebuilds.

## Releases

`.github/workflows/release.yml` runs on `v*` tags, on the `xcode-27` runner:
- It builds ZoneTab in Release, arm64 only. The tag sets `MARKETING_VERSION`, and `CURRENT_PROJECT_VERSION`, a build number that only grows (`0.3.0-beta.2` → 30002, `0.3.0` → 30099), which Sparkle compares. A local build is version `0.1`, and doesn't update.
- It signs the app with the Developer ID certificate in the repository's secrets (`MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD`, `APPLE_TEAM_ID`), then notarizes it with an App Store Connect API key (`NOTARY_API_KEY_BASE64`, `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER_ID`) and staples it. `scripts/sign-sparkle.sh`, the target's last build phase, signs Sparkle's helpers with Developer ID, as notarization requires.
- `scripts/appcast.sh` writes the app's Sparkle feed, `ZoneTab-macOS-appcast.xml`: the zip's EdDSA signature (`SPARKLE_PRIVATE_KEY`, checked against the app's `SUPublicEDKey`) and the release's notes up to its `## Downloads`, if the release is written by then. The release job uploads `ZoneTab-macOS-arm64.zip` and `SHA256SUMS`, then the feed, which `SUFeedURL` reads from the latest release.
- A tag without the secrets fails. A run by hand without them signs ad hoc and keeps the zip as a run artifact. An ad hoc build has no hardened runtime, under which it couldn't load Sparkle.framework (`HARDENED_RUNTIME_WITHOUT_TEAM` in `project.yml`). A run by hand takes a `version`, such as `0.2.0-test.1`, to build an app that offers and takes updates, and a `bundle_id`, such as `dev.sasha.zonetab.updatetest`, to keep it apart from the installed one.

ZoneTab updates itself with Sparkle (`AppUpdater`). An update a daily check finds while ZoneTab is in the background waits in the menu bar menu, as **Update to …**, instead of opening a window. Sparkle refuses to update an app that macOS runs from a temporary copy (App Translocation: its path has `/AppTranslocation/`), which happens to a downloaded app opened before it was moved into Applications. `xattr -dr com.apple.quarantine` on the app in Applications fixes it; the README and the release notes say so.

Sparkle installs only updates signed with the key whose public half is `SPARKLE_PUBLIC_KEY` in `project.yml`. Its private half is in the login keychain of the Mac that made it, and in the repository's secrets; keep a backup, since without it the app can never update again:

```bash
mkdir -p ~/sparkle && curl -fsSL https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz | tar -xf - -C ~/sparkle
~/sparkle/bin/generate_keys --account zonetab         # prints the public key
~/sparkle/bin/generate_keys --account zonetab -x ~/sparkle/private-key
gh secret set SPARKLE_PRIVATE_KEY < ~/sparkle/private-key
```

## Tests

To run the core unit tests:
```bash
xcodebuild test -project ZoneTab.xcodeproj -scheme ZoneTabCore -destination 'platform=macOS,arch=arm64'
```

The tests use Swift Testing and have no host app, so running them never turns off the system ⌘⇥.

## Debug tools (Debug builds only)

The running app handles `zonetab://` URLs and writes its results to `~/Library/Application Support/ZoneTab/`. Always send them with `open -g`, so the frontmost app doesn't change. They go to the running instance, which holds the Accessibility permission; a binary started from a terminal would get the terminal's permissions instead. The full list of hooks is at the top of `ZoneTab/App/Diagnostics.swift`.

Print the displays, zones, windows and ⌘⇥ list at the mouse:
```bash
scripts/dump.sh
```

The same, at a point in Quartz coordinates:
```bash
scripts/dump.sh 3360 800
```

Tile a scratch TextEdit window through every command and check where it ends up:
```bash
scripts/e2e-tiling.sh
```

Put a scratch TextEdit window in full screen with TextEdit's own ⌃⌘F, check that ⌘⇥ lists it from both zones, and switch to it and back. Your display changes Spaces a few times while this runs:
```bash
scripts/e2e-fullscreen.sh
```

Tile two TextEdit scratch windows and float a third, then act as if the display were unplugged and plugged back in. Only TextEdit's windows move:
```bash
scripts/e2e-layout.sh
```

Point at and click an app in the ⌘⇥ switcher, then move between the zones with "Focus follows the mouse" on, with and without a key held, using two TextEdit scratch windows. It posts real mouse and keyboard events and holds ⌘ for a few seconds. Run it only when nobody is using the Mac: keys typed meanwhile reach the frontmost app as ⌘ shortcuts.
```bash
scripts/e2e-mouse.sh
```

Follow ZoneTab's log (in zsh, `log` is a shell builtin, so use the full path). Debug messages aren't kept, so stream them while reproducing a problem rather than reading them afterwards:
```bash
/usr/bin/log stream --predicate 'subsystem == "dev.sasha.zonetab"' --level debug
```

## Code layout

- `ZoneTabCore/`: pure logic, unit-tested in `ZoneTabCoreTests/`:
  - zone geometry (`ZoneLayout`);
  - which zone or display a window belongs to (`ScopeResolver`);
  - the switcher list (`SwitcherListBuilder`);
  - tile targets (`TileActions`);
  - the layout kept across unplugging a display (`LayoutMemory`);
  - the window to focus under the mouse (`MouseFocus`).

  Everything uses Quartz coordinates (origin at the top-left of the main display).
- `ZoneTab/System/`: system access:
  - window list and displays (`WindowInventory`);
  - Accessibility window control (`AXWindow`);
  - focusing a specific window through SkyLight (`WindowFocuser`);
  - Carbon hotkeys (`HotKeyCenter`);
  - native ⌘⇥ off/on plus the watchdog (`NativeSwitcherGuard`).
- `ZoneTab/Switcher/`: the ⌘⇥ session and its non-activating panel.
- `ZoneTab/Tiling/`: tiling commands, Shift-drag snapping, keeping tiles across unplugging a display (`DisplayLayoutKeeper`), and focus following the mouse (`FocusFollower`).
- `ZoneTab/Settings/`, `ZoneTab/App/`: preferences, the menu-bar item, app lifecycle, and debug diagnostics.
- `ZoneTab/Resources/AppIcon.icon`: the app icon, an Icon Composer document (open it in Xcode's Icon Composer to edit). Preview it without building:
  ```bash
  "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" ZoneTab/Resources/AppIcon.icon --export-image --output-file icon.png --platform macOS --rendition Default --width 512 --height 512 --scale 1
  ```

**Conventions:**
- Swift 6 with approachable concurrency. The app target is on the main actor by default (`SWIFT_DEFAULT_ACTOR_ISOLATION`). Anything that makes Accessibility calls runs off the main thread, because AX calls block until the target app answers.
- Logic that can be tested without the system goes in `ZoneTabCore`. It only imports CoreGraphics and isn't main-actor isolated.
- Debug-only code sits in `#if DEBUG`.

**Private APIs:**
- `CGSSetSymbolicHotKeyEnabled`, `CGSCopyManagedDisplaySpaces`, `_AXUIElementGetWindow` and `_AXUIElementCreateWithRemoteToken` (to reach windows on other Spaces) are declared in the bridging header.
- `_SLPSSetFrontProcessWithOptions` and `SLPSPostEventRecordTo` are looked up at runtime. If they're missing, focusing falls back to public APIs.

## Things that bite

- **The native ⌘⇥ setting outlives the process.** Never leave it off: quit ZoneTab gracefully (`run.sh` does), and if it does get stuck, run `ZoneTab --restore-native-cmd-tab`.
- **Windows on other Spaces through Accessibility:**
  - `kAXWindows` only lists windows on the current Space.
  - Other windows are reached by sweeping remote-token element ids. That only finds elements some Accessibility client has already asked for: a window that went straight into full screen has none.
  - An app's focused and main windows are given out from any Space, so `AXWindow.windowsOnAnySpace` asks for those first.
  - Raising a window through Accessibility is what moves to its Space; making it key through SkyLight doesn't.
- **Display changes:**
  - `NSScreen` lags behind them. `CGGetOnlineDisplayList` has the live configuration (`WindowInventory.onlineDisplays`).
  - A laptop's built-in display is offline while the lid is closed.
  - macOS moves windows around for a moment after a change, so wait for it to settle.
- **TextEdit in tests.** With "Prefer tabs when opening documents" set to Always (`AppleWindowTabbingMode`), TextEdit opens documents as tabs of one window. Inactive tabs keep a stale frame in the window list. The e2e scripts that need several windows (`e2e-layout.sh`, `e2e-mouse.sh`) launch TextEdit with `-AppleWindowTabbingMode manual`, and refuse to run if it's already running in tab mode.
- **Logging:** `Logger` can't interpolate a `Duration` directly; use `.description` with `privacy: .public`.
