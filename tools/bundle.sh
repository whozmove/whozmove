# Whozmove's app bundle: what goes in it, and its signature. Sourced by build.sh and tools/release.sh, from the
# checkout's root.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# Every bundle is made here, so each one carries the same parts, its hooks among them: they go in with the app, and
# are sealed in its signature with the rest. Who signs it is tools/signing.sh's to say.
. modules/claude-code/plugin.sh
. tools/signing.sh

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

# Signs the bundle $1, once nothing more goes in it: a file added after the signature breaks it. With an identity ($2,
# from the keychain $3: tools/signing.sh's, or the release workflow's), it's signed with that Developer ID and macOS's
# own rule for it, which names Apple, the developer's team and the bundle id: macOS keys privacy grants
# (Accessibility, for the Claude Desktop message box) to that rule, so every build signed by the same developer, and
# every release, keeps the grants given to one of them, and nothing signed by anyone else matches it. $4 is release
# for a build Apple will notarise, which wants a secure timestamp from Apple's server; any other is signed with none,
# so a build here never goes online. Each is signed once, with no retry, so a password box you deny isn't shown again.
# Without an identity (an agent's build, a test's, a Mac with no certificate), it's signed ad hoc with the bundle id as
# its designated requirement, so a rebuild there keeps its grants too.
# Its files' extended attributes are cleared first: cp and install copy them with the files, and codesign refuses a
# bundle with Finder information in it (a file's colour tag, say). The helper inside is signed on its own first, as
# the bundle's signature takes in what's nested only once it's signed.
#
# Every program in it runs with the hardened runtime (--options runtime), so no other code runs as Whozmove with its
# grants: macOS ignores a library forced in as it starts (DYLD_INSERT_LIBRARIES) and refuses a debugger. What the
# runtime holds back that Whozmove needs is asked for in tools/Whozmove.entitlements, one key for each, added only
# when Whozmove starts using it: today, sending Apple Events to the apps it controls. The ones that would undo the
# runtime never go in: get-task-allow, allow-dyld-environment-variables, disable-library-validation,
# allow-unsigned-executable-memory and allow-jit. Betterleaks asks for none: Keys has it match with Go's own regular
# expressions, as its default compiles a matcher into memory as it looks, which the runtime stops (KeyFacts.m).
sign_bundle() {
  local app=$1 identity=${2:-} keychain=${3:-} id stamp=--timestamp=none
  id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist")
  xattr -cr "$app"
  if [ -n "$identity" ]; then
    [ "${4:-}" = release ] && stamp=--timestamp
    codesign --force --sign "$identity" --keychain "$keychain" --options runtime $stamp \
      "$app/Contents/Helpers/betterleaks" || return 1
    codesign --force --sign "$identity" --keychain "$keychain" --options runtime $stamp \
      --entitlements tools/Whozmove.entitlements "$app" || return 1
    return 0
  fi
  codesign --force --sign - --options runtime "$app/Contents/Helpers/betterleaks" 2>/dev/null ||
    codesign --force --sign - --options runtime "$app/Contents/Helpers/betterleaks" || return 1
  codesign --force --sign - --options runtime --entitlements tools/Whozmove.entitlements \
    -r="designated => identifier \"$id\"" "$app"
}
