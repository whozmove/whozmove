#!/bin/bash
# The app's one compile line, for build.sh, the tests (tests/lib.sh) and CI: every .m under app/ and modules/.
# Only the core's, the contracts' and the shared helpers' folders are on the include path (a module's own headers are
# found beside its code), so a module can't import another module's header. Prints nothing unless clang has something
# to say.
#   tools/compile.sh <output> [clang options…]     e.g. -Werror (CI) or -O0 (the tests)
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
here=$PWD
cd "$(dirname "$0")/.."
# The output path is taken from where this was run, not from the repo it compiles.
out=$1
case $out in /*) ;; *) out=$here/$out ;; esac
shift
roots=()
for root in app modules; do [ -d "$root" ] && roots+=("$root"); done
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find "${roots[@]}" -name '*.m' | LC_ALL=C sort)
includes=()
for folder in app app/core app/contracts app/shared; do [ -d "$folder" ] && includes+=("-I$folder"); done
# The oldest macOS the app says it runs on (Info.plist's LSMinimumSystemVersion), so a call newer than that, made
# without checking for it, is a warning here (an error in CI) rather than a crash on that Mac. Left out, the compiler
# would take this Mac's own version, and the app wouldn't open on anything older.
oldest=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" app/Info.plist)
clang -O2 -Wall -fobjc-arc -framework Cocoa -framework WebKit -framework JavaScriptCore -framework QuartzCore \
  -framework Carbon -mmacosx-version-min="$oldest" "${includes[@]}" "$@" "${sources[@]}" -o "$out"
