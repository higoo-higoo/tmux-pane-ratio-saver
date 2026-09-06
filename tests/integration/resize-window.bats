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

@test "window resize restores the reference split ratios" {
  reference=$(window_option @0 @pane-ratio-saver-reference-layout)

  tmux_test resize-window -t @0 -x 200 -y 60
  wait_until state_is_settled @0 200x60

  actual=$(window_layout @0)
  expected=$(scale_for_current_root "$reference" "$actual")
  [ "$actual" = "$expected" ]
  [ "$(window_option @0 @pane-ratio-saver-reference-layout)" = "$reference" ]
}

@test "repeated resizes do not accumulate rounding drift" {
  reference=$(window_option @0 @pane-ratio-saver-reference-layout)

  i=0
  while [ "$i" -lt 110 ]; do
    width=$((73 + (i * 47) % 128))
    height=$((25 + (i * 13) % 40))
    tmux_test resize-window -t @0 -x "$width" -y "$height"
    wait_until state_is_settled @0 "${width}x${height}"
    i=$((i + 1))
  done

  tmux_test resize-window -t @0 -x 120 -y 40
  wait_until state_is_settled @0 120x40
  [ "$(window_layout @0)" = "$reference" ]
  [ "$(window_option @0 @pane-ratio-saver-reference-layout)" = "$reference" ]
}
