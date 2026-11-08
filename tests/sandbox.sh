#!/bin/bash
# What the sandbox every test runs in (tests/sandboxed.sh) lets a test reach over a Unix socket: one in a folder of its
# own (wz- in /tmp, whozmove- in the temporary folder), and none in a folder it may write in that isn't its own (the
# caches), so none anywhere else either: not the panel's, nor a session's in /tmp/cc-socks, which this never tries, as
# reaching one would send that session words. Each socket is nc's, listening; each connection, nc's too. Compared with
# tests/sandbox.expected.txt.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the difference and exits 1 if anything changed.
#   tests/sandbox.sh            run and compare
#   tests/sandbox.sh --update   run and save the output as the new expected (after a change you meant)
cd "$(dirname "$0")/.." || exit 1
. tests/sandboxed.sh "$@"
. tests/compare.sh
# In a sandbox not its own (Claude Code's), what it lets through is that sandbox's to say, not this one's.
if [ "$WHOZMOVE_TEST_SANDBOX" = outer ]; then
  echo "The tests' sandbox: couldn't run here, as it runs in a sandbox not its own"
  exit 1
fi
# Stops here if there's no temporary folder: an empty folder would make the clean-up below delete this checkout.
S=$(mktemp -d /tmp/wz-sandbox.XXXXXX) || exit 1
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-sandbox-check.XXXXXX") || exit 1
O=$(mktemp -d "$(getconf DARWIN_USER_CACHE_DIR)outside-sandbox-check.XXXXXX") || exit 1
trap 'rm -rf "$S" "$T" "$O"' EXIT

# Whether a socket at `path` can be reached: nc listens there, and another nc says hello to it.
reach() {
  /usr/bin/nc -lU "$1" > "$1.got" 2>/dev/null & local listening=$!
  for _ in $(seq 1 50); do [ -S "$1" ] && break; sleep 0.1; done
  echo hello | /usr/bin/nc -U -w 2 "$1" 2>/dev/null
  sleep 0.2
  kill $listening 2>/dev/null; wait $listening 2>/dev/null
  if [ "$(cat "$1.got" 2>/dev/null)" = hello ]; then echo reached; else echo refused; fi
}

out=$({
echo "A socket in a test's own folder in /tmp: $(reach "$S/s")"
echo "A socket in a test's own folder in the temporary folder: $(reach "$T/s")"
echo "A socket in a folder a test may write in, but not its own: $(reach "$O/s")"
})
compare "The tests' sandbox" tests/sandbox.expected.txt "$out" "${1:-}"
