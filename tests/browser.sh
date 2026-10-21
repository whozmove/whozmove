#!/bin/bash
# The Browser's rules (app/core/Browser.m), as Whozmove --print-browsing prints them for a sample folder: where each
# kind of address goes from each sample setup, the folders too wide to show a page from, the store each name's sign-ins
# are kept in, and how it introduces itself, compared with tests/browser.expected.txt.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   tests/browser.sh            run and compare
#   tests/browser.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/.." || exit 1
# Stops here if there's no temporary folder: an empty T would make the clean-up below delete this checkout.
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-browser.XXXXXX") || exit 1
T=$(cd "$T" && pwd -P) || exit 1
trap 'rm -rf "$T"' EXIT
. tests/lib.sh
. tests/compare.sh
APP=$(built_app "$T") || exit 1

# A page a session wrote, with a file beside it, one in a folder in it, and a link in it to a folder beside it; that
# folder, and one named like the page's, are outside it.
mkdir -p "$T/home/work/site/sub" "$T/home/work/outside" "$T/home/work/site-other"
for file in site/page.html site/beside.html site/sub/inner.html outside/secret.html site-other/page.html; do
  echo '<p>A sample page.</p>' > "$T/home/work/$file"
done
ln -s ../outside "$T/home/work/site/link"

out=$(HOME="$T/home" "$APP" --print-browsing "$T/home/work/site" 2>&1 | sed -e "s|$T|T|g")
compare "The browser's rules" tests/browser.expected.txt "$out" "${1:-}"
