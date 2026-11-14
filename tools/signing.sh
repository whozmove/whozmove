#!/bin/bash
# Signing your own builds with your Developer ID (docs/guides/signing.md): its key lives in a keychain of its own,
# Whozmove's signing keychain, behind a password of its own that macOS asks for each time a build is signed.
#   tools/signing.sh new         makes that keychain, asking you for its password, and a request for the certificate,
#                                whose key is made in that keychain and never leaves it
#   tools/signing.sh add FILE    puts the certificate Apple made from the request in beside its key
# build.sh and tools/release.sh source it for signing_identity, the one place that decides who signs a build.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

# The keychain, in your home folder's (a test's home has none, so its builds are ad hoc). Only this file is asked
# about, never the keychains macOS searches, so nothing in another one can sign.
signing_keychain="$HOME/Library/Keychains/whozmove-signing.keychain-db"

# Who signs this build. Prints the Developer ID Application identity in the signing keychain and returns 0; prints
# nothing and returns 1 for an ad hoc build: an agent's command (Claude Code marks the commands an agent runs with
# CLAUDECODE, as build.sh reads it), or no signing keychain; prints what to do and returns 2 when the keychain is there
# but holds no identity that works (its certificate not added yet, expired, or Apple's intermediate missing), as a
# build then would be refused the grants the signed ones share.
signing_identity() {
  [ -z "${CLAUDECODE:-}" ] && [ -e "$signing_keychain" ] || return 1
  local found
  found=$(security find-identity -v -p codesigning "$signing_keychain" 2>/dev/null |
    awk '/"Developer ID Application: / { print $2; exit }')
  if [ -z "$found" ]; then
    echo "Whozmove's signing keychain holds no Developer ID certificate that works (not added yet, expired, or Apple's"
    echo "Developer ID - G2 certificate missing), so nothing was built: add one (tools/signing.sh add FILE), make a new"
    echo "one (docs/guides/signing.md), or take $signing_keychain out to build ad hoc again."
    return 2
  fi
  echo "$found"
}

# Locks the signing keychain, as each build does as soon as its signing ends, whichever way it ended: open only for a
# build's own password boxes, so a key someone let codesign use without asking can't sign anything after them.
lock_signing() { security lock-keychain "$signing_keychain" 2>/dev/null || true; }

case "${BASH_SOURCE[0]}" in "$0") ;; *) return 0 ;; esac
set -euo pipefail

# A keychain's path as security prints it, trimmed of its indent and quotes.
unquoted() {
  local line=$1
  line=${line#"${line%%[![:space:]]*}"}; line=${line#\"}; line=${line%\"}
  printf '%s' "$line"
}

# codesign finds an identity only in a keychain on your list (the keychains macOS searches), even one named with
# --keychain: the signing keychain goes on it last, after yours, and your default keychain stays as it is. Setting the
# list replaces it, so it's written only when the one read holds your default keychain: a list read wrong, set to
# the signing keychain alone, would take your own keychains out of what macOS searches.
on_the_list() {
  local list=() line default found=no
  while IFS= read -r line; do
    line=$(unquoted "$line")
    [ -n "$line" ] && list+=("$line")
  done < <(security list-keychains -d user)
  for line in "${list[@]}"; do [ "$line" = "$signing_keychain" ] && return 0; done
  default=$(unquoted "$(security default-keychain -d user)")
  for line in "${list[@]}"; do [ -n "$default" ] && [ "$line" = "$default" ] && found=yes; done
  if [ "$found" = no ]; then
    echo "The keychains macOS searches for you couldn't be read, so the signing keychain wasn't added to them, and they"
    echo "stay as they were. Add it in Keychain Access (File ▸ Add Keychain, then $signing_keychain), then run"
    echo "tools/signing.sh add again."
    return 1
  fi
  security list-keychains -d user -s "${list[@]}" "$signing_keychain"
}

# Lets codesign ask for the key: its partition list names Apple's own programs (apple:), which codesign is one of;
# Apple's tools' group (apple-tool:) alone, measured, still brings a second box, to access the key, at each use. It
# still asks for the keychain's password each time, as the key's access lets no program use it without asking.
# Without it, each signing brings twice as many boxes. Set once, here, never by a build: security asks for the
# password itself.
let_codesign_ask() {
  echo "macOS's security asks for your signing keychain's password, to let codesign ask for the key:"
  security set-key-partition-list -S apple: -s "$signing_keychain" >/dev/null
}

case "${1:-}" in
  new)
    [ -z "${CLAUDECODE:-}" ] ||
      { echo "Run tools/signing.sh new in Terminal, outside Claude Code: it asks you for a password."; exit 2; }
    if [ -e "$signing_keychain" ]; then
      echo "Whozmove's signing keychain is there already: $signing_keychain."
      echo "To start again with a new certificate (a forgotten password, say), take that file out first."
      exit 1
    fi
    request="$HOME/Desktop/Whozmove signing.certSigningRequest"
    echo "Making Whozmove's signing keychain. Choose a password for it, one you don't use for anything else, and keep it"
    echo "where you keep passwords: macOS asks for it each time a build of yours is signed."
    security create-keychain "$signing_keychain"
    # Locked when the Mac sleeps and after a minute unused; build.sh and release.sh lock it as soon as signing ends, so
    # it's open only while a build of yours is being signed.
    security set-keychain-settings -l -u -t 60 "$signing_keychain"
    on_the_list || true
    echo
    echo "Now the request for its certificate. Its key is made in that keychain, open only to this request: anything"
    echo "else that signs with it is asked for the keychain's password. certtool asks, in this order:"
    echo "  a label: Whozmove signing      the key's algorithm: r       its size: Return (2048)       OK: y"
    echo "  its use: s                     the signature's algorithm: 2  OK: y                         a challenge: Return"
    echo "  Common Name: the name Apple has you under    Country: your two letters    the next three: Return"
    echo "  Email Address: your Apple Account's          OK: y"
    certtool r "$request" k="$signing_keychain" a
    let_codesign_ask
    echo
    echo "The request is on your Desktop. Upload it at"
    echo "https://developer.apple.com/account/resources/certificates/add (Developer ID Application, G2 Sub-CA if asked),"
    echo "download the certificate, and run: tools/signing.sh add <the certificate you downloaded>"
    ;;
  add)
    [ -n "${2:-}" ] && [ -f "$2" ] || { echo "Usage: tools/signing.sh add <the certificate Apple made>"; exit 2; }
    [ -z "${CLAUDECODE:-}" ] ||
      { echo "Run tools/signing.sh add in Terminal, outside Claude Code: it asks for your keychain's password."; exit 2; }
    [ -e "$signing_keychain" ] || { echo "There's no signing keychain yet: run tools/signing.sh new first."; exit 1; }
    security import "$2" -k "$signing_keychain"
    on_the_list || exit 1
    let_codesign_ask
    if signing_identity >/dev/null; then
      echo "Ready: builds you make here are signed with your Developer ID from now on, each asking for the keychain's"
      echo "password a few times as it signs. Press Allow each time, never Always Allow: it would let anything on this"
      echo "Mac sign as you while the keychain is open. A box that doesn't follow your own ./build.sh or a Deploy (yours,"
      echo "one you let a session ask for, or one kept for later while an agent worked) isn't Whozmove's: press Deny."
    else
      echo "The certificate is in, but nothing in the keychain signs with it yet. Most often that's Apple's Developer ID -"
      echo "G2 certificate missing: download it at https://www.apple.com/certificateauthority/, double-click it, and run"
      echo "tools/signing.sh add again. Otherwise, check it's a Developer ID Application certificate, made from this"
      echo "keychain's request; or take $signing_keychain out to build ad hoc again."
      exit 1
    fi
    ;;
  *)
    echo "Usage: tools/signing.sh new | add FILE (docs/guides/signing.md)"
    exit 2
    ;;
esac
