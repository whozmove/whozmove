#!/bin/bash
# Puts a Claude Code program in a folder, for the real Claude Code run (real.sh, beside this file), and never
# runs it. The program is fetched once from Anthropic's own release folder into a cache outside the checkout
# ($WHOZMOVE_BUILD_CACHE, else ~/Library/Caches/Whozmove-build), and checked each time it's used: its SHA-256 (the
# version claude-code.txt pins against the sum written there, any other against its release's manifest), and that
# Anthropic signed it. One that fails either is deleted, and nothing is put in the folder. The official installer
# isn't used: it also sets the program up as the home folder's own Claude Code (a launcher, the shell's profile),
# which a check has no use for.
# From the checkout's top, with the folder's path:
#   modules/claude-code/tests/claude-code.sh <folder>                 the version Whozmove was last checked with
#                                                                     (`checked`); prints the program's path
#   modules/claude-code/tests/claude-code.sh --newest <folder>        the newest version out
#   modules/claude-code/tests/claude-code.sh --at <version> <folder>  that version
#   modules/claude-code/tests/claude-code.sh --version [--newest]     prints that version, and puts nothing anywhere
#   modules/claude-code/tests/claude-code.sh --cache-folder           prints where the downloads are kept, for a cache
#                                                                     kept between runs (CI's), asking nothing
#   --arch arm64|x86_64 with a folder: for that kind of Mac, else this Mac's
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
# Into the sandbox before anything else: with every option still there for it to start again with, before set -e,
# which would end the run at the refusal sandboxed.sh expects inside a sandbox already, and before a folder is made.
# Then back where it was started from, so a folder given by a relative path is read from there.
cd "$(dirname "$0")" || exit 1
. ../../../tests/sandboxed.sh --downloads "$@"
cd "$OLDPWD" || exit 1
set -euo pipefail
which=checked only_version=no only_cache=no folder= arch= version=
while [ $# -gt 0 ]; do
  case $1 in
    --newest) which=newest ;;
    --at) shift; which=at; version=${1:-} ;;
    --version) only_version=yes ;;
    --cache-folder) only_cache=yes ;;
    --arch) shift; arch=${1:-} ;;
    *) folder=$(mkdir -p "$1" && cd "$1" && pwd -P) ;;
  esac
  shift
done
cd "$(dirname "$0")" || exit 1
cache=${WHOZMOVE_BUILD_CACHE:-$HOME/Library/Caches/Whozmove-build}
if [ "$only_cache" = yes ]; then echo "$cache"; exit 0; fi
releases=https://downloads.claude.ai/claude-code-releases
case $which in
  checked) version=$(awk '$1 == "checked" { print $2 }' claude-code.txt) ;;
  newest) version=$(curl -fsSL --retry 2 "$releases/latest") ||
            { echo "Couldn't ask which version is newest" >&2; exit 1; } ;;
esac
# Only a version number goes into an address: an error page in place of one stops here.
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Not a Claude Code version: ${version:-nothing}" >&2; exit 1; }
if [ "$only_version" = yes ]; then echo "$version"; exit 0; fi
[ -n "$folder" ] || { echo "Usage: claude-code.sh [--newest | --at <version>] <folder>" >&2; exit 2; }
[ -n "$arch" ] || arch=$(uname -m)
case $arch in
  arm64) platform=darwin-arm64 ;;
  x86_64) platform=darwin-x64 ;;
  *) echo "There's no Claude Code for $arch Macs." >&2; exit 1 ;;
esac
sum=$(awk -v version="$version" -v arch="$arch" '$1 == version && $2 == arch { print $3 }' claude-code.txt)
if [ -z "$sum" ]; then
  # A version the file doesn't pin is checked against the sum its own release gives.
  sum=$(curl -fsSL --retry 2 "$releases/$version/manifest.json" | python3 -I -c '
import json, sys
print(json.load(sys.stdin)["platforms"][sys.argv[1]]["checksum"])' "$platform") ||
    { echo "Couldn't read Claude Code $version's manifest" >&2; exit 1; }
fi
[[ $sum =~ ^[0-9a-f]{64}$ ]] || { echo "No SHA-256 for Claude Code $version on $arch" >&2; exit 1; }
download="$cache/claude-code-$version-$platform"
mkdir -p "$cache"
if [ ! -f "$download" ]; then
  # Into a file of this run's own, then moved into place whole, so two runs at once never write into one download.
  part=$(mktemp "$download.XXXXXX")
  curl -fsSL --retry 2 -o "$part" "$releases/$version/$platform/claude" ||
    { rm -f "$part"; echo "Couldn't download Claude Code $version" >&2; exit 1; }
  mv "$part" "$download"
fi
got=$(shasum -a 256 "$download" | awk '{ print $1 }')
if [ "$got" != "$sum" ]; then
  rm -f "$download"
  echo "Claude Code $version's download isn't the one its release names (its SHA-256 is $got): deleted." >&2
  exit 1
fi
# And signed by Anthropic, whatever the sums say: a forged certificate can hand macOS's curl a forged manifest too.
if ! codesign --verify --strict -R='anchor apple generic and certificate leaf[subject.OU] = "Q6L2SF6YDW"' \
     "$download" 2>/dev/null; then
  rm -f "$download"
  echo "Claude Code $version's download isn't signed by Anthropic: deleted." >&2
  exit 1
fi
mkdir -p "$folder"
cp "$download" "$folder/claude"
chmod 755 "$folder/claude"
echo "$folder/claude"
