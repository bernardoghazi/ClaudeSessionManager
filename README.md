# Claude Session Manager

A macOS menu-bar app for keeping track of your [Claude Code](https://docs.claude.com/en/docs/claude-code) sessions. It does two jobs:

- **Live status.** A dot in the menu bar lists every running session and turns orange when one needs you. Clicking a session brings its Warp tab to the front. Notifications tell you when a session is waiting on you or has finished a turn.
- **Session finder.** A window lists every session on disk. You can search titles, folders, branches and full transcript contents, copy a `claude -r <id>` resume command, or rename a session.

It merges two earlier tools, Agents Overview and Claude Sessions Finder, into one native Swift app.

## Requirements

- macOS 15 or later
- Xcode or the Swift 6 toolchain, to build
- Claude Code
- [Warp](https://www.warp.dev), if you want clicking a session or notification to focus its terminal tab. Status and the session finder work in any terminal.

## Build and run

To install, or to update an installed copy:

```sh
./build.sh --install   # builds, replaces /Applications/ClaudeSessionManager.app and relaunches it
```

To build and try it from the repo without installing:

```sh
./build.sh                      # release build, bundles and ad-hoc signs ClaudeSessionManager.app here
open ClaudeSessionManager.app   # launch through LaunchServices so notification clicks work
```

If you move or rename the repo folder, delete `.build/` before building. Swift's build cache records the old path and fails otherwise.

To uninstall, quit the app, then:

```sh
rm -rf /Applications/ClaudeSessionManager.app ~/.claude-session-manager
```

Earlier versions installed a helper plugin. If `claude plugin list` still shows `claude-session-manager@claude-session-manager`, remove it with `claude plugin uninstall claude-session-manager@claude-session-manager` and `claude plugin marketplace remove claude-session-manager`.

For development, run the tests with `swift test` (Swift Testing). `swift run` also starts the app, but without a bundle there are no notifications.

The first time the app posts a notification, macOS asks for permission. Notifications default to the persistent Alert style. If yours disappear after a few seconds, change the style in System Settings → Notifications → Claude Session Manager.

## Using it

### Menu bar

The dot is blue when all is calm and orange when any session is waiting. Each running session gets a row:

```
🟠  billing-fix · Waiting · Needs your input · 2m 5s
🟢  claude-session-manager · Working · 36s
🔵  marcopolo-b1 · Idle
```

Clicking a row focuses that session's terminal tab. A row is disabled, and says `no tab`, when the app can't tell which tab the session is in. The menu also has **Open Sessions Window** (⌘O) and **Quit** (⌘Q).

### Statuses

| Claude Code status | Shown as | Colour |
|---|---|---|
| `busy` | Working | green |
| `waiting` | Waiting, plus the reason | orange |
| `idle`, `shell`, or anything unrecognised | Idle | blue |
| not running | (no status) | — |

Waiting reasons: "Needs your input", "Waiting on a dialog", "Wants sandbox access", "Waiting on a goal proposal", "Waiting on a worker request". If there's no reason it shows "Needs your attention", and an unknown reason is shown as "Waiting: <reason>".

### Notifications

Only two things notify:

- a session starts **waiting** on you
- a session goes from Working to Idle after a turn of **at least 2 seconds** ("Finished after 4m 12s")

Clicking a notification focuses that session's tab.

### Sessions window

A table of every session on disk, with Status, Session (title), Folder, Branch, Last Edited and Size. Every column sorts. A folder that no longer exists is struck through.

| Action | How |
|---|---|
| Focus the terminal of a running session | double-click or Return, or right-click → Focus Terminal |
| Copy `claude -r <id>` | double-click or Return on a session that isn't running, or the toolbar button |
| Copy session ID | ⌘C |
| Copy branch name | ⇧⌘C |
| Rename | ⌘⏎. Refused while the session is running; use `/rename` there instead |
| Reveal folder in Finder | right-click |
| Refresh | ⌘R. The list also refreshes when the app becomes active |

Search matches titles, folders, branches and IDs straight away, and transcript contents after a short pause. Content search ignores case for ASCII letters only.

## How it works

| Reads | For |
|---|---|
| `~/.claude/sessions/<pid>.json` | Live status. This is Claude Code's internal, undocumented registry, polled every 500 ms. |
| `~/.claude/projects/*/<id>.jsonl` | The session list, titles, folders and branches, plus content search |
| the session process's environment (`ps eww`) | `WARP_FOCUS_URL`, to find the Warp tab of any running session, including ones started before the app. Read once per session. |

| Writes | When |
|---|---|
| two lines appended to a transcript (`custom-title` and `agent-name`) | renaming a session, the same records `/rename` writes |
| `~/.claude-session-manager/activity.log` | always; a diagnostic log of launches, notifications and clicks |

Set `CLAUDE_SESSION_MANAGER_HOME` to use a folder other than `~/.claude-session-manager`.

The registry reader is built to avoid false notifications. A file caught mid-write is not treated as a session ending. A recycled pid is detected by comparing the process start time with the session's. An unrecognised status keeps the last known one.

The app needs no setup inside Claude Code: no plugin, hook or settings change.

## Project layout

```
Package.swift
build.sh                         builds and signs ClaudeSessionManager.app
Sources/ClaudeSessionCore/       logic, no UI
  Transcripts/                   session index, content search, rename
  Live/                          registry reader, process liveness, tab lookup from the process environment
  Monitor/                       transition detection, notification policy and wording, poll loop
  Integration/                   paths, terminal focusing, logging, running commands
Sources/ClaudeSessionManager/    the SwiftUI app: menu bar, sessions window, notifications
Tests/ClaudeSessionCoreTests/    tests for the core library
```
