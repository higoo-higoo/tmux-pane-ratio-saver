#!/bin/sh

PRS_TMUX=${PRS_TMUX:-tmux}
PRS_STATE_VERSION=1
PRS_REFERENCE_OPTION='@pane-ratio-saver-reference-layout'
PRS_LAST_SIZE_OPTION='@pane-ratio-saver-last-size'
PRS_LAST_APPLIED_OPTION='@pane-ratio-saver-last-applied-layout'
PRS_PENDING_OPTION='@pane-ratio-saver-pending-resize'
PRS_VERSION_OPTION='@pane-ratio-saver-state-version'
PRS_ENABLED_OPTION='@pane-ratio-saver-enabled'
PRS_DEBUG_OPTION='@pane-ratio-saver-debug'
PRS_AWK=${PRS_AWK:-"$PRS_ROOT/lib/scale-layout.awk"}

get_window_option() {
    "$PRS_TMUX" show-options -wqv -t "$1" "$2" 2>/dev/null
}

set_window_option() {
    "$PRS_TMUX" set-option -wq -t "$1" "$2" "$3"
}

unset_window_option() {
    "$PRS_TMUX" set-option -wqu -t "$1" "$2" 2>/dev/null || :
}

plugin_enabled() {
    enabled=$(get_window_option "$1" "$PRS_ENABLED_OPTION")
    [ "${enabled:-on}" = "on" ]
}

debug_enabled() {
    debug_value=$(get_window_option "$1" "$PRS_DEBUG_OPTION")
    [ "${debug_value:-off}" = "on" ]
}

debug_log() {
    debug_window=$1
    shift
    if debug_enabled "$debug_window"; then
        "$PRS_TMUX" display-message -t "$debug_window" "pane-ratio-saver: $*" >/dev/null 2>&1 || :
    fi
}

read_snapshot() {
    snapshot=$(
        "$PRS_TMUX" display-message -p -t "$1" \
            '#{window_width}|#{window_height}|#{window_zoomed_flag}|#{window_layout}' 2>/dev/null
    ) || return 1

    PRS_WIDTH=${snapshot%%|*}
    snapshot_rest=${snapshot#*|}
    PRS_HEIGHT=${snapshot_rest%%|*}
    snapshot_rest=${snapshot_rest#*|}
    PRS_ZOOMED=${snapshot_rest%%|*}
    PRS_LAYOUT=${snapshot_rest#*|}
    PRS_SIZE="${PRS_WIDTH}x${PRS_HEIGHT}"

    case $PRS_WIDTH in ''|*[!0-9]*) return 1 ;; esac
    case $PRS_HEIGHT in ''|*[!0-9]*) return 1 ;; esac
    case $PRS_ZOOMED in 0|1) ;; *) return 1 ;; esac
    [ "$PRS_WIDTH" -gt 0 ] && [ "$PRS_HEIGHT" -gt 0 ] || return 1
    [ -n "$PRS_LAYOUT" ]
}

load_state() {
    state_window=$1
    PRS_REFERENCE=$(get_window_option "$state_window" "$PRS_REFERENCE_OPTION")
    PRS_LAST_SIZE=$(get_window_option "$state_window" "$PRS_LAST_SIZE_OPTION")
    PRS_LAST_APPLIED=$(get_window_option "$state_window" "$PRS_LAST_APPLIED_OPTION")
    PRS_PENDING=$(get_window_option "$state_window" "$PRS_PENDING_OPTION")
    PRS_VERSION=$(get_window_option "$state_window" "$PRS_VERSION_OPTION")
}

state_is_complete() {
    [ "$PRS_VERSION" = "$PRS_STATE_VERSION" ] &&
        [ -n "$PRS_REFERENCE" ] &&
        [ -n "$PRS_LAST_SIZE" ] &&
        [ -n "$PRS_LAST_APPLIED" ] &&
        case $PRS_LAST_SIZE in
            *[!0-9x]*|x*|*x|*x*x*) false ;;
            *)
                state_width=${PRS_LAST_SIZE%%x*}
                state_height=${PRS_LAST_SIZE#*x}
                [ "$state_width" -gt 0 ] && [ "$state_height" -gt 0 ]
                ;;
        esac
}

validate_layout() {
    printf '%s\n' "$1" | awk -v mode=validate -f "$PRS_AWK" >/dev/null 2>&1
}

layout_signature() {
    printf '%s\n' "$1" | awk -v mode=signature -f "$PRS_AWK" 2>/dev/null
}

scale_layout() {
    printf '%s\n%s\n' "$1" "$2" | awk -v mode=scale -f "$PRS_AWK" 2>/dev/null
}

clear_state_locked() {
    clear_window=$1
    unset_window_option "$clear_window" "$PRS_REFERENCE_OPTION"
    unset_window_option "$clear_window" "$PRS_LAST_SIZE_OPTION"
    unset_window_option "$clear_window" "$PRS_LAST_APPLIED_OPTION"
    unset_window_option "$clear_window" "$PRS_PENDING_OPTION"
    unset_window_option "$clear_window" "$PRS_VERSION_OPTION"
}

capture_snapshot_locked() {
    capture_window=$1
    if [ "$PRS_ZOOMED" = "1" ]; then
        debug_log "$capture_window" "not capturing a reference while zoomed"
        return 1
    fi
    if ! validate_layout "$PRS_LAYOUT"; then
        debug_log "$capture_window" "current layout is unsupported or invalid"
        return 1
    fi

    # The version is written last so a partially updated state is never valid.
    unset_window_option "$capture_window" "$PRS_VERSION_OPTION"
    set_window_option "$capture_window" "$PRS_REFERENCE_OPTION" "$PRS_LAYOUT" || return 1
    set_window_option "$capture_window" "$PRS_LAST_SIZE_OPTION" "$PRS_SIZE" || return 1
    set_window_option "$capture_window" "$PRS_LAST_APPLIED_OPTION" "$PRS_LAYOUT" || return 1
    unset_window_option "$capture_window" "$PRS_PENDING_OPTION"
    set_window_option "$capture_window" "$PRS_VERSION_OPTION" "$PRS_STATE_VERSION"
}

capture_current_locked() {
    capture_window=$1
    read_snapshot "$capture_window" || return 1
    capture_snapshot_locked "$capture_window"
}

update_observation() {
    observation_window=$1
    observation_size=$2
    observation_layout=$3
    set_window_option "$observation_window" "$PRS_LAST_SIZE_OPTION" "$observation_size" || return 1
    set_window_option "$observation_window" "$PRS_LAST_APPLIED_OPTION" "$observation_layout"
}

restore_snapshot_locked() {
    restore_window=$1

    if ! validate_layout "$PRS_REFERENCE" || ! validate_layout "$PRS_LAYOUT"; then
        debug_log "$restore_window" "reference or current layout is unsupported or invalid"
        update_observation "$restore_window" "$PRS_SIZE" "$PRS_LAYOUT"
        return 1
    fi

    reference_signature=$(layout_signature "$PRS_REFERENCE") || return 1
    current_signature=$(layout_signature "$PRS_LAYOUT") || return 1
    if [ "$reference_signature" != "$current_signature" ]; then
        debug_log "$restore_window" "pane topology changed; capturing a new reference"
        capture_snapshot_locked "$restore_window"
        return $?
    fi

    target_layout=$(scale_layout "$PRS_REFERENCE" "$PRS_LAYOUT")
    scale_status=$?
    if [ "$scale_status" -ne 0 ] || [ -z "$target_layout" ]; then
        debug_log "$restore_window" "layout cannot be scaled to ${PRS_SIZE}"
        update_observation "$restore_window" "$PRS_SIZE" "$PRS_LAYOUT"
        return 1
    fi

    # Record the intended result before select-layout. Any hook generated by
    # tmux can then identify the plugin's own layout change after taking lock.
    update_observation "$restore_window" "$PRS_SIZE" "$target_layout" || return 1
    if ! "$PRS_TMUX" select-layout -t "$restore_window" "$target_layout" >/dev/null 2>&1; then
        debug_log "$restore_window" "select-layout failed"
        if read_snapshot "$restore_window"; then
            update_observation "$restore_window" "$PRS_SIZE" "$PRS_LAYOUT" || :
        fi
        return 1
    fi

    if ! read_snapshot "$restore_window"; then
        return 1
    fi
    update_observation "$restore_window" "$PRS_SIZE" "$PRS_LAYOUT" || return 1
    unset_window_option "$restore_window" "$PRS_PENDING_OPTION"
    return 0
}

lock_window() {
    lock_id=${1#@}
    PRS_LOCK_NAME="pane-ratio-saver-$lock_id"
    "$PRS_TMUX" wait-for -L "$PRS_LOCK_NAME"
}

unlock_window() {
    if [ -n "${PRS_LOCK_NAME:-}" ]; then
        "$PRS_TMUX" wait-for -U "$PRS_LOCK_NAME" 2>/dev/null || :
        PRS_LOCK_NAME=
    fi
}
