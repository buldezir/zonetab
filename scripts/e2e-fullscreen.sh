#!/bin/bash
# End-to-end full-screen check against a running Debug ZoneTab: puts a TextEdit scratch window in full screen (by
# pressing ⌃⌘F in TextEdit), checks that ⌘⇥ lists it from both zones ("Always include untiled windows"), then
# switches to it and back through zonetab://focus. Your display switches Spaces a few times while it runs.
set -euo pipefail

cd "$(dirname "$0")/.."
DIR="$HOME/Library/Application Support/ZoneTab"
SCRATCH="$(mktemp -d)/zonetab-fullscreen.txt"
NAME="$(basename "$SCRATCH")"
echo "ZoneTab full-screen test window" > "$SCRATCH"

wait_for() { # file, previous mtime
  for _ in $(seq 1 50); do
    [[ $(stat -f %m "$1" 2>/dev/null || echo 0) != "$2" ]] && return
    sleep 0.1
  done
}

# Window ids by owner and title, or the frontmost app's topmost window.
window_id() {
  swift - "$@" <<'EOF'
import AppKit
let args = CommandLine.arguments.dropFirst()
let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let match: ([String: Any]) -> Bool
if args.first == "--frontmost" {
    let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
    match = { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
        && ($0[kCGWindowIsOnscreen as String] as? Bool) == true }
} else {
    match = { ($0[kCGWindowOwnerName as String] as? String) == args.first && ($0[kCGWindowName as String] as? String) == args.last }
}
print(list.first(where: match).flatMap { $0[kCGWindowNumber as String] as? Int } ?? 0)
EOF
}

focus() { # window id
  local before
  before=$(stat -f %m "$DIR/focus-result.json" 2>/dev/null || echo 0)
  open -g "zonetab://focus?wid=$1"
  wait_for "$DIR/focus-result.json" "$before"
  sleep 0.2
  python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))['spaces'])" "$DIR/focus-result.json"
}

HOME_WINDOW=$(window_id --frontmost)
[[ $HOME_WINDOW != 0 ]] || { echo "No frontmost window to come back to"; exit 1; }

TEXTEDIT_WAS_RUNNING=false
pgrep -x TextEdit >/dev/null && TEXTEDIT_WAS_RUNNING=true
open -a TextEdit "$SCRATCH"
sleep 2
# Into full screen with TextEdit's own shortcut, not through Accessibility: a window that no Accessibility client has
# asked about yet is the hard one to switch to.
swift - <<'EOF'
import AppKit
guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.TextEdit" else {
    print("TextEdit isn't in front")
    exit(1)
}
let source = CGEventSource(stateID: .hidSystemState)
for down in [true, false] {
    let event = CGEvent(keyboardEventSource: source, virtualKey: 3, keyDown: down) // ⌃⌘F
    event?.flags = [.maskControl, .maskCommand]
    event?.post(tap: .cghidEventTap)
}
EOF
sleep 2
FULL_SCREEN=$(window_id TextEdit "$NAME")

failures=0
check() { # description, condition result
  if [[ $2 == true ]]; then echo "ok    $1"; else echo "FAIL  $1"; failures=$((failures + 1)); fi
}

spaces=$(focus "$HOME_WINDOW")
check "back on the desktop" "$([[ $spaces == *"type 0"* ]] && echo true || echo false)"
for point in "500 800" "3700 800"; do
  # shellcheck disable=SC2086
  listed=$(scripts/dump.sh $point | grep "⌘⇥ list" | grep -c "'TextEdit'" || true)
  check "listed from x=${point% *}" "$([[ $listed == 1 ]] && echo true || echo false)"
done
spaces=$(focus "$FULL_SCREEN")
check "switched to the full-screen window" "$([[ $spaces == *"type 4 fs_wid $FULL_SCREEN"* ]] && echo true || echo false)"
spaces=$(focus "$HOME_WINDOW")
check "switched back" "$([[ $spaces == *"type 0"* ]] && echo true || echo false)"

osascript -e "tell application \"TextEdit\" to close (every document whose name is \"$NAME\") saving no"
$TEXTEDIT_WAS_RUNNING || osascript -e 'tell application "TextEdit" to quit'
rm -f "$SCRATCH"
[[ $failures == 0 ]] && echo "All full-screen checks passed." || { echo "$failures check(s) failed."; exit 1; }
