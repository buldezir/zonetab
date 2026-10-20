#!/bin/bash
# End-to-end check of the mouse in the ⌘⇥ switcher and of "Focus follows the mouse between zones", against a
# running Debug ZoneTab. Tiles two TextEdit scratch windows into the zones of the first zoned display, then moves the
# mouse and holds ⌘ for a few seconds: leave the mouse and keyboard alone while it runs. Afterwards the mouse goes
# back where it was and the setting is restored.
set -euo pipefail

cd "$(dirname "$0")/.."
DIR="$HOME/Library/Application Support/ZoneTab"
SCRATCH="$(mktemp -d)"
OUT="$SCRATCH/out"
mkdir "$OUT"
NAMES=(zonetab-mouse-1.txt zonetab-mouse-2.txt)
for name in "${NAMES[@]}"; do echo "ZoneTab mouse test window" > "$SCRATCH/$name"; done

# Runs a zonetab:// command and keeps a copy of the file it writes.
run() { # url, result file, copy name
  rm -f "$DIR/$2"
  open -g "$1"
  for _ in $(seq 1 100); do [[ -f "$DIR/$2" ]] && break; sleep 0.1; done
  sleep 0.2
  cp "$DIR/$2" "$OUT/$3"
}

window_id() { # owner, title
  swift - "$@" <<'EOF'
import CoreGraphics
let args = CommandLine.arguments.dropFirst()
let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let match = list.first { ($0[kCGWindowOwnerName as String] as? String) == args.first && ($0[kCGWindowName as String] as? String) == args.last }
print(match.flatMap { $0[kCGWindowNumber as String] as? Int } ?? 0)
EOF
}

# Posts mouse and keyboard events, in Quartz coordinates. A trailing "cmd" marks mouse events as made with ⌘ held.
# "key down|up|tap CODE" presses a key without modifiers.
cat > "$SCRATCH/input.swift" <<'EOF'
import CoreGraphics
import Foundation

let source = CGEventSource(stateID: .hidSystemState)
let args = Array(CommandLine.arguments.dropFirst())
let command = args.last == "cmd"
func point(_ index: Int) -> CGPoint { CGPoint(x: Double(args[index])!, y: Double(args[index + 1])!) }
func post(_ event: CGEvent?) {
    event?.post(tap: .cghidEventTap)
    usleep(10_000)
}
func mouse(_ type: CGEventType, _ location: CGPoint) {
    let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: .left)
    event?.flags = command ? .maskCommand : []
    post(event)
}
func key(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
    let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
    event?.flags = flags
    post(event)
}

switch args.first {
case "where":
    let location = CGEvent(source: nil)?.location ?? .zero
    print(Int(location.x), Int(location.y))
case "warp":
    CGWarpMouseCursorPosition(point(1))
case "move":
    mouse(.mouseMoved, point(1))
case "glide":
    let from = point(1), to = point(3)
    for step in 1...20 {
        let t = CGFloat(step) / 20
        mouse(.mouseMoved, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
    }
case "click":
    mouse(.leftMouseDown, point(1))
    usleep(50_000)
    mouse(.leftMouseUp, point(1))
case "cmd":
    key(55, down: args[1] == "down", flags: args[1] == "down" ? .maskCommand : [])
case "key":
    let code = CGKeyCode(args[2])!
    if args[1] != "up" { key(code, down: true, flags: []) }
    if args[1] != "down" { key(code, down: false, flags: []) }
case "cmdtab":
    key(48, down: true, flags: .maskCommand)
    key(48, down: false, flags: .maskCommand)
default:
    exit(2)
}
EOF
swiftc -O -o "$SCRATCH/input" "$SCRATCH/input.swift"
input() { "$SCRATCH/input" "$@"; }

# The test needs two separate windows; with "Prefer tabs when opening documents" set to Always they'd be tabs.
TEXTEDIT_WAS_RUNNING=false
if pgrep -x TextEdit >/dev/null; then
  TEXTEDIT_WAS_RUNNING=true
  if [[ $(defaults read -g AppleWindowTabbingMode 2>/dev/null || true) == always ]]; then
    echo "Quit TextEdit first: documents open as tabs, and the test needs separate windows."
    exit 1
  fi
fi
START=$(input where)
ARROW=124 # →: the key held and pressed below, in the frontmost TextEdit window
FOLLOWS_WAS=$(defaults read dev.sasha.zonetab focusFollowsMouse 2>/dev/null || echo 0)
cleanup() {
  input cmd up
  input key up "$ARROW"
  open -g "zonetab://focusfollows?on=$FOLLOWS_WAS"
  # shellcheck disable=SC2086
  input warp $START
  for name in "${NAMES[@]}"; do
    osascript -e "tell application \"TextEdit\" to close (every document whose name is \"$name\") saving no" >/dev/null 2>&1 || true
  done
  $TEXTEDIT_WAS_RUNNING || osascript -e 'tell application "TextEdit" to quit' >/dev/null 2>&1 || true
  rm -rf "$SCRATCH"
}
trap cleanup EXIT
front_window() { osascript -e 'tell application "TextEdit" to name of front window'; }
frontmost_app() { osascript -e 'id of application (path to frontmost application as text)'; }

# The argument only applies when this launches TextEdit, and only to that process.
open -a TextEdit "$SCRATCH/${NAMES[0]}" --args -AppleWindowTabbingMode manual; sleep 1.5
run "zonetab://tile?action=left&bundle=com.apple.TextEdit" tile-result.json tile-1.json
open -a TextEdit "$SCRATCH/${NAMES[1]}"; sleep 1.5
run "zonetab://tile?action=right&bundle=com.apple.TextEdit" tile-result.json tile-2.json
ID1=$(window_id TextEdit "${NAMES[0]}")
run "zonetab://dump" diagnostics.json dump.json
# Points in the middle of each zone, and at the top of each zone, over the menu bar.
read -r A B A_TOP B_TOP < <(python3 -I - "$OUT/dump.json" <<'EOF'
import json, sys
display = next(d for d in json.load(open(sys.argv[1]))["displays"] if d.get("zones"))
zones = {z["kind"]: z["rect"] for z in display["zones"]}
top = display["display"]["frame"][0][1] + 5
def middle(rect): return f'{round(rect[0][0] + rect[1][0] / 2)},{round(rect[0][1] + rect[1][1] / 2)}'
def high(rect): return f'{round(rect[0][0] + rect[1][0] / 2)},{round(top)}'
print(middle(zones["primary"]), middle(zones["secondary"]), high(zones["primary"]), high(zones["secondary"]))
EOF
)
A=${A/,/ }; B=${B/,/ }; A_TOP=${A_TOP/,/ }; B_TOP=${B_TOP/,/ }

# --- The switcher: it opens around a resting mouse, then the mouse points at TextEdit and clicks it. ---
run "zonetab://focusfollows?on=0" focusfollows-result.json follows-off.json
run "zonetab://focus?wid=$ID1" focus-result.json focus-1.json
# shellcheck disable=SC2086
input move $A; sleep 0.3
input cmd down
input cmdtab; sleep 0.4
run "zonetab://switcher" switcher-result.json opened.json
TARGET=$(python3 -I -c '
import json, sys
items = json.load(open(sys.argv[1]))["items"]
frame = next((i["frame"] for i in items if i["name"] == "TextEdit"), None)
print(f"{round(frame[0][0] + frame[1][0] / 2)} {round(frame[0][1] + frame[1][1] / 2)}" if frame else "")
' "$OUT/opened.json")
if [[ -n $TARGET ]]; then
  # shellcheck disable=SC2086
  input glide $A $TARGET cmd; sleep 0.2
  run "zonetab://switcher" switcher-result.json pointed.json
  # shellcheck disable=SC2086
  input click $TARGET cmd; sleep 0.3
  run "zonetab://switcher" switcher-result.json clicked.json
fi
input cmd up; sleep 0.3
SWITCHED_TO=$(frontmost_app)

# --- Focus follows the mouse: moving between the zones focuses the window there. ---
run "zonetab://focusfollows?on=1" focusfollows-result.json follows-on.json
run "zonetab://focus?wid=$ID1" focus-result.json focus-2.json
# shellcheck disable=SC2086
{
  input move $A; sleep 0.3
  input glide $A $B; sleep 0.6
  FRONT_IN_B=$(front_window)
  input glide $B $A; sleep 0.6
  FRONT_IN_A=$(front_window)
  # Into the other zone over the menu bar: nothing happens until the mouse is over the window.
  input glide $A $A_TOP; sleep 0.3
  input glide $A_TOP $B_TOP; sleep 0.6
  FRONT_OVER_MENU_BAR=$(front_window)
  input glide $B_TOP $B; sleep 0.6
  FRONT_DOWN_IN_B=$(front_window)
  # Holding a key, or pressing one on the way, keeps the focus where it is until the mouse moves to another zone.
  input key down "$ARROW"
  input glide $B $A; sleep 0.6
  FRONT_KEY_HELD=$(front_window)
  input key up "$ARROW"
  input glide $A $A_TOP; sleep 0.6
  FRONT_KEY_RELEASED=$(front_window)
  input glide $A_TOP $B_TOP; sleep 0.3
  input glide $B_TOP $A_TOP; sleep 0.3
  input key tap "$ARROW"
  input glide $A_TOP $A; sleep 0.6
  FRONT_KEY_PRESSED=$(front_window)
  input glide $A $B; sleep 0.6
  input glide $B $A; sleep 0.6
  FRONT_AFTER_KEYS=$(front_window)
}

python3 -I - "$OUT" "$SWITCHED_TO" "${NAMES[@]}" "$FRONT_IN_B" "$FRONT_IN_A" "$FRONT_OVER_MENU_BAR" "$FRONT_DOWN_IN_B" \
  "$FRONT_KEY_HELD" "$FRONT_KEY_RELEASED" "$FRONT_KEY_PRESSED" "$FRONT_AFTER_KEYS" <<'EOF'
import json, os, sys
out, switched_to, name1, name2, in_b, in_a, over_menu_bar, down_in_b = sys.argv[1:9]
key_held, key_released, key_pressed, after_keys = sys.argv[9:13]
load = lambda name: json.load(open(os.path.join(out, name))) if os.path.exists(os.path.join(out, name)) else {}
opened, pointed, clicked = load("opened.json"), load("pointed.json"), load("clicked.json")
names = [item["name"] for item in opened.get("items", [])]

failures = 0
def check(name, ok, *details):
    global failures
    failures += not ok
    print(f'{"ok  " if ok else "FAIL"}  {name}' + ("" if ok else f"  {details}"))

check("switcher open, TextEdit first", opened.get("panelVisible") and names[:1] == ["TextEdit"] and len(names) > 1, opened)
check("a resting mouse leaves the selection alone", opened.get("selection") == 1, opened.get("selection"))
check("pointing at TextEdit selects it", pointed.get("selection") == 0 and pointed.get("active"), pointed)
check("clicking it switches, with ⌘ still held", clicked.get("active") is False and switched_to == "com.apple.TextEdit",
      clicked, switched_to)
check("moving into the right zone focuses its window", in_b == name2, in_b)
check("moving back focuses the left zone's window", in_a == name1, in_a)
check("over the menu bar, nothing changes yet", over_menu_bar == name1, over_menu_bar)
check("reaching the window focuses it", down_in_b == name2, down_in_b)
check("holding a key keeps the focus", key_held == name2, key_held)
check("releasing it changes nothing until the next zone", key_released == name2, key_released)
check("a key pressed on the way keeps the focus", key_pressed == name2, key_pressed)
check("without keys, the focus follows again", after_keys == name1, after_keys)

print("All mouse checks passed." if failures == 0 else f"{failures} check(s) failed.")
sys.exit(1 if failures else 0)
EOF
