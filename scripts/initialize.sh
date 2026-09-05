#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
PRS_ROOT=$(CDPATH='' cd "$SCRIPT_DIR/.." && pwd)
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

if [ -z "$("$PRS_TMUX" show-options -gqv "$PRS_ENABLED_OPTION" 2>/dev/null)" ]; then
    "$PRS_TMUX" set-option -gq "$PRS_ENABLED_OPTION" on
fi
if [ -z "$("$PRS_TMUX" show-options -gqv "$PRS_DEBUG_OPTION" 2>/dev/null)" ]; then
    "$PRS_TMUX" set-option -gq "$PRS_DEBUG_OPTION" off
fi

quote_shell_word() {
    quoted=$(printf '%s' "$1" | sed "s/'/'\\\\''/g")
    printf "'%s'" "$quoted"
}

dispatch_command=$(quote_shell_word "$SCRIPT_DIR/dispatch.sh")
hook_index=9871

"$PRS_TMUX" set-hook -g "window-layout-changed[$hook_index]" \
    "run-shell -b \"$dispatch_command layout '#{hook_window}'\""
"$PRS_TMUX" set-hook -g "window-resized[$hook_index]" \
    "run-shell -b \"$dispatch_command resize '#{hook_window}'\""
"$PRS_TMUX" set-hook -g "after-new-window[$hook_index]" \
    "run-shell -b \"$dispatch_command init '#{hook_window}'\""
"$PRS_TMUX" set-hook -g "session-created[$hook_index]" \
    "run-shell -b \"$dispatch_command init '#{hook_window}'\""
"$PRS_TMUX" set-hook -g "window-linked[$hook_index]" \
    "run-shell -b \"$dispatch_command init '#{hook_window}'\""

# Explicit command hooks feed the same state machine. Duplicate notifications
# are safe because last-applied-layout makes them no-ops.
for layout_hook in \
    after-split-window \
    after-kill-pane \
    after-resize-pane \
    after-select-layout
do
    "$PRS_TMUX" set-hook -g "${layout_hook}[$hook_index]" \
        "run-shell -b \"$dispatch_command layout '#{hook_window}'\""
done

# Window IDs are server-global. De-duplicating them avoids reinitializing a
# linked window once per session, and init preserves every complete state.
"$PRS_TMUX" list-windows -a -F '#{window_id}' 2>/dev/null | sort -u |
while IFS= read -r window_id; do
    [ -n "$window_id" ] || continue
    "$SCRIPT_DIR/dispatch.sh" init "$window_id" || :
done
