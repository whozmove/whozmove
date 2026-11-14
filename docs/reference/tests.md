# Tests

Each test on its own, and what it checks. `tests/all.sh` runs every one, with the app built once for all of them,
and ends by naming the ones that failed; `--update` on any of them records its expected output again after a change
you meant (read the diff first).

```bash
tests/rows.sh         # the rows the app builds for a sample home, its mode menus' Shift+Tab counts, the menus' why
                      # nots, how a command's result is read, and why a recording counts as talking to an agent,
                      # compared with tests/rows.expected.txt
tests/panel.sh        # the page's labels, colours, sorting and row HTML (macOS's jsc, in UTC), vs
                      # tests/panel.expected.txt
tests/build.sh        # build.sh against a throwaway HOME: when a build waits and when it goes in, the hooks it
                      # carries, sealed in its signature, the hardened runtime and the entitlements it's signed with,
                      # swap-in.sh putting it in place, what it restarts, no build on a Mac older than the app needs,
                      # and with a signing keychain, an agent's build kept out and a broken one stopping the build,
                      # vs tests/build.expected.txt
tests/browser.sh      # where each kind of address goes from a Browser's sample setups, and the folders, stores and
                      # names it keeps to, for a sample folder, vs tests/browser.expected.txt
tests/edges.sh        # the panel's edge for sample panels and screens: the side its icons are on, where it folds
                      # round Whozmove beside it, whether a swipe is the panel's and flicks it off the screen's edge,
                      # where a flicked panel goes and how much shows on its way, a swipe on Whozmove there pulling
                      # it back out or pushing Whozmove in, which way what comes out of the folded cat goes and the
                      # room for it, and how tall the list and the panel may get, vs tests/edges.expected.txt
tests/keys.sh         # the edit each key does (⌘V and the rest) in a web view being typed in, and none while
                      # nothing in it has the keyboard, vs tests/keys.expected.txt
tests/ticked.sh       # the switches kept only while Whozmove runs, or for a folder, and ticked.json that offers them back
                      # after a restart, in a throwaway home: what is written, what waits, what one press turns on and
                      # what it refuses, who in a folder holds a switch kept for it, and what a Quit, a restart and a
                      # print run leave, vs tests/ticked.expected.txt
tests/sandbox.sh      # what the sandbox every test runs in lets a test reach over a Unix socket: one in a folder of its
                      # own, and none in another it may write in, vs tests/sandbox.expected.txt
tests/checks.sh       # the checks that keep the parts and modules apart, each a file of its own in tests/checks/
                      # (prints only problems): no page function
                      # in two scripts, every page call and message has its other end, no module imports another,
                      # no class styled on its own by two owners (the core, a part, a module), a part reached only
                      # through what it provides, what decides and delivers in notifications reading only its own
                      # state (no row's field, no part's constant), but for what tests/part-crossings.txt lists, each
                      # part's and each module's README with its pieces and its rules, every file the page loads in
                      # the page tools/page.sh writes, no colour, text size or corner written out in a style that
                      # tests/styles-by-hand.txt doesn't list (--update takes off the ones gone), no way to your own
                      # home folder past HOME (NSHomeDirectory(), getpwuid(), a real-looking /Users/…) but for what
                      # tests/real-home.txt lists, each outside app's bundle id or folder in its module's Facts header
                      # but for what tests/facts-by-hand.txt lists, each Facts header named in docs/using/install.md's
                      # "What it's tested with", no Jira site or ticket key but made-up ones (acme, PAY-142) and no
                      # code that decides by a status's name, the README with ten features at most, each <picture>
                      # in a dark and a light version, and every link and anchor in it, SECURITY.md, CONTRIBUTING.md
                      # and docs/ there, docs/reference/rows.md describing exactly the fields a row has, the README
                      # naming each macOS permission the app asks for and no file naming one it doesn't, and no test
                      # defining again a helper tests/lib.sh has but for what tests/helpers-by-hand.txt lists
tests/outside.sh      # what goes outside this Mac, the files that start programs and what isn't the project's own,
                      # against tests/outside.txt (--update takes off the ones gone), and none of what's never
                      # allowed: a certificate check turned off, a plain http:// address, a program started outside
                      # app/shared/Processes.m, an action not GitHub's own and pinned, an import from outside
                      # Python's own library; it needs no build, and checks itself on made-up files first, vs
                      # tests/outside.expected.txt
tests/energy-tool.sh  # tools/energy.sh against a stand-in app: its helpers built with every warning an error, the
                      # programs it starts named with the folder each git and gh ran in, never another of their
                      # arguments; a made-up week's power log; each report's figures against their targets;
                      # nothing written in the home; each app id tools/energy/hosts.txt takes from a module still
                      # the module's; and each target in tools/energy/targets.txt the one the energy page's table
                      # says, vs tests/energy-tool.expected.txt
parts/*/tests/test.sh    # each part's own tests, where it has them, as a module's are
modules/*/tests/test.sh  # each module's own tests, with its own recorded outputs; Claude Code's run both hooks against
                         # a throwaway HOME, compared with modules/claude-code/tests/hooks.expected.txt (on the
                         # developer tools' Python too), put its plugin into a stand-in Claude Code, and say which
                         # stand-in session holds the switches kept for a folder (stand-in.c's sessions); the install
                         # module's, how the app sets itself up as it opens; the usage module's, what the usage card
                         # shows and the vine's reset, with its page's scripts; the commands module's, how the log
                         # says each command, never its words; and the Claude Desktop module's, how it says what's
                         # written in a conversation's message box and what Claude's window shows; the waits module's,
                         # waits begun and woken as the gear has room, what's kept across a restart, and ask-panel.sh's
                         # wait waiting through the panel being away; the git module's, what wakes a session
                         # waiting on a pull request; and the process-notes module's, a project's note kept only by
                         # Keep It, the same lines not asked again after Not Now, and the Keep It card in each state;
                         # and the ticket routing module's, where a ticket starts by its project's way, the guide,
                         # what's kept, and Settings' before and after
modules/claude-code/tests/real.sh --throwaway-mac
                         # a real Claude Code (the version modules/claude-code/tests/claude-code.txt pins, or
                         # --newest) against a stand-in for Anthropic's servers, driven through what the panel does,
                         # compared with real.expected.txt; only on a throwaway Mac (CI, a virtual Mac), as Claude Code
                         # reads the Mac's sign-in; --stand-in-claude checks the run's own pieces anywhere. Needs the
                         # network; not in tests/all.sh
```
