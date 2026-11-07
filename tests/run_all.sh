#!/usr/bin/env bash
# Run every headless check: import/parse, then the Milestone 1, 2, 3 and cannon suites.
# Usage: tests/run_all.sh     (from the project root or anywhere)
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
fail=0

echo "== import / parse"
if "$GODOT" --headless --path . --import 2>&1 | grep -E "SCRIPT ERROR|Parse Error|ERROR:" | grep -v "debugger"; then
  echo "   import reported errors"; fail=1
else
  echo "   clean"
fi

for t in tests/test_milestone1.gd tests/test_milestone2.gd tests/test_milestone3.gd tests/test_cannon.gd; do
  echo "== $t"
  "$GODOT" --headless --path . --fixed-fps 60 -s "res://$t" 2>&1 | grep -E "PASS|FAIL|tests:|leaked|still in use"
  code=${PIPESTATUS[0]}
  [ "$code" -ne 0 ] && { echo "   exit code $code"; fail=1; }
done

[ $fail -eq 0 ] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED"
exit $fail
