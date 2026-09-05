#!/bin/sh

set -u

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
PRS_ROOT=$(CDPATH='' cd "$SCRIPT_DIR/.." && pwd)
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

window_id=${1:-}
[ -n "$window_id" ] || exit 2

lock_window "$window_id" || exit 1
trap 'unlock_window' EXIT HUP INT TERM
clear_state_locked "$window_id"
