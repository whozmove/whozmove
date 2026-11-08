# Builds

The build of Whozmove running now, as build.sh recorded it: for the header's line (Show Build in Header), and for the
install module, which leaves the hooks as they are for a build an agent made, and never looks for a newer version for a
build from a checkout.

## What it owns

- `app/Builds.h`, `app/Builds.m`: `RunningBuild` (where this app's build came from, or nil), `RunningBuildTip` (the
  same in words) and `BuiltByAgent`. Plain functions.
- `part.json`: who it talks to, and what it provides.

## Who it talks to

It talks only to the core (`Files`, for the record build.sh writes). The pawn menu (the menubar part), the app's
start-up and the install module import its header.

## Rules

- **An agent's build never puts its hooks in place:** every session you start would run them, and an agent's may be
  half-way through a change (`BuiltByAgent`).
