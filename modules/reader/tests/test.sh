#!/bin/bash
# The reader module's tests: where a prototype a session wrote is shown from, or why it can't be (Whozmove
# --print-prototypes, compared with prototypes.expected.txt), and what the line above it says (page-cases.js, run with
# macOS's jsc in UTC, compared with page.expected.txt).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/reader/tests/test.sh            run and compare
#   modules/reader/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
HERE=modules/reader/tests
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-reader.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
trap 'rm -rf "$T"' EXIT
. tests/lib.sh
. tests/compare.sh
APP=$(built_app "$T") || exit 1

# Pages a session wrote: one with a file beside it, one in a folder of its own, one reached through a link to its
# folder, one since deleted, and one saved straight into the home folder.
mkdir -p "$T/home/work/site/sub"
for file in work/site/page.html work/site/beside.css work/site/sub/inner.html top.html; do
  echo '<p>A sample page.</p>' > "$T/home/$file"
done
ln -s site "$T/home/work/linked"

status=0
out=$(
echo "== Where each prototype is shown from (its folder, read from there, with the web's parts, links out to your"
echo "   browser, nothing kept), or why it can't be"
HOME="$T/home" "$APP" --print-prototypes "$T/home/work/site/page.html" "$T/home/work/site/sub/inner.html" \
  "$T/home/work/linked/page.html" "$T/home/work/site/gone.html" "$T/home/top.html" | in_minutes | sed -e "s|$T|T|g"
)
compare "Prototypes" "$HERE/prototypes.expected.txt" "$out" "${1:-}" || status=1

page=$(page_cases "$HERE/page-cases.js") || { echo "$page"; exit 1; }
compare "The reader's page" "$HERE/page.expected.txt" "$page" "${1:-}" || status=1
exit $status
