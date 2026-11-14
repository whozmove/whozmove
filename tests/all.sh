#!/bin/bash
# Runs every test: the rows the app builds, the panel page's logic, build.sh, the Browser's rules, the panel's edge, the
# edit keys, the switches kept while Whozmove runs, what the tests' own sandbox lets through, the checks that keep the
# parts and the modules apart, what goes outside this Mac, and each part's and
# each module's own tests (parts/<name>/tests/test.sh, modules/<name>/tests/test.sh; Claude Code's run both hooks). The
# app is built once for all of them, unless WHOZMOVE_APP already names a build (CI's, with every warning an error). A
# build that fails fails the tests that run the app, and the others still run. Exits 1 if any output changed, and ends
# with the tests that failed, so one doesn't scroll past unseen.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
cd "$(dirname "$0")/.." || exit 1
. tests/sandboxed.sh "$@"
. tests/lib.sh
B=$(throwaway all) || exit 1
leave_nothing "$B"
failed=()
run() { "$1" || failed+=("$1"); }
if [ -n "${WHOZMOVE_APP:-}" ] && [ -x "$WHOZMOVE_APP" ]; then
  :
elif tools/compile.sh "$B/Whozmove" -O0; then
  export WHOZMOVE_APP="$B/Whozmove"
else
  echo "The app didn't compile (above): the tests that run it fail, and the others run."
  export WHOZMOVE_APP_FAILED=1
  failed+=("the app's build")
fi
run tests/rows.sh
run tests/panel.sh
run tests/build.sh
run tests/browser.sh
run tests/edges.sh
run tests/keys.sh
run tests/ticked.sh
run tests/sandbox.sh
run tests/checks.sh
run tests/outside.sh
run tests/energy-tool.sh
for test in $(find parts modules -path '*/tests/test.sh' 2>/dev/null | LC_ALL=C sort); do
  run "$test"
done
echo
if [ ${#failed[@]} -gt 0 ]; then
  echo "Failed (${#failed[@]}):"
  printf '  %s\n' "${failed[@]}"
  exit 1
fi
echo "Every test passed."
