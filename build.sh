#!/bin/bash
# Builds ~/Applications/Whozmove.app from app/, panel/ and icon/. Run again after editing any of them.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "$(dirname "$0")"

# The app's name, bundle id and executable are written down once, in app/Info.plist; this and install.sh read
# them from there, so a rename can't leave a stale copy behind (a stale signing id would quietly lose the
# Accessibility grant; a stale job label would stop the restart below).
plist() { /usr/libexec/PlistBuddy -c "Print :$1" app/Info.plist; }
name=$(plist CFBundleName); bundle_id=$(plist CFBundleIdentifier); exe=$(plist CFBundleExecutable)
app="$HOME/Applications/$name.app"
# Built aside and swapped in only once it's complete, so a failed build leaves the working app in place.
work=$(mktemp -d "${TMPDIR:-/tmp}/$exe.XXXXXX")
trap 'rm -rf "$work"' EXIT
new="$work/$name.app"
mkdir -p "$new/Contents/MacOS" "$new/Contents/Resources"
cp app/Info.plist "$new/Contents/"
cp icon/AppIcon.icns "$new/Contents/Resources/"
cp -R panel "$new/Contents/Resources/panel"
clang -O2 -Wall -fobjc-arc -framework Cocoa -framework WebKit -framework JavaScriptCore app/*.m \
  -o "$new/Contents/MacOS/$exe"
# Ad-hoc signed, but with the bundle id as its designated requirement: macOS keys privacy grants
# (Accessibility, for the Claude Desktop message box) to that, so a rebuild doesn't lose them. By default an
# ad-hoc signature's requirement is the exact build's hash. The catch: any ad-hoc signed app claiming this
# id would match it too. Signing with a certificate of your own (and its requirement) closes that.
codesign --force --sign - -r="designated => identifier \"$bundle_id\"" "$new"
mkdir -p "$HOME/Applications"
rm -rf "$app"
mv "$new" "$app"
# Re-register so Finder, Spotlight and the Dock pick up the icon of the fresh bundle.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -f "$app" || true
echo "Built $app"

# If the login item (./install.sh) is set up, restart it on the new build.
job="gui/$(id -u)/$bundle_id"
if launchctl print "$job" >/dev/null 2>&1; then
  launchctl kickstart -k "$job"
  echo "Restarted $name"
fi
