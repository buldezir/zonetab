# ZoneTab

A menu-bar app for macOS 26+ (Apple Silicon) that replaces AltTab and Rectangle for an ultrawide setup. It does two things:

- **Splits ultrawide displays into two zones.** On displays 21:9 and wider there is a main zone and a second zone that takes the rest of the width. By default the main zone is 16:9 at full height: on a 5K2K panel, an exact 3840 px "4K" column. In Settings its width can be set from 20% to 80% of the display.
- **Replaces ⌘⇥ with a switcher scoped to where the mouse is.** It lists only the apps that have a window in the zone under the cursor, or on the display under the cursor when that display has no zones. Each zone works like a monitor of its own.

ZoneTab needs **Accessibility** access to move and focus windows. It doesn't need Screen Recording: it shows app icons, not window thumbnails.

## Install

Download `ZoneTab-macOS-arm64.zip` from [Releases](https://github.com/buldezir/zonetab/releases), unzip it and drag `ZoneTab.app` into Applications before you open it, then allow it under System Settings › Privacy & Security › Accessibility. To build it yourself, see [AGENTS.md](AGENTS.md).

ZoneTab is signed with Developer ID and notarized by Apple, and updates itself: **Check for Updates…** is in its menu bar menu, and Settings › Updates turns the daily checks and automatic installs on and off. If it says it can't be updated, it is running from the temporary copy macOS makes of an app opened where it was downloaded: quit it and run `xattr -dr com.apple.quarantine /Applications/ZoneTab.app`.

## Using it

| | |
|---|---|
| ⌘⇥ / ⌘⇧⇥ | Switch apps within the zone or display under the mouse |
| hold ⌘: ⇥ ⇧⇥ ← →, or point at an app | Move the selection |
| hold ⌘: ↩ / click an app / release ⌘ | Switch to the selected app |
| hold ⌘: ⎋ | Cancel |
| hold ⌘: Q / H | Quit / hide the selected app |
| ⌃⌥⌘↩ | Fill the window's zone; press again for the whole display; again to go back to the zone |
| ⌃⌥⌘← / ⌃⌥⌘→ | Move the window to the left / right zone (left / right half on regular displays) |
| ⇧ + drag a window | Highlight the zone under the cursor; drop to snap |

The window shortcuts can be changed in Settings.

## How it works

### Zones

- A display gets zones when it's at least 2.2 times as wide as it is tall. Other displays work as a whole.
- Zones fill the display's height below the menu bar (and above the Dock, unless it hides itself), the way a real monitor of that size would.
- Snapping is manual only: with the shortcuts, or by holding ⇧ while dragging a window. Windows keep their size until you snap them again.
- ⌃⌥⌘↩ remembers that it filled a window, so pressing it again expands to the whole display and then goes back to the zone. Moving or resizing the window yourself resets that.

### The switcher

- **Which zone a window is in:** the zone that holds its centre, plus any zone it covers at least half of. A window spanning the whole display is in both zones.
- **What's listed:**
  - Apps with a window in the zone on the current Space.
  - Hidden apps (⌘H), last and dimmed.
  - With "Always include untiled windows" (on by default), untiled windows count for the whole display instead of one zone. That covers floating windows, such as settings and dialogs, and full-screen apps on that display's other Spaces, placed by when you last used them. A window counts as tiled when it fills at least 90% of a zone's width and height, or of the whole display.
  - If the cursor's display is showing a full-screen Space, every app is listed instead.
  - Apps with no windows, or only minimized windows, are left out.
- **Order:** most recently used first, by each app's frontmost window in the zone.
- **Switching:**
  - Choosing an app brings forward only that window, the one it has in the zone. The app's windows in the other zone stay where they are.
  - A window on another Space, such as a full-screen app, switches to that Space.
- **Selection:** the switcher starts on the previous app, like the native one. A quick ⌘⇥, released before the panel appears, switches straight back.
- **Mouse:** pointing selects an app once the mouse moves, so a panel opening under a resting cursor keeps its selection. A click switches.

### The native switcher

- While ZoneTab runs with "Replace ⌘⇥" on, it turns off the system ⌘⇥ switcher.
- macOS keeps that setting after the process exits, so ZoneTab turns the system switcher back on in three cases:
  - when you quit it;
  - when a small watchdog process sees it crash or get killed;
  - when you turn off "Replace ⌘⇥".
- If ⌘⇥ ever stops working altogether, restore it by hand:
  ```bash
  /Applications/ZoneTab.app/Contents/MacOS/ZoneTab --restore-native-cmd-tab
  ```

### Unplugging a display

This is on by default ("Keep tiles when a display is unplugged").

- While a zoned display is connected, ZoneTab records where each of its windows is, on every Space. The record is updated every few seconds and after each snap.
- When you unplug the display, its tiled windows are maximized on the display they end up on. Floating windows are only moved if they no longer fit.
- When you plug it back in:
  - tiled windows go back to their zones, using the current zone settings;
  - floating windows go back to where they were, including windows you moved in the meantime;
  - windows opened while it was unplugged stay where they are.
- Closing or opening a laptop's lid counts as a display change too: afterwards, the display gets its recorded layout back.
  - When the lid closes, its tiles stay put. The laptop's windows land wherever macOS puts them, and are recorded from then on.
  - When the lid opens, windows macOS moves to the laptop come back.
- Unplugging the display with the lid closed works too. The Mac sleeps until you open the lid, and the windows are maximized on the laptop then.
- Windows get their frames back, but not necessarily their Space, and the stacking order isn't restored.
- The record is kept in `~/Library/Application Support/ZoneTab/display-layouts.json`, so it survives restarting ZoneTab. Restarting an app gives its windows new ids, so those windows aren't restored.

### Focus follows the mouse between zones

This is off by default.

- When the mouse moves into another zone, or onto another display, the window under it comes to the front and gets focus, as if you had clicked it. Moving around inside a zone changes nothing.
- The mouse has to stay in the zone for a moment (0.1 s), so passing through one on the way somewhere else doesn't focus it.
- If the mouse enters the zone over the menu bar, a menu, the Dock or the desktop, the window is focused once the mouse reaches it.
- Nothing happens while the ⌘⇥ switcher is open.
- Clicking, holding a key, or pressing one before the window comes forward keeps the focus where it is until the mouse moves into another zone. Keystrokes keep going to the window you're typing in.

## Settings

Open them from the menu-bar icon → Settings…:
- turn zones on or off, and put the main zone on the left or right;
- set the main zone's width with a slider (the zones are previewed on screen while you drag; it snaps back to 16:9 near that width, or use "Use 16:9 (4K)");
- keep tiles when a display is unplugged;
- focus follows the mouse between zones;
- turn the ⌘⇥ replacement on or off, and choose whether untiled windows are listed from every zone;
- change the window shortcuts;
- launch at login.

The menu-bar menu also has quick toggles for zones, the main zone's side, focus following the mouse and the ⌘⇥ replacement.

Building and development notes are in [AGENTS.md](AGENTS.md).

## License

ZoneTab is licensed under the [GNU Affero General Public License v3.0](LICENSE).
