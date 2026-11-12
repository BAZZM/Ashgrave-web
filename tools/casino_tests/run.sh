#!/usr/bin/env bash
# Runs the casino core tests headless: tools/casino_tests/run.sh <path-to-godot-4.4.1>
# The scripts are copied into a throwaway project in a temp dir, so nothing
# under game/ (notably game/.godot and game/project.godot) is ever opened by
# the engine, and the repo's autoloads (Online, Perf) never start.
# QUICK=1 shrinks the property runs for fast iteration.
set -euo pipefail
GODOT="${1:?usage: tools/casino_tests/run.sh <path-to-godot>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts" "$TMP/tests"
cp -r "$REPO/game/scripts/casino" "$TMP/scripts/casino"
cp "$HERE"/*.gd "$TMP/tests/"
printf 'config_version=5\n\n[application]\nconfig/name="casino_tests"\n' > "$TMP/project.godot"
START=$(date +%s)
EXTRA=()
if [[ -n "${QUICK:-}" ]]; then EXTRA+=(--quick); fi
set +e
timeout "${CASINO_TIMEOUT:-1800}" "$GODOT" --headless --path "$TMP" -s res://tests/main.gd -- --export="$TMP/hands.tsv" "${EXTRA[@]}" 2>&1 | tee "$TMP/out.log"
GD=${PIPESTATUS[0]}
set -e
STATUS=0
if [[ $GD -ne 0 ]]; then echo "GDScript tests failed (exit $GD)"; STATUS=1; fi
# A runtime script error does not stop Godot; treat any as a failure.
if grep -E -q "SCRIPT ERROR|Parse Error|^ERROR:" "$TMP/out.log"; then
  echo "Engine reported script errors (see above)"; STATUS=1
fi
if ! grep -q "GDSCRIPT TOTAL" "$TMP/out.log"; then echo "GDScript runner did not finish"; STATUS=1; fi
if [[ -f "$TMP/hands.tsv" ]]; then
  python3 -I "$HERE/ref_eval.py" "$TMP/hands.tsv" || STATUS=1
else
  echo "no exported hands for the Python cross-check"; STATUS=1
fi
echo "casino tests: $([[ $STATUS -eq 0 ]] && echo PASS || echo FAIL) in $(( $(date +%s) - START )) s"
exit $STATUS
