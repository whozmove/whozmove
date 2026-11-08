# Shared by the tests: compares a test's output with its recorded copy, or with --update saves the output as the
# new copy.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# After `. tests/compare.sh`:  compare <name> <expected file> "$out" "${1:-}"
compare() {
  local name=$1 expected=$2 out=$3 mode=$4
  if [ "$mode" = "--update" ]; then
    printf '%s\n' "$out" > "$expected"
    echo "Saved $expected"
    return
  fi
  # Through a file in the temporary folder rather than <(…) or a pipe: Claude Code's sandbox refuses /dev/fd, where
  # diff would read both from.
  local got status=0
  got=$(mktemp "${TMPDIR:-/tmp}/wz-compare.XXXXXX") || return 1
  printf '%s\n' "$out" > "$got"
  if diff -u --label "$expected" --label "$name" "$expected" "$got"; then
    echo "$name: all as expected."
  else
    echo "$name: output changed (above). If the change is intended: $0 --update"
    status=1
  fi
  rm -f "$got"
  return $status
}
