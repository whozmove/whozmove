#!/bin/bash
# Makes a release of Whozmove: the app for Apple silicon, signed with the Developer ID, checked, notarised by Apple,
# zipped into dist/, unpacked and checked again. It prints the zip's sha256 and the Homebrew cask's two lines for it,
# and publishes nothing. The release workflow (.github/workflows/release.yml) runs it for a pushed tag, with the
# certificate and the notarising key it holds; run it here to try a release first, signed with your own Developer ID
# if you've set one up (tools/signing.sh) and not notarised, or ad hoc.
#   tools/release.sh <version>            in the release workflow, from a checkout with no changes, whose
#                                         app/Info.plist says <version> and whose CHANGELOG has a ## <version>
#                                         section: dist/Whozmove-<version>.zip
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
  # Keys looks with the Betterleaks tools/betterleaks.txt names for releases: a finished version, never a release
  # candidate, and the one every build carries, so what was tried is what ships.
  scanner=$(tools/betterleaks.sh --version --release)
  [[ $scanner =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    refuse "tools/betterleaks.txt's release line names Betterleaks $scanner, not a finished version: name one."
  built=$(tools/betterleaks.sh --version)
  [ "$built" = "$scanner" ] ||
    refuse "tools/betterleaks.txt's build line names Betterleaks $built, not the release's $scanner: make them one."
  changes=$(git status --porcelain)
  if [ -n "$changes" ]; then
    echo "$changes"
    refuse "The checkout has the changes above, so a release would differ from its commit: commit them first."
  fi
fi

# Who signs it. In the release workflow, the Developer ID in the keychain it made for the run
# (WHOZMOVE_SIGNING_KEYCHAIN), with a secure timestamp, then notarised by Apple with the key it put beside it
# (NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID), for the team APPLE_TEAM_ID names. In your terminal, your own
# Developer ID (tools/signing.sh), not notarised. For an agent, or with no certificate, no one: ad hoc. A release is
# only ever the first; a trial is whichever it can be, and is checked for what it is.
keychain=${WHOZMOVE_SIGNING_KEYCHAIN:-} identity= notarise=no team=${APPLE_TEAM_ID:-}
if [ -n "$keychain" ]; then
  identity=$(security find-identity -v -p codesigning "$keychain" 2>/dev/null |
    awk '/"Developer ID Application: / { print $2; exit }')
  [ -n "$identity" ] || { echo "The release workflow's keychain holds no Developer ID certificate that works."; exit 1; }
  [ -n "${NOTARY_KEY_PATH:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER_ID:-}" ] && [ -n "$team" ] ||
    { echo "The release workflow gave no notarising sign-in, or no team: see its secrets."; exit 1; }
  notarise=yes
else
  identity=$(signing_identity) || { status=$?; [ $status = 2 ] && { echo "$identity"; exit 1; }; identity=; }
  [ -z "$identity" ] || keychain=$signing_keychain
fi
[ "$trial" = yes ] || [ "$notarise" = yes ] ||
  refuse "A release is signed with the Developer ID and notarised by Apple, which the release workflow does: push its tag."

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
betterleaks_for=release make_bundle "$app" -arch arm64 -Werror
if [ "$trial" = yes ]; then
  plutil -replace CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
  plutil -replace CFBundleVersion -string "$version" "$app/Contents/Info.plist"
fi
if [ "$notarise" = yes ]; then
  sign_bundle "$app" "$identity" "$keychain" release
elif [ -n "$identity" ]; then
  # Your signing keychain is locked again as soon as signing ends, however it ends (tools/signing.sh).
  trap 'lock_signing; rm -rf "$work"' EXIT
  echo "Signing with your Developer ID: macOS asks for your signing keychain's password a few times now, as it signs"
  echo "Betterleaks and Whozmove. Press Allow each time, never Always Allow."
  sign_bundle "$app" "$identity" "$keychain" ||
    { echo "Signing wasn't allowed, so nothing was made: run it again to try again."; exit 1; }
  lock_signing
  # The team the rule names, as its certificate says it: a trial of yours is checked for your own.
  team=$(codesign --display --verbose "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p')
else
  sign_bundle "$app"
fi

# Whether the signed program or bundle $1 asks for exactly the entitlements the list $2 holds, no more and no fewer;
# with no list, for none at all.
asks_exactly() {
  codesign --display --entitlements - --xml "$1" >"$work/entitlements.plist" 2>/dev/null
  if [ -z "${2:-}" ]; then
    [ ! -s "$work/entitlements.plist" ] && return 0
    echo "$1: it asks for entitlements, and should ask for none"
    return 1
  fi
  python3 - "$work/entitlements.plist" "$2" <<'PY' && return 0
import plistlib, sys
try:
    signed, listed = (plistlib.load(open(path, "rb")) for path in sys.argv[1:])
except (OSError, plistlib.InvalidFileException, ValueError):
    sys.exit(1)
sys.exit(0 if signed == listed else 1)
PY
  echo "$1: its entitlements aren't exactly $2"
  return 1
}

# What every copy of a release must be, checked on the build and again on the copy unpacked from its zip.
check() {
  local app=$1 program=$1/Contents/MacOS/$exe said hooks inside
  codesign --verify --strict "$app" || { echo "$app: its signature doesn't hold"; return 1; }
  # Privacy grants (Accessibility) are kept by this requirement, so every release must have the same one: signed with
  # a Developer ID, Apple's own rule for it, naming the team; ad hoc, the bundle id alone. Compared without printing
  # it, as it names the team.
  said=$(codesign --display --requirements - "$app" 2>/dev/null | sed -n 's/^designated => //p' | tr -d '"')
  if [ -n "$identity" ]; then
    [ "$said" = "identifier $bundle_id and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = $team" ] ||
      { echo "$app: its requirement isn't Apple's Developer ID rule for the team it's signed for"; return 1; }
  else
    [ "$said" = "identifier $bundle_id" ] || { echo "$app: its requirement is '$said'"; return 1; }
  fi
  # Every program in it runs with the hardened runtime, Whozmove asks for exactly what tools/Whozmove.entitlements
  # lists, and Betterleaks for nothing (tools/bundle.sh): one more would let macOS hold back less, and one missing would
  # stop what it's there for.
  for inside in "$app"/Contents/MacOS/* "$app"/Contents/Helpers/*; do
    # Read whole before it's matched: under pipefail, grep -q stopping early would fail the pipe.
    said=$(codesign --display --verbose "$inside" 2>&1)
    grep -q '^CodeDirectory .*flags=0x[0-9a-f]*([^)]*runtime' <<<"$said" ||
      { echo "$app: $(basename "$inside") doesn't run with the hardened runtime"; return 1; }
    # One Apple notarises carries, in each program's signature, the time Apple's server gave it.
    if [ "$notarise" = yes ]; then
      said=$(codesign --display --verbose=2 "$inside" 2>&1)
      grep -q '^Timestamp=' <<<"$said" || { echo "$app: $(basename "$inside") has no secure timestamp"; return 1; }
    fi
  done
  asks_exactly "$app" tools/Whozmove.entitlements || return 1
  asks_exactly "$app/Contents/Helpers/betterleaks" || return 1
  # Notarised: macOS takes it as Apple's notary service passed it, and the ticket that says so is stapled to it, so a
  # Mac offline opens it too.
  if [ "$stapled" = yes ]; then
    said=$(spctl --assess --type execute --verbose=2 "$app" 2>&1) || true
    grep -q 'source=Notarized Developer ID' <<<"$said" || { echo "$app: macOS doesn't take it as notarised"; return 1; }
    xcrun stapler validate -q "$app" >/dev/null 2>&1 || { echo "$app: its notarisation isn't stapled to it"; return 1; }
  fi
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
  # Betterleaks, signed, for Apple silicon, and the version tools/betterleaks.txt names for releases.
  helper=$app/Contents/Helpers/betterleaks
  codesign --verify --strict "$helper" 2>/dev/null || { echo "$app: Betterleaks inside isn't signed"; return 1; }
  said=$(lipo -archs "$helper")
  [ "$said" = arm64 ] || { echo "$app: Betterleaks inside is for $said, not Apple silicon alone"; return 1; }
  said=$("$helper" version 2>/dev/null)
  [ "$said" = "$(tools/betterleaks.sh --version --release)" ] ||
    { echo "$app: Betterleaks inside is $said, not the one tools/betterleaks.txt names for releases"; return 1; }
  # Nothing in it names the folder it was built in, or whose Mac it was.
  ! grep -rqF "$HOME" "$app" || { echo "$app: it names $HOME"; return 1; }
}
stapled=no
check "$app"

# Notarised: sent to Apple's notary service as a zip, waited for (usually a few minutes), and the ticket stapled to the
# app. Apple's answer is printed as its submission's id, its status and each issue its log names (Apple's words and
# the file in the bundle), so a run that's thrown away after says why; what else notarytool and stapler print stays in
# files, as it can name the team. The submission's id is what `xcrun notarytool log` takes to fetch the log again.
if [ "$notarise" = yes ]; then
  ditto -c -k --norsrc --noextattr --keepParent "$app" "$work/notarise.zip"
  echo "Sent to Apple to be notarised; waiting for its answer."
  xcrun notarytool submit "$work/notarise.zip" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" --wait --timeout 1h --output-format json >"$work/notarised.json" 2>"$work/notary.err" ||
    true
  answer() { python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))' \
    "$work/notarised.json" "$1" 2>/dev/null || true; }
  submission=$(answer id)
  said=$(answer status)
  log="dist/$name-$version-notary-log.json"
  [ -z "$submission" ] || xcrun notarytool log "$submission" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" "$log" >/dev/null 2>&1 || true
  echo "Apple's answer: ${said:-none}${submission:+, submission $submission}"
  python3 - "$log" <<'PY' || true
import json, sys
try:
    issues = json.load(open(sys.argv[1])).get("issues") or []
except (OSError, ValueError):
    sys.exit()
for issue in issues[:20]:
    print("  %s: %s" % (issue.get("severity", "issue"), issue.get("message", "")))
    print("    in %s" % issue.get("path", "?"))
if len(issues) > 20:
    print("  and %d more" % (len(issues) - 20))
PY
  if [ -z "$submission" ]; then
    echo "notarytool said:"
    tail -5 "$work/notary.err" | sed 's/^/  /'
  fi
  [ "$said" = Accepted ] || { echo "Apple didn't notarise it: what its log says is above."; exit 1; }
  xcrun stapler staple -q "$app" >/dev/null 2>&1 || { echo "Apple notarised it, but its ticket wouldn't staple."; exit 1; }
  stapled=yes
  check "$app"
fi

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
if [ "$stapled" = yes ]; then echo "Signed with the Developer ID, notarised by Apple, its ticket stapled"
elif [ -n "$identity" ]; then echo "Signed with your Developer ID, not notarised (a trial made here)"
else echo "Signed ad hoc (no Developer ID here)"; fi
echo "sha256 $sha"
echo
echo "The cask's two lines (Casks/whozmove.rb in the tap):"
echo "  version \"$version\""
echo "  sha256 \"$sha\""
