#!/bin/bash
# End-to-end tiling check against a running Debug ZoneTab: opens a scratch file in TextEdit, drives the tile
# commands through zonetab://tile and verifies the frames TextEdit actually ends up with.
set -euo pipefail

cd "$(dirname "$0")/.."
DIR="$HOME/Library/Application Support/ZoneTab"
RESULT="$DIR/tile-result.json"
SCRATCH="$(mktemp -d)/zonetab-e2e.txt"
echo "ZoneTab tiling test window" > "$SCRATCH"

TEXTEDIT_WAS_RUNNING=false
pgrep -x TextEdit >/dev/null && TEXTEDIT_WAS_RUNNING=true
open -a TextEdit "$SCRATCH"
sleep 2

tile() {
  local before
  before=$(stat -f %m "$RESULT" 2>/dev/null || echo 0)
  open -g "zonetab://tile?action=$1&bundle=com.apple.TextEdit"
  for _ in $(seq 1 30); do
    [[ $(stat -f %m "$RESULT" 2>/dev/null || echo 0) != "$before" ]] && break
    sleep 0.1
  done
  sleep 0.3
  cp "$RESULT" "$DIR/e2e-step-$2.json"
}

tile left 1; tile right 2; tile fill 3; tile fill 4; tile left 5; tile fill 6; tile fill 7
scripts/dump.sh 3360 800 > "$DIR/e2e-dump-zoneB.txt"
scripts/dump.sh 1440 800 > "$DIR/e2e-dump-zoneA.txt"

python3 -I - "$DIR" <<'EOF'
import json, sys, os
d = sys.argv[1]
dump = json.load(open(os.path.join(d, "diagnostics.json")))
display = next(x for x in dump["displays"] if x.get("zones"))
zones = {z["kind"]: z["rect"] for z in display["zones"]}
usable = display["display"]["usableFrame"]
flat = lambda r: [round(v) for v in r[0] + r[1]]
expected = [("left", zones["primary"]), ("right", zones["secondary"]), ("fill → display", usable),
            ("fill → back to zone", zones["secondary"]), ("left", zones["primary"]), ("fill → display", usable),
            ("fill → back to zone", zones["primary"])]
failures = 0
for i, (name, rect) in enumerate(expected, 1):
    step = json.load(open(os.path.join(d, f"e2e-step-{i}.json")))
    actual = step.get("outcome", {}).get("actual")
    ok = actual is not None and all(abs(a - b) <= 2 for a, b in zip(flat(actual), flat(rect)))
    failures += not ok
    print(f'{"PASS" if ok else "FAIL"} step {i} {name:22} expected {flat(rect)} got {flat(actual) if actual else None}')
print("FAILURES:", failures)
EOF
grep "⌘⇥ list" "$DIR/e2e-dump-zoneA.txt" | sed 's/^/zone A /'
grep "⌘⇥ list" "$DIR/e2e-dump-zoneB.txt" | sed 's/^/zone B /'

if ! $TEXTEDIT_WAS_RUNNING; then pkill -x TextEdit || true; fi
rm -f "$SCRATCH"
