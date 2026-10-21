# Install

Whozmove setting itself up each time it opens. An install from Homebrew only copies the app, so everything the
install script did happens here, as the app starts: it notes where it runs from, looks for the agent, waits for
Apple's command line developer tools, which only the agent's sessions need, and puts its hooks into the agent (Claude
Code's plugin) or brings them up to date there. Nothing of it shows on screen yet.

## Its pieces

- `app/InstallModule.m`: its face for the core (contracts/Module.h). At launch it finds the agent that takes the
  hooks (`AgentInstall`, contracts/Agent.h) and starts the check; and each tick, while the check waits for the agent
  or for the developer tools, it looks again every 10 seconds (macOS is asked about the tools at most every 5 minutes).
  Its print mode is `--print-install`.
- `app/Install.h/.m`: the check, in this order, on a queue of its own, one at a time, your presses on the line
  included:
  1. Only from an Applications folder (`InApplications`: /Applications or ~/Applications, at any depth). A copy
     opened where it was downloaded, from a disk image, from a build's folder, or from the copy macOS runs one of
     those from (App Translocation) sets nothing up.
  2. Where it runs from goes in Whozmove's folder (`app`), written whole, and only when it changed: the hooks record
     only while that app is there.
  3. Nothing more until the agent is on this Mac (`onThisMac`, found without running anything): Whozmove works
     without it, and the developer tools are only needed for its sessions.
  4. Nothing more until Apple's developer tools are in (`DeveloperToolsReady`): the agent may run git, which until
     then offers to install them each time it runs.
  5. A build an agent made (build.json's `agent`, `BuiltByAgent` in the core's Builds) leaves the hooks as they are.
  6. The agent puts the hooks in, or brings them up to date (`connect:before:from:`), from the copy this app carries
     (`Contents/Resources/plugin`).
- Its own record, in Whozmove's folder (`install.json`), not the app's preferences, which a print run's home folder
  doesn't reach: when the hooks were first found in the agent, so ones you take out aren't put back. Each outcome goes
  in the panel's log, once, until it changes.

`tests/test.sh` runs `--print-install`'s cases, each with stand-ins for where the app runs from, whether an agent
made it, the agent and the developer tools, and compares what each check found, what the agent was asked and what was
noted with `tests/install.expected.txt`.

## Rules

- Nothing is set up from anywhere but an Applications folder: a copy that may be gone tomorrow must never decide where
  the hooks look for the app.
- Hooks you took out of the agent are never put back unless you ask (`before`, from its record).
- An agent's build never puts its hooks in place: every session you start would run them.
- Apple's developer tools are asked for only once the agent is on this Mac, and nothing of it runs the agent before
  they're in.
- Its print mode writes in Whozmove's folder in `$HOME`, so it never runs in your own home folder.
