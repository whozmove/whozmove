#!/bin/bash
# Makes a release of Whozmove: the app for Apple silicon, checked, zipped into dist/, unpacked and checked again. It
# prints the zip's sha256 and the Homebrew cask's two lines for it, and publishes nothing. The release workflow
# (.github/workflows/release.yml) runs it for a pushed tag; run it here to try a release first.
#   tools/release.sh <version>            from a checkout with no changes, whose app/Info.plist says <version> and
#                                         whose CHANGELOG has a ## <version> section: dist/Whozmove-<version>.zip
#   tools/release.sh <version> --trial    from any checkout, whatever its version says: dist/Whozmove-<version>-trial.zip,
#                                         with <version> written into the app, for trying it before a release
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "$(dirname "$0")/.."
. tools/bundle.sh

version= trial=no
for arg in "$@"; do
  case $arg in
    --trial) trial=yes ;;
    -*) echo "Unknown option: $arg (there's only --trial)"; exit 2 ;;
    *) [ -z "$version" ] || { echo "One version only, not $version and $arg"; exit 2; }; version=$arg ;;
  esac
done
[ -n "$version" ] || { echo "Usage: tools/release.sh <version> [--trial]"; exit 2; }
# Three numbers, as Info.plist and the cask write it: it names files here and the tag on GitHub.
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "$version isn't a version: it's three numbers, as 0.2.0"; exit 2; }

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1"; }
name=$(plist app/Info.plist CFBundleName); bundle_id=$(plist app/Info.plist CFBundleIdentifier)
exe=$(plist app/Info.plist CFBundleExecutable); oldest=$(plist app/Info.plist LSMinimumSystemVersion)
base=$(plutil -extract version raw -o - modules/claude-code/plugin/.claude-plugin/plugin.json)

# A release goes out only as the release commit made it: everything in it says this version, its notes are written,
# and nothing in the checkout differs from the commit. A trial is for trying a build before that commit exists.
# Each refusal says what to change, and that a trial needs none of it.
notes=
refuse() { echo "$1"; echo "Or try a build first: tools/release.sh $version --trial"; exit 1; }
if [ "$trial" = no ]; then
  for key in CFBundleShortVersionString CFBundleVersion; do
    said=$(plist app/Info.plist $key)
    [ "$said" = "$version" ] || refuse "app/Info.plist's $key says $said, not $version: set it to $version."
  done
  [ "$base" = "$version" ] ||
    refuse "modules/claude-code/plugin/.claude-plugin/plugin.json says version $base, not $version: set it to $version."
  # The notes are the CHANGELOG's ## <version> section (its heading may carry the date after it), up to the next one.
  notes=$(VERSION=$version awk '$1 == "##" { on = ($2 == ENVIRON["VERSION"]); next } on' CHANGELOG.md)
  grep -q '[^[:space:]]' <<<"$notes" ||
    refuse "CHANGELOG.md has no ## $version section with notes in it: name the Unreleased section ## $version."
  changes=$(git status --porcelain)
  if [ -n "$changes" ]; then
    echo "$changes"
    refuse "The checkout has the changes above, so a release would differ from its commit: commit them first."
  fi
fi

zip_name=$name-$version.zip
[ "$trial" = no ] || zip_name=$name-$version-trial.zip
mkdir -p dist
rm -rf dist/check "dist/$zip_name"
work=$(mktemp -d "${TMPDIR:-/tmp}/$exe-release.XXXXXX")
trap 'rm -rf "$work"' EXIT
app="$work/$name.app"

# The program for Apple silicon only, every warning an error, for the oldest macOS Info.plist names
# (tools/compile.sh). Unlike build.sh's, a release carries no build.json: it would name the folder it was built in, and
# a release is named by its version.
make_bundle "$app" -arch arm64 -Werror
if [ "$trial" = yes ]; then
  plutil -replace CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
  plutil -replace CFBundleVersion -string "$version" "$app/Contents/Info.plist"
fi
sign_bundle "$app"

# What every copy of a release must be, checked on the build and again on the copy unpacked from its zip.
check() {
  local app=$1 program=$1/Contents/MacOS/$exe said hooks
  codesign --verify --strict "$app" || { echo "$app: its signature doesn't hold"; return 1; }
  # Privacy grants (Accessibility) are kept by this requirement, so every release must have the same one.
  said=$(codesign --display --requirements - "$app" 2>/dev/null | sed -n 's/^designated => //p')
  [ "$said" = "identifier \"$bundle_id\"" ] || { echo "$app: its requirement is '$said'"; return 1; }
  said=$(lipo -archs "$program")
  [ "$said" = arm64 ] || { echo "$app: its program is for $said, not Apple silicon alone"; return 1; }
  said=$(vtool -show-build "$program" | awk '$1 == "minos" { print $2 }')
  [ "$said" = "$oldest" ] || { echo "$app: its program asks for macOS $said, not $oldest"; return 1; }
  said=$(plist "$app/Contents/Info.plist" CFBundleShortVersionString)
  [ "$said" = "$version" ] || { echo "$app: its Info.plist says $said, not $version"; return 1; }
  # The hooks, exactly as this checkout's plugin makes them, with the version that names their contents. plutil writes
  # plugin.json's keys in any order, so that file is compared by what it holds.
  hooks=$(mktemp -d "$work/hooks.XXXXXX")
  copy_plugin "$hooks"
  diff -r -x plugin.json "$hooks" "$app/Contents/Resources/plugin" >/dev/null &&
    cmp -s <(plutil -convert xml1 -o - "$hooks/.claude-plugin/plugin.json") \
      <(plutil -convert xml1 -o - "$app/Contents/Resources/plugin/.claude-plugin/plugin.json") ||
    { echo "$app: the hooks inside differ from this checkout's"; return 1; }
  # Nothing in it names the folder it was built in, or whose Mac it was.
  ! grep -rqF "$HOME" "$app" || { echo "$app: it names $HOME"; return 1; }
}
check "$app"

# Zipped as macOS keeps an app, without the marks macOS adds to files (as ._ entries, which a plain unzip would put in
# the bundle, breaking its signature), then unpacked and checked again: that copy stays in dist/check, and the release
# workflow runs the tests on its program.
ditto -c -k --norsrc --noextattr --keepParent "$app" "dist/$zip_name"
ditto -x -k "dist/$zip_name" dist/check
check "dist/check/$name.app"
if [ -n "$notes" ]; then printf '%s\n' "$notes" | sed '/./,$!d' >"dist/$name-$version-notes.md"; fi

sha=$(shasum -a 256 "dist/$zip_name" | cut -d' ' -f1)
hooks=$(plutil -extract version raw -o - "dist/check/$name.app/Contents/Resources/plugin/.claude-plugin/plugin.json")
echo "Made dist/$zip_name: $name $version, for Apple silicon, macOS $oldest and later, with hooks $hooks"
echo "sha256 $sha"
echo
echo "The cask's two lines (Casks/whozmove.rb in the tap):"
echo "  version \"$version\""
echo "  sha256 \"$sha\""
