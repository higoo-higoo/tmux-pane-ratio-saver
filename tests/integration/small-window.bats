#!/usr/bin/env bats

setup() {
  load ../helpers.bash
  ROOT=$(project_root)
  start_tmux 20 10
  tmux_test split-window -h
  tmux_test split-window -h
  load_plugin
}

teardown() {
  stop_tmux
}

@test "a too-small resize request never discards the reference" {
  reference=$(window_option @0 @pane-ratio-saver-reference-layout)

  # tmux clamps the requested width to the structural minimum (five cells
  # for three leaves and two separators). The bounded allocator must keep all
  # subtrees valid without replacing the larger reference.
  tmux_test resize-window -t @0 -x 2 -y 2
  wait_until state_is_settled @0 5x2
  [ "$(window_option @0 @pane-ratio-saver-reference-layout)" = "$reference" ]

  tmux_test resize-window -t @0 -x 20 -y 10
  wait_until state_is_settled @0 20x10
  [ "$(window_layout @0)" = "$reference" ]
}

@test "a window-scoped off override disables resize handling" {
  reference=$(window_option @0 @pane-ratio-saver-reference-layout)
  last_size=$(window_option @0 @pane-ratio-saver-last-size)
  tmux_test set-option -w -t @0 @pane-ratio-saver-enabled off

  tmux_test resize-window -t @0 -x 40 -y 15
  sleep 0.2
  [ "$(window_option @0 @pane-ratio-saver-last-size)" = "$last_size" ]
  [ "$(window_option @0 @pane-ratio-saver-reference-layout)" = "$reference" ]
}
