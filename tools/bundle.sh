# Whozmove's app bundle: what goes in it, and its signature. Sourced by build.sh and tools/release.sh, from the
# checkout's root.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Every bundle is made here, so each one carries the same parts, its hooks among them: they go in with the app, and
# are sealed in its signature with the rest.
. modules/claude-code/plugin.sh

# The bundle $1, made from this checkout: its Info.plist and icon, the page with each module's page files listed in it
# (tools/page.sh), swap-in.sh, ask-panel.sh (what a session asks the panel), the hooks as the Claude Code plugin, with
# the version that names their contents (Contents/Resources/plugin), Betterleaks, which Keys looks with
# (Contents/Helpers, its licence in Resources: tools/betterleaks.sh, the version a build carries, or a release's with
# betterleaks_for=release), and the program (tools/compile.sh, with the options after $1).
make_bundle() {
  local app=$1 exe
  shift
  exe=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" app/Info.plist)
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Helpers"
  cp app/Info.plist "$app/Contents/"
  cp icon/AppIcon.icns "$app/Contents/Resources/"
  tools/page.sh "$app/Contents/Resources/panel"
  cp app/swap-in.sh app/ask-panel.sh "$app/Contents/Resources/"
  copy_plugin "$app/Contents/Resources/plugin"
  # Betterleaks for the Mac the program is built for (its -arch, else this Mac's), whatever Mac builds it.
  local arch=$(uname -m) previous=
  for option in "$@"; do
    [ "$previous" = -arch ] && arch=$option
    previous=$option
  done
  tools/betterleaks.sh ${betterleaks_for:+--$betterleaks_for} --arch "$arch" "$app/Contents/Helpers" >/dev/null
  mv "$app/Contents/Helpers/LICENSE" "$app/Contents/Resources/Betterleaks-LICENSE"
  tools/compile.sh "$app/Contents/MacOS/$exe" "$@"
}

# Signs the bundle $1, once nothing more goes in it: a file added after the signature breaks it. Ad-hoc signed, but
# with the bundle id as its designated requirement: macOS keys privacy grants (Accessibility, for the Claude Desktop
# message box) to that, so a rebuild doesn't lose them. By default an ad-hoc signature's requirement is the exact
# build's hash. The catch: any ad-hoc signed app claiming this id would match it too. Signing with a certificate of
# your own (and its requirement) closes that. Its files' extended attributes are cleared first: cp and install copy
# them with the files, and codesign refuses a bundle with Finder information in it (a file's colour tag, say). The
# helper inside is signed on its own first, as the bundle's signature takes in what's nested only once it's signed.
sign_bundle() {
  local id
  id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$1/Contents/Info.plist")
  xattr -cr "$1"
  codesign --force --sign - "$1/Contents/Helpers/betterleaks" 2>/dev/null ||
    codesign --force --sign - "$1/Contents/Helpers/betterleaks"
  codesign --force --sign - -r="designated => identifier \"$id\"" "$1"
}
