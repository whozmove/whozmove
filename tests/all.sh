#!/bin/bash
# Runs every test: the rows the app builds, the panel page's logic, build.sh, the Browser's rules, the panel's edge, the
# edit keys, the switches kept while Whozmove runs, what the tests' own sandbox lets through, the checks that keep the
# parts and the modules apart, what goes outside this Mac, and each part's and
# each module's own tests (parts/<name>/tests/test.sh, modules/<name>/tests/test.sh; Claude Code's run both hooks). The
# app is built once for all of them, unless WHOZMOVE_APP already names a build (CI's, with every warning an error). A
# build that fails fails the tests that run the app, and the others still run. Exits 1 if any output changed.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
cd "$(dirname "$0")/.." || exit 1
. tests/sandboxed.sh "$@"
B=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-all.XXXXXX") || exit 1
trap 'rm -rf "$B"' EXIT
status=0
if [ -n "${WHOZMOVE_APP:-}" ] && [ -x "$WHOZMOVE_APP" ]; then
  :
elif tools/compile.sh "$B/Whozmove" -O0; then
  export WHOZMOVE_APP="$B/Whozmove"
else
  echo "The app didn't compile (above): the tests that run it fail, and the others run."
  export WHOZMOVE_APP_FAILED=1
  status=1
fi
tests/rows.sh || status=1
tests/panel.sh || status=1
tests/build.sh || status=1
tests/browser.sh || status=1
tests/edges.sh || status=1
tests/keys.sh || status=1
tests/ticked.sh || status=1
tests/sandbox.sh || status=1
tests/checks.sh || status=1
tests/outside.sh || status=1
for test in $(find parts modules -path '*/tests/test.sh' 2>/dev/null | LC_ALL=C sort); do
  "$test" || status=1
done
exit $status
