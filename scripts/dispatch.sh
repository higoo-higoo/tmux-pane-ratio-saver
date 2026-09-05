#!/bin/sh

set -u

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
PRS_ROOT=$(CDPATH='' cd "$SCRIPT_DIR/.." && pwd)
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

event=${1:-}
window_id=${2:-}
case $event in
    init|layout|resize) ;;
    *) exit 2 ;;
esac
[ -n "$window_id" ] || exit 0

lock_window "$window_id" || exit 0
trap 'unlock_window' EXIT HUP INT TERM

plugin_enabled "$window_id" || exit 0
read_snapshot "$window_id" || exit 0
load_state "$window_id"

if [ "$event" = "init" ]; then
    if ! state_is_complete; then
        capture_snapshot_locked "$window_id" || :
    fi
    exit 0
fi

if ! state_is_complete; then
    capture_snapshot_locked "$window_id" || :
    exit 0
fi

if [ "$event" = "layout" ]; then
    if [ "$PRS_PENDING" = "1" ] && [ "$PRS_ZOOMED" = "0" ]; then
        restore_snapshot_locked "$window_id" || :
        exit 0
    fi

    if [ "$PRS_LAYOUT" = "$PRS_LAST_APPLIED" ] && [ "$PRS_SIZE" = "$PRS_LAST_SIZE" ]; then
        exit 0
    fi

    if ! validate_layout "$PRS_REFERENCE"; then
        debug_log "$window_id" "saved reference is invalid; capturing current layout"
        capture_snapshot_locked "$window_id" || :
        exit 0
    fi
    if ! validate_layout "$PRS_LAYOUT"; then
        debug_log "$window_id" "current layout is unsupported or invalid"
        exit 0
    fi

    reference_signature=$(layout_signature "$PRS_REFERENCE") || exit 0
    current_signature=$(layout_signature "$PRS_LAYOUT") || exit 0
    if [ "$reference_signature" != "$current_signature" ]; then
        # A pane permutation may have happened just before this resize without
        # its own tmux notification. Let the resize handler rebind pane order
        # while retaining the pre-resize geometry.
        if [ "$PRS_SIZE" != "$PRS_LAST_SIZE" ]; then
            exit 0
        fi
        capture_snapshot_locked "$window_id" || :
        exit 0
    fi

    # tmux may emit this before window-resized. Preserve the immutable
    # reference until the resize handler restores it.
    if [ "$PRS_SIZE" != "$PRS_LAST_SIZE" ]; then
        exit 0
    fi
    if [ "$PRS_ZOOMED" = "1" ]; then
        exit 0
    fi

    # Same topology and outer size, but different geometry: this is a manual
    # resize-pane or select-layout and becomes the new reference.
    capture_snapshot_locked "$window_id" || :
    exit 0
fi

# window-resized
if [ "$PRS_SIZE" = "$PRS_LAST_SIZE" ] && [ "$PRS_PENDING" != "1" ]; then
    exit 0
fi

if [ "$PRS_ZOOMED" = "1" ]; then
    set_window_option "$window_id" "$PRS_PENDING_OPTION" 1 || exit 0
    update_observation "$window_id" "$PRS_SIZE" "$PRS_LAYOUT" || :
    exit 0
fi

restore_snapshot_locked "$window_id" || :
