#!/bin/bash
# Puts the Betterleaks that tools/betterleaks.txt names, and its licence, in a folder: the one program Whozmove carries
# that isn't its own, which Keys looks for keys with. Its release's download is fetched once into a cache outside the
# checkout ($WHOZMOVE_BUILD_CACHE, else ~/Library/Caches/Whozmove-build), and checked against its SHA-256 each time
# it's used: one that doesn't match is deleted, and nothing is put in the folder.
#   tools/betterleaks.sh <folder>             the version every build carries (`build`); prints the path put there
#   tools/betterleaks.sh --release <folder>   the version a release carries (`release`)
#   tools/betterleaks.sh --next <folder>      the version being readied (`next`), for Keys' tests
#   tools/betterleaks.sh --version [--release | --next]   prints that version, and puts nothing anywhere
#   --arch arm64|x86_64 with a folder: for that kind of Mac (the build's own, from make_bundle), else this Mac's
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
which=build only_version=no folder= arch=
while [ $# -gt 0 ]; do
  case $1 in
    --release) which=release ;;
    --next) which=next ;;
    --version) only_version=yes ;;
    --arch) shift; arch=${1:-} ;;
    *) folder=$1 ;;
  esac
  shift
done
cd "$(dirname "$0")/.."
version=$(awk -v which="$which" '$1 == which { print $2 }' tools/betterleaks.txt)
[ -n "$version" ] || { echo "tools/betterleaks.txt doesn't name a $which version." >&2; exit 1; }
if [ "$only_version" = yes ]; then echo "$version"; exit 0; fi
[ -n "$folder" ] || { echo "Usage: tools/betterleaks.sh [--release] <folder>" >&2; exit 2; }
[ -n "$arch" ] || arch=$(uname -m)
sum=$(awk -v version="$version" -v arch="$arch" '$1 == version && $2 == arch { print $3 }' tools/betterleaks.txt)
case $arch in
  arm64) asset=arm64 ;;
  x86_64) asset=x64 ;;
  *) echo "There's no Betterleaks for $arch Macs." >&2; exit 1 ;;
esac
[ -n "$sum" ] || { echo "tools/betterleaks.txt has no checksum for Betterleaks $version on $arch." >&2; exit 1; }
cache=${WHOZMOVE_BUILD_CACHE:-$HOME/Library/Caches/Whozmove-build}
download="$cache/betterleaks_${version}_darwin_$asset.tar.gz"
mkdir -p "$cache"
if [ ! -f "$download" ]; then
  # Into a file of this run's own, then moved into place whole, so two builds at once never write into one download.
  url="https://github.com/betterleaks/betterleaks/releases/download/v$version/betterleaks_${version}_darwin_$asset.tar.gz"
  part=$(mktemp "$download.XXXXXX")
  # Tried up to four times, whatever went wrong: GitHub sometimes answers a release download with an error once (a
  # 504), which curl alone wouldn't try again. The SHA-256 below checks whatever arrives.
  curl -fsSL --retry 3 --retry-all-errors --retry-delay 3 -o "$part" "$url" \
    || { rm -f "$part"; echo "Couldn't download $url" >&2; exit 1; }
  mv "$part" "$download"
fi
got=$(shasum -a 256 "$download" | awk '{ print $1 }')
if [ "$got" != "$sum" ]; then
  rm -f "$download"
  echo "Betterleaks' download isn't the one tools/betterleaks.txt names (its SHA-256 is $got): deleted." >&2
  exit 1
fi
mkdir -p "$folder"
tar -xzf "$download" -C "$folder" betterleaks LICENSE
chmod 755 "$folder/betterleaks"
echo "$folder/betterleaks"
