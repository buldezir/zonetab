#!/bin/bash
# End-to-end check of "Keep tiles when a display is unplugged" against a running Debug ZoneTab, without unplugging
# anything: tiles two TextEdit scratch windows into the zones and leaves a third floating, then acts as if the
# display were unplugged (the tiled windows are maximized) and plugged back in (they go back to their zones).
# Only TextEdit's windows are moved.
set -euo pipefail

cd "$(dirname "$0")/.."
DIR="$HOME/Library/Application Support/ZoneTab"
SCRATCH="$(mktemp -d)"
OUT="$SCRATCH/out"
mkdir "$OUT"
NAMES=(zonetab-layout-1.txt zonetab-layout-2.txt zonetab-layout-3.txt)
for name in "${NAMES[@]}"; do echo "ZoneTab layout test window" > "$SCRATCH/$name"; done

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

# The test needs three separate windows; with "Prefer tabs when opening documents" set to Always they'd be tabs.
TEXTEDIT_WAS_RUNNING=false
if pgrep -x TextEdit >/dev/null; then
  TEXTEDIT_WAS_RUNNING=true
  if [[ $(defaults read -g AppleWindowTabbingMode 2>/dev/null || true) == always ]]; then
    echo "Quit TextEdit first: documents open as tabs, and the test needs separate windows."
    exit 1
  fi
fi
cleanup() {
  # Never leave the display marked as unplugged.
  open -g "zonetab://layout?action=restore&bundle=com.apple.TextEdit"
  for name in "${NAMES[@]}"; do
    osascript -e "tell application \"TextEdit\" to close (every document whose name is \"$name\") saving no" >/dev/null 2>&1 || true
  done
  $TEXTEDIT_WAS_RUNNING || osascript -e 'tell application "TextEdit" to quit' >/dev/null 2>&1 || true
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

# The argument only applies when this launches TextEdit, and only to that process.
open -a TextEdit "$SCRATCH/${NAMES[0]}" --args -AppleWindowTabbingMode manual; sleep 1.5
run "zonetab://tile?action=left&bundle=com.apple.TextEdit" tile-result.json tile-1.json
open -a TextEdit "$SCRATCH/${NAMES[1]}"; sleep 1.5
run "zonetab://tile?action=right&bundle=com.apple.TextEdit" tile-result.json tile-2.json
open -a TextEdit "$SCRATCH/${NAMES[2]}"; sleep 1.5
osascript -e "tell application \"TextEdit\" to set bounds of (first window whose name is \"${NAMES[2]}\") to {1000, 400, 1700, 900}"
sleep 0.5
IDS=()
for name in "${NAMES[@]}"; do IDS+=("$(window_id TextEdit "$name")"); done

run "zonetab://layout?action=save" layout-result.json save.json
run "zonetab://layout?action=disconnect&bundle=com.apple.TextEdit" layout-result.json disconnect.json
run "zonetab://dump" diagnostics.json dump-disconnected.json
run "zonetab://layout?action=restore&bundle=com.apple.TextEdit" layout-result.json restore.json
run "zonetab://dump" diagnostics.json dump-restored.json

python3 -I - "$OUT" "${IDS[@]}" <<'EOF'
import json, os, sys
out, ids = sys.argv[1], [int(x) for x in sys.argv[2:5]]
load = lambda name: json.load(open(os.path.join(out, name)))
flat = lambda r: [round(v) for v in r[0] + r[1]]
near = lambda a, b: a is not None and all(abs(x - y) <= 2 for x, y in zip(flat(a), flat(b)))
floating = [[1000, 400], [700, 500]]

display = next(d for d in load("dump-restored.json")["displays"] if d.get("zones"))
uuid, usable = display["display"]["uuid"], display["display"]["usableFrame"]
zones = {z["kind"]: z["rect"] for z in display["zones"]}
def bounds(dump):
    return {w["window"]["id"]: w["window"]["bounds"] for w in load(dump)["windows"]}

failures = 0
def check(name, ok, *details):
    global failures
    failures += not ok
    print(f'{"ok  " if ok else "FAIL"}  {name}' + ("" if ok else f"  {details}"))

check("found the three windows", 0 not in ids)
saved = {w["id"]: w["placement"] for w in (load("save.json").get("layout") or {}).get("windows", [])}
check("recorded the tiles", saved.get(ids[0]) == {"zone": {"_0": "primary"}} and saved.get(ids[1]) == {"zone": {"_0": "secondary"}},
      saved.get(ids[0]), saved.get(ids[1]))
check("recorded the floating window's frame", near(saved.get(ids[2], {}).get("frame", {}).get("_0"), floating))

unplugged = bounds("dump-disconnected.json")
check("unplugged: tiles maximized", near(unplugged.get(ids[0]), usable) and near(unplugged.get(ids[1]), usable),
      unplugged.get(ids[0]), unplugged.get(ids[1]), usable)
check("unplugged: floating window left alone", near(unplugged.get(ids[2]), floating))
check("unplugged: display marked away", uuid in load("disconnect.json")["away"])

replugged = bounds("dump-restored.json")
check("plugged back: tiles in their zones", near(replugged.get(ids[0]), zones["primary"]) and near(replugged.get(ids[1]), zones["secondary"]),
      replugged.get(ids[0]), replugged.get(ids[1]), zones)
check("plugged back: floating window where it was", near(replugged.get(ids[2]), floating))
check("plugged back: display no longer away", uuid not in load("restore.json")["away"])

print("All layout checks passed." if failures == 0 else f"{failures} check(s) failed.")
sys.exit(1 if failures else 0)
EOF
