#!/bin/sh
# Claude Sessions Manager - records which terminal tab a Claude Code session is running in.
#
# Runs on SessionStart and on UserPromptSubmit. SessionStart alone would never see a
# session that was already running when this plugin was installed, and those are exactly
# the sessions a user has open right now. UserPromptSubmit fires once per prompt - human
# paced, not per tool call - so an existing session is picked up the first time it is used.
#
# UserPromptSubmit's payload contains the user's prompt text. The record below is built
# from an explicit field list, so the prompt is never read and never written.
#
# Contract, in order of importance:
#   1. Never write to stdout. Claude Code reads hook stdout as control output.
#   2. Always exit 0. A non-zero exit from a hook can block the user's session.
#   3. Do nothing slow. This runs inside every SessionStart.
#
# Every failure below is a silent `exit 0`: the desktop app is fully functional
# without an address, it just cannot focus that session's tab.

set -u

INPUT=$(cat 2>/dev/null) || exit 0

# Only Warp publishes a focus URL. Any other terminal has no address to record.
[ -n "${WARP_FOCUS_URL:-}" ] || exit 0

# jq is how we parse and emit JSON safely. Without it, degrade to no deep-linking
# rather than hand-rolling escaping for paths that can contain quotes and spaces.
command -v jq >/dev/null 2>&1 || exit 0

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -n "$SESSION_ID" ] || exit 0

# The id becomes a filename, so refuse anything that is not a plain identifier.
case "$SESSION_ID" in
    *[!a-zA-Z0-9_-]*) exit 0 ;;
esac

DIR="${CLAUDE_SESSIONS_MANAGER_HOME:-$HOME/.claude-sessions-manager}/addresses"
mkdir -p "$DIR" 2>/dev/null || exit 0

# Write to a temporary file and rename, so a reader polling this directory can never
# observe a half-written record. Same hazard the session registry has, avoided here.
# Steady state: the record already exists and still points at this tab, so there is
# nothing to do. Keeps the per-prompt cost to a single grep.
TARGET="$DIR/$SESSION_ID.json"
if [ -f "$TARGET" ] && grep -qF "\"focus_url\":\"$WARP_FOCUS_URL\"" "$TARGET" 2>/dev/null; then
    exit 0
fi

TMP="$DIR/.$SESSION_ID.$$.tmp"
printf '%s' "$INPUT" | jq -c \
    --arg focus_url "$WARP_FOCUS_URL" \
    --arg terminal "${TERM_PROGRAM:-}" \
    --arg uuid "${WARP_TERMINAL_SESSION_UUID:-}" \
    --arg recorded_at "$(date +%s)000" \
    '{
        session_id: .session_id,
        cwd: (.cwd // ""),
        source: (.source // ""),
        event: (.hook_event_name // ""),
        focus_url: $focus_url,
        terminal: $terminal,
        terminal_session_uuid: $uuid,
        recorded_at: ($recorded_at | tonumber)
     }' > "$TMP" 2>/dev/null || { rm -f "$TMP" 2>/dev/null; exit 0; }

mv -f "$TMP" "$DIR/$SESSION_ID.json" 2>/dev/null || rm -f "$TMP" 2>/dev/null

exit 0
