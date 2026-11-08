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
  # Each fetch is tried up to four times, whatever went wrong: GitHub sometimes answers a release download with an
  # error (a 504), which curl alone wouldn't try again. The SHA-256 below checks whatever arrives.
  fetch() { curl -fsSL --proto =https --retry 3 --retry-all-errors --retry-delay 3 "$@"; }
  if ! fetch -o "$part" "$url"; then
    # GitHub's release download address can keep failing for one file while its API still gives the same file, so
    # the release's list of files is read there, and this one fetched by its id. On GitHub Actions, the run's own
    # token is sent to the API, as an address shared by many runs soon runs out of unsigned requests; curl sends it to
    # the API alone, never to where the file's address leads.
    echo "Betterleaks' download address failed; fetching the same file through GitHub's API." >&2
    api=https://api.github.com/repos/betterleaks/betterleaks/releases
    auth=()
    if [ "${GITHUB_ACTIONS:-}" = true ] && [ -n "${GITHUB_TOKEN:-}" ]; then
      auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
    fi
    listed=$(mktemp "$download.XXXXXX")
    fetch ${auth[@]+"${auth[@]}"} -H "Accept: application/vnd.github+json" -o "$listed" "$api/tags/v$version" \
      || { rm -f "$part" "$listed"; echo "Couldn't download $url, nor read its release in GitHub's API." >&2; exit 1; }
    name=${url##*/} id= i=0
    while each=$(plutil -extract "assets.$i.name" raw -o - "$listed" 2>/dev/null); do
      if [ "$each" = "$name" ]; then
        id=$(plutil -extract "assets.$i.id" raw -o - "$listed" 2>/dev/null) || id=
        break
      fi
      i=$((i + 1))
    done
    rm -f "$listed"
    case $id in
      '' | *[!0-9]*)
        rm -f "$part"
        echo "Couldn't download $url, and its release on GitHub doesn't list it." >&2
        exit 1 ;;
    esac
    fetch ${auth[@]+"${auth[@]}"} -H "Accept: application/octet-stream" -o "$part" "$api/assets/$id" \
      || { rm -f "$part"; echo "Couldn't download $url, nor through GitHub's API." >&2; exit 1; }
  fi
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
