# Runs the test that sources it in a macOS sandbox of its own, so nothing it does can reach your home folder, your
# sessions or your accounts, even when the test reaches for them by mistake: the line after each test's `cd` is
# `. tests/sandboxed.sh "$@"`, which tests/checks.sh looks for in every one. A test that downloads what it checks says
# so first: `. tests/sandboxed.sh --downloads "$@"`.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#
# In it, a test writes only where tests make their throwaway homes and builds (this account's temporary folder and its
# caches, its own wz- or whozmove- folders in /tmp, the pipes bash makes there for <(…) when TMPDIR isn't set, and its
# here documents' files in /var/tmp), and the checkout itself only with --update, which records a test's expected output
# there. It connects to no socket but those in its own wz- and whozmove- folders (in /tmp and the temporary folder),
# so never to the hook.sock or ask.sock of the panel you're using, nor to a Claude Code session's in /tmp/cc-socks, nor
# to a helper's of macOS's or another app's (tests/sandbox.sh checks it); to no address but this Mac's own (with
# --downloads, also HTTPS anywhere); and to no Keychain, where your sign-ins are whatever HOME says. It writes the
# preferences of no app but the test build's own (a bare build's are "Whozmove", never the app's com.whozmove.app); it
# signals only the processes it started; and it opens no app. ps, which a sandbox may not start (it's set-user-id),
# runs outside it, as it only reads. The test then runs again inside it, and what it starts stays inside without making
# a sandbox of its own.
#
# What it leaves open: this Mac's own addresses are every server on it, a Deploy's or an editor's too, and --downloads
# lets HTTPS reach anywhere, not only what the test downloads. And a program the test starts can't open a /dev/fd path
# it's given, as diff <(…) does: compare through a file (tests/compare.sh).
#
# macOS refuses a sandbox inside another, which is how a test tells it may be in one already: then it asks macOS
# whether it is (in its own, or in a Claude Code session's, which keeps its writes to the checkout and the temporary
# folders too) and runs as it is only if so. Anywhere else it runs only in its own: if that can't be made, it doesn't
# run.
sandboxed_downloads=
[ "${1:-}" = --downloads ] && sandboxed_downloads=1 && shift
sandboxed_refusal=$(/usr/bin/sandbox-exec -p '(version 1) (allow default)' /usr/bin/true 2>&1)
sandboxed_refused=$?
if [ $sandboxed_refused = 0 ]; then
  sandboxed_profile=$(mktemp "${TMPDIR:-/tmp}/whozmove-sandbox.XXXXXX") || exit 1
  sandboxed_quote() { printf '"%s"' "$(cd "$1" 2>/dev/null && pwd -P | sed 's/[\\"]/\\&/g')"; }
  sandboxed_own() {
    printf ' (regex #"^/private/tmp/(wz-|whozmove-|sh-np)")'
    for folder in "${TMPDIR:-/tmp}" "$(getconf DARWIN_USER_TEMP_DIR)" "$(getconf DARWIN_USER_CACHE_DIR)"; do
      [ -d "$folder" ] && [ "$(cd "$folder" && pwd -P)" != /private/tmp ] && printf ' (subpath %s)' \
        "$(sandboxed_quote "$folder")"
    done
  }
  # A Unix socket a test may reach, by the start of its path. A socket is matched only by a socket's own filter
  # (path-regex), against its real path (/private/tmp, never /tmp), one rule each: a file's filters (subpath, regex)
  # match no socket, and several filters in one rule must all match, so neither lets anything through.
  sandboxed_socket() { printf '(allow network-outbound (remote unix-socket (path-regex #"^%s")))\n' "$1"; }
  # A folder's real path, written so a regex takes it as it is.
  sandboxed_regex() { (cd "$1" 2>/dev/null && pwd -P | sed 's/[][\\.^$*+?(){}|"]/\\&/g'); }
  {
    echo '(version 1)'
    echo '(allow default)'
    echo '(deny file-write*)'
    printf '(allow file-write* (subpath "/dev")%s' "$(sandboxed_own)"
    for argument in "$@"; do
      [ "$argument" = --update ] && printf ' (subpath %s)' "$(sandboxed_quote .)" && break
    done
    echo ')'
    # macOS's bash makes a here document's file in /var/tmp whatever TMPDIR says, once it has seen that it may write
    # there, and else in the folder it's in: only its own sh-thd files, and that look at the folder.
    echo '(allow file-write-data (literal "/private/var/tmp"))'
    echo '(allow file-write* (regex #"^/private/var/tmp/+sh-thd-[0-9]+$"))'
    # Only a test's own sockets, in the wz- and whozmove- folders tests make; never a session's, in /tmp/cc-socks,
    # written last so it stands whatever comes before.
    echo '(deny network-outbound (remote unix-socket))'
    sandboxed_socket '/private/tmp/(wz-|whozmove-)'
    sandboxed_seen=/private/tmp
    for folder in "${TMPDIR:-/tmp}" "$(getconf DARWIN_USER_TEMP_DIR)"; do
      sandboxed_real=$(sandboxed_regex "$folder") && [ -n "$sandboxed_real" ] \
        && [ "$sandboxed_real" != "$sandboxed_seen" ] && sandboxed_socket "${sandboxed_real%/}/(wz-|whozmove-)" \
        && sandboxed_seen=$sandboxed_real
    done
    echo '(deny file-write* (subpath "/private/tmp/cc-socks"))'
    echo '(deny network-outbound (remote unix-socket (path-regex #"^/private/tmp/cc-socks/")))'
    echo '(deny network-outbound (remote ip))'
    echo '(allow network-outbound (remote ip "localhost:*"))'
    [ -n "$sandboxed_downloads" ] && echo '(allow network-outbound (remote ip "*:443"))'
    echo '(deny mach-lookup (global-name "com.apple.SecurityServer"))'
    echo '(deny user-preference-write)'
    echo '(allow user-preference-write (preference-domain "Whozmove"))'
    echo '(deny signal (target others))'
    echo '(allow signal (target same-sandbox))'
    echo '(deny lsopen)'
    echo '(allow process-exec (literal "/bin/ps") (with no-sandbox))'
  } > "$sandboxed_profile"
  if /usr/bin/sandbox-exec -f "$sandboxed_profile" /usr/bin/true 2>/dev/null; then
    export WHOZMOVE_TEST_SANDBOX="$sandboxed_profile" PYTHONDONTWRITEBYTECODE=1
    exec /usr/bin/sandbox-exec -f "$sandboxed_profile" "$BASH" -c 'cd "$1" && shift && exec "$0" "$@"' \
      "$BASH" "$OLDPWD" "$0" "$@"
  fi
  rm -f "$sandboxed_profile"
  echo "$0: couldn't make the sandbox it runs in (sandbox-exec), so it doesn't run" >&2
  exit 1
fi
# A sandbox couldn't be made here. That's this one being in a sandbox only if sandbox-exec says so (it was refused the
# sandbox it applies), and macOS, asked, agrees; where python3 can't ask (a Mac without Apple's developer tools, which
# the tests need anyway), sandbox-exec's own refusal stands for it.
sandboxed_check=$(/usr/bin/python3 -I -c 'import ctypes, os
check = ctypes.CDLL("/usr/lib/libSystem.B.dylib").sandbox_check
check.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
print(check(os.getpid(), None, 0))' 2>/dev/null) || sandboxed_check=unknown
case "$sandboxed_refused $sandboxed_refusal $sandboxed_check" in
  "71 sandbox-exec: sandbox_apply: Operation not permitted 1" | \
  "71 sandbox-exec: sandbox_apply: Operation not permitted unknown") ;;
  *)
    echo "$0: couldn't make the sandbox it runs in (sandbox-exec), so it doesn't run" >&2
    exit 1 ;;
esac
# The test's first step in the sandbox it made: the profile has done its work.
case "${WHOZMOVE_TEST_SANDBOX:-}" in
  "${TMPDIR:-/tmp}"/whozmove-sandbox.*) [ -f "$WHOZMOVE_TEST_SANDBOX" ] && rm -f "$WHOZMOVE_TEST_SANDBOX" ;;
esac
export WHOZMOVE_TEST_SANDBOX=${WHOZMOVE_TEST_SANDBOX:-outer} PYTHONDONTWRITEBYTECODE=1
