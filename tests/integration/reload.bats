#!/usr/bin/env bats

setup() {
  load ../helpers.bash
  ROOT=$(project_root)
  start_tmux 120 40
  tmux_test split-window -h -l 25%
  load_plugin
}

teardown() {
  stop_tmux
}

@test "plugin reload preserves state and replaces only its indexed hooks" {
  tmux_test resize-pane -t %0 -R 7
  wait_until reference_matches_layout @0
  reference=$(window_option @0 @pane-ratio-saver-reference-layout)

  tmux_test run-shell "$ROOT/tmux-pane-ratio-saver.tmux"
  tmux_test run-shell "$ROOT/tmux-pane-ratio-saver.tmux"
  [ "$(window_option @0 @pane-ratio-saver-reference-layout)" = "$reference" ]

  run tmux_test show-hooks -g 'window-resized[9871]'
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
  [[ "$output" == *"dispatch.sh' resize"* ]]

  tmux_test resize-window -t @0 -x 190 -y 65
  wait_until state_is_settled @0 190x65
  actual=$(window_layout @0)
  [ "$actual" = "$(scale_for_current_root "$reference" "$actual")" ]
}

@test "plugin reload replaces an invalid saved state" {
  current=$(window_layout @0)
  tmux_test set-option -w -t @0 @pane-ratio-saver-reference-layout '0000,broken'
  tmux_test set-option -w -t @0 @pane-ratio-saver-last-applied-layout '0000,broken'

  tmux_test run-shell "$ROOT/tmux-pane-ratio-saver.tmux"
  [ "$(window_option @0 @pane-ratio-saver-reference-layout)" = "$current" ]
  [ "$(window_option @0 @pane-ratio-saver-last-applied-layout)" = "$current" ]
  [ "$(window_option @0 @pane-ratio-saver-state-version)" = 1 ]
}

@test "new and linked windows initialize state once per window id" {
  first_reference=$(window_option @0 @pane-ratio-saver-reference-layout)
  tmux_test new-session -d -s secondary -x 80 -y 24
  wait_until option_equals @1 @pane-ratio-saver-state-version 1

  tmux_test link-window -s @0 -t secondary:
  wait_until option_equals @0 @pane-ratio-saver-state-version 1
  [ "$(window_option @0 @pane-ratio-saver-reference-layout)" = "$first_reference" ]

  occurrences=$(tmux_test list-windows -a -F '#{window_id}' | awk '$0 == "@0" { count++ } END { print count + 0 }')
  [ "$occurrences" -eq 2 ]
}
