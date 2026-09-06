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

@test "resize remains pending until the window is unzoomed" {
  reference=$(window_option @0 @pane-ratio-saver-reference-layout)
  tmux_test resize-pane -Z -t %0
  tmux_test resize-window -t @0 -x 170 -y 55

  wait_until option_equals @0 @pane-ratio-saver-pending-resize 1
  [ "$(tmux_test display-message -p -t @0 '#{window_zoomed_flag}')" = 1 ]
  [ "$(window_option @0 @pane-ratio-saver-reference-layout)" = "$reference" ]

  tmux_test resize-pane -Z -t %0
  wait_until state_is_settled @0 170x55
  [ "$(tmux_test display-message -p -t @0 '#{window_zoomed_flag}')" = 0 ]
  actual=$(window_layout @0)
  [ "$actual" = "$(scale_for_current_root "$reference" "$actual")" ]
  [ "$(window_option @0 @pane-ratio-saver-reference-layout)" = "$reference" ]
}
