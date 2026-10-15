#!/bin/bash
# Print what a running Debug ZoneTab sees: displays, zones, windows and the ⌘⇥ list.
#   scripts/dump.sh            at the mouse
#   scripts/dump.sh 3360 800   at a point (Quartz coordinates: origin top-left of the main display)
set -euo pipefail

OUT="$HOME/Library/Application Support/ZoneTab/diagnostics.json"
URL="zonetab://dump"
[[ $# -ge 2 ]] && URL="zonetab://dump?x=$1&y=$2"
BEFORE=$(stat -f %m "$OUT" 2>/dev/null || echo 0)
open -g "$URL"
for _ in $(seq 1 30); do
  [[ $(stat -f %m "$OUT" 2>/dev/null || echo 0) != "$BEFORE" ]] && break
  sleep 0.1
done

python3 -I - "$OUT" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
r = lambda rect: [round(v) for v in rect[0] + rect[1]]
print(f'running={d["running"]} accessibility={d["accessibilityTrusted"]} zones={d["zonesEnabled"]} config={d["zoneConfig"]} '
      f'replaceCmdTab={d["replaceCommandTab"]} point={[round(v) for v in d["point"]]}')
for disp in d["displays"]:
    di = disp["display"]
    print(f'display {di["id"]}: frame={r(di["frame"])} usable={r(di["usableFrame"])} fullScreenSpace={disp["fullScreenSpace"]}')
    for z in disp.get("zones") or []:
        print(f'   zone {z["kind"]:9} {r(z["rect"])}')
scope = d.get("scope")
print("scope:", scope and f'display {scope["displayID"]} zone={scope.get("zone", "whole display")} rect={r(scope["rect"])}',
      "(full-screen fallback)" if d["fullScreenFallback"] else "")
print("windows:")
for w in d["windows"]:
    win = w["window"]
    print(f'   {w["app"][:24]:24} wid={win["id"]:<6} onscreen={str(win["isOnScreen"]):5} bounds={r(win["bounds"])} zones={w["zones"]}')
entries = [f'{e["app"]}{" (hidden)" if e["entry"]["isHidden"] else ""}' for e in d["switcher"]]
print("⌘⇥ list:", entries, "initial selection:", d.get("initialSelection"))
EOF
