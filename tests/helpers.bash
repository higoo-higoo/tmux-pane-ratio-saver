project_root() {
  cd "$(dirname "${BATS_TEST_FILENAME}")/../.." >/dev/null 2>&1 && pwd
}

checksum_layout() {
  body=$1
  checksum=$(printf '%s' "$body" | "$(project_root)/lib/checksum.sh")
  printf '%s,%s\n' "$checksum" "$body"
}

tmux_test() {
  tmux -L "$TMUX_TEST_SOCKET" "$@"
}

start_tmux() {
  local width=${1:-120}
  local height=${2:-40}
  TMUX_TEST_SOCKET="pane-ratio-saver-${BATS_TEST_NUMBER:-0}-$$"
  export TMUX_TEST_SOCKET
  tmux_test -f /dev/null new-session -d -s primary -x "$width" -y "$height"
}

stop_tmux() {
  tmux_test kill-server >/dev/null 2>&1 || true
}

load_plugin() {
  tmux_test run-shell "$ROOT/tmux-pane-ratio-saver.tmux"
  wait_until option_equals @0 @pane-ratio-saver-state-version 1
}

window_option() {
  tmux_test show-options -wqv -t "$1" "$2"
}

window_layout() {
  tmux_test display-message -p -t "$1" '#{window_layout}'
}

option_equals() {
  local actual
  actual=$(window_option "$1" "$2")
  [ "$actual" = "$3" ]
}

option_is_unset() {
  [ -z "$(window_option "$1" "$2")" ]
}

reference_matches_layout() {
  [ "$(window_option "$1" @pane-ratio-saver-reference-layout)" = "$(window_layout "$1")" ]
}

state_is_settled() {
  local target=$1
  local expected_size=$2
  [ "$(window_option "$target" @pane-ratio-saver-last-size)" = "$expected_size" ] &&
    [ "$(window_option "$target" @pane-ratio-saver-last-applied-layout)" = "$(window_layout "$target")" ] &&
    option_is_unset "$target" @pane-ratio-saver-pending-resize
}

wait_until() {
  local attempt=0
  while [ "$attempt" -lt 200 ]; do
    if "$@"; then
      return 0
    fi
    sleep 0.02
    attempt=$((attempt + 1))
  done
  return 1
}

scale_for_current_root() {
  local reference=$1
  local current=$2
  printf '%s\n%s\n' "$reference" "$current" |
    awk -v mode=scale -f "$ROOT/lib/scale-layout.awk"
}
