# Whozmove's app bundle: what goes in it, and its signature. Sourced by build.sh and tools/release.sh, from the
# checkout's root.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Every bundle is made here, so each one carries the same parts, its hooks among them: they go in with the app, and
# are sealed in its signature with the rest.
. modules/claude-code/plugin.sh

# The bundle $1, made from this checkout: its Info.plist and icon, the page with each module's page files listed in it
# (tools/page.sh), swap-in.sh, the hooks as the Claude Code plugin, with the version that names their contents
# (Contents/Resources/plugin), and the program (tools/compile.sh, with the options after $1).
make_bundle() {
  local app=$1 exe
  shift
  exe=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" app/Info.plist)
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cp app/Info.plist "$app/Contents/"
  cp icon/AppIcon.icns "$app/Contents/Resources/"
  tools/page.sh "$app/Contents/Resources/panel"
  cp app/swap-in.sh "$app/Contents/Resources/"
  copy_plugin "$app/Contents/Resources/plugin"
  tools/compile.sh "$app/Contents/MacOS/$exe" "$@"
}

# Signs the bundle $1, once nothing more goes in it: a file added after the signature breaks it. Ad-hoc signed, but
# with the bundle id as its designated requirement: macOS keys privacy grants (Accessibility, for the Claude Desktop
# message box) to that, so a rebuild doesn't lose them. By default an ad-hoc signature's requirement is the exact
# build's hash. The catch: any ad-hoc signed app claiming this id would match it too. Signing with a certificate of
# your own (and its requirement) closes that. Its files' extended attributes are cleared first: cp and install copy
# them with the files, and codesign refuses a bundle with Finder information in it (a file's colour tag, say).
sign_bundle() {
  local id
  id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$1/Contents/Info.plist")
  xattr -cr "$1"
  codesign --force --sign - -r="designated => identifier \"$id\"" "$1"
}
