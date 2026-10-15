# ZoneTab

A menu-bar app for macOS 26+ (Apple Silicon) that replaces AltTab and Rectangle for an ultrawide setup:

- **⌘⇥ app switcher.** It lists only the apps that have a window where the mouse is. That means the zone under the cursor when zones are on, or the display under the cursor otherwise.
- **Zones on 21:9 and wider displays.** A main zone and a second zone that takes the rest of the width. By default the main zone is 16:9 at full height (on a 5K2K panel, an exact 3840 px "4K" column); in Settings its width can be set from 20% to 80% of the display.

## Using it

| | |
|---|---|
| ⌘⇥ / ⌘⇧⇥ | Switch apps within the zone or display under the mouse |
| hold ⌘: ⇥ ⇧⇥ ← → | Move the selection |
| hold ⌘: ↩ / release ⌘ | Switch to the selected app |
| hold ⌘: ⎋ | Cancel |
| hold ⌘: Q / H | Quit / hide the selected app |
| ⌃⌥⌘↩ | Fill the window's zone; press again for the whole display; again to go back to the zone |
| ⌃⌥⌘← / ⌃⌥⌘→ | Move the window to the left / right zone (left / right half on regular displays) |
| ⇧ + drag a window | Highlight the zone under the cursor; drop to snap |

**What the switcher lists:**
- Apps whose windows are on the current Space, and hidden apps (⌘H, shown last and dimmed).
- With "Always include untiled windows" (on by default), untiled windows count for the whole display instead of one zone:
  - floating windows, such as settings and dialogs;
  - full-screen apps on that display's other Spaces, placed by when you last used them.

  A window counts as tiled when it fills at least 90% of a zone's width and height, or of the whole display.
- If the cursor's display is showing a full-screen Space, it lists every app instead.
- Apps with no windows, or only minimized windows, are not listed.

**Settings** (menu-bar icon → Settings…):
- turn zones on or off, and put the main zone on the left or right;
- set the main zone's width with a slider (the zones are previewed on screen while you drag; it snaps back to 16:9 near that width, or use "Use 16:9 (4K)");
- turn the ⌘⇥ replacement on or off, and choose whether untiled windows are listed from every zone;
- change the window shortcuts;
- launch at login.

ZoneTab needs **Accessibility** access. It doesn't need Screen Recording.

## Building

You need Xcode 27 and XcodeGen (`brew install xcodegen`).

To build, install to `/Applications` and relaunch:
```bash
scripts/run.sh
```

For a build without the debug `zonetab://` hooks:
```bash
scripts/run.sh Release
```

To run the core unit tests:
```bash
xcodebuild test -project ZoneTab.xcodeproj -scheme ZoneTabCore -destination 'platform=macOS,arch=arm64'
```

Builds are signed with the Developer ID certificate (team `LY2W69ED92`). A stable signature keeps the Accessibility permission across rebuilds.

## Debug tools (Debug builds only)

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

Put a scratch TextEdit window in full screen, check that ⌘⇥ lists it from both zones, and switch to it and back. Your display changes Spaces a few times while this runs:
```bash
scripts/e2e-fullscreen.sh
```

Follow ZoneTab's log:
```bash
log stream --predicate 'subsystem == "dev.sasha.zonetab"' --level debug
```

## If ⌘⇥ stops working

While ZoneTab runs, it turns off the system ⌘⇥ switcher, and macOS keeps that setting after the process exits. ZoneTab restores it in three cases: when you quit normally, when a watchdog process sees it crash or get killed, and when you turn off "Replace ⌘⇥". To restore it by hand:
```bash
/Applications/ZoneTab.app/Contents/MacOS/ZoneTab --restore-native-cmd-tab
```

## Layout

- `ZoneTabCore/`: pure logic, unit-tested in `ZoneTabCoreTests/`: zone geometry, which zone or display a window belongs to, the switcher list, and tile targets. Everything uses Quartz coordinates (origin at the top-left of the main display).
- `ZoneTab/System/`: system access:
  - window list and displays (`WindowInventory`);
  - Accessibility window control (`AXWindow`);
  - focusing a specific window through SkyLight (`WindowFocuser`);
  - Carbon hotkeys (`HotKeyCenter`);
  - native ⌘⇥ off/on plus the watchdog (`NativeSwitcherGuard`).
- `ZoneTab/Switcher/`: the ⌘⇥ session and its non-activating panel.
- `ZoneTab/Tiling/`: tiling commands and Shift-drag snapping.
- `ZoneTab/Settings/`, `ZoneTab/App/`: preferences, the menu-bar item, app lifecycle, and debug diagnostics.
- `ZoneTab/Resources/AppIcon.icon`: the app icon, an Icon Composer document (open it in Xcode's Icon Composer to edit). Preview it without building:
  ```bash
  "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" ZoneTab/Resources/AppIcon.icon --export-image --output-file icon.png --platform macOS --rendition Default --width 512 --height 512 --scale 1
  ```

**Private APIs:**
- `CGSSetSymbolicHotKeyEnabled`, `CGSCopyManagedDisplaySpaces` and `_AXUIElementGetWindow` are declared in the bridging header.
- `_SLPSSetFrontProcessWithOptions` and `SLPSPostEventRecordTo` are looked up at runtime. If they're missing, focusing falls back to public APIs.
