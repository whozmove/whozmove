#!/bin/bash
# Diagrams, their tests: a ```mermaid block read (a flow only when every part of it is read), what it says in words, a
# flow laid out and drawn with every word escaped, and the figure with Diagram and As written (page-cases.js, run with
# macOS's jsc in UTC, compared with page.expected.txt).
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   modules/diagrams/tests/test.sh            run and compare
#   modules/diagrams/tests/test.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/../../.." || exit 1
. tests/sandboxed.sh "$@"
HERE=modules/diagrams/tests
. tests/lib.sh
. tests/compare.sh

page=$(page_cases "$HERE/page-cases.js") || { echo "$page"; exit 1; }
compare "Diagrams" "$HERE/page.expected.txt" "$page" "${1:-}"
