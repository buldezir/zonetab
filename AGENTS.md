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
