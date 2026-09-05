#!/usr/bin/env bats

setup() {
  load ../helpers.bash
  ROOT=$(project_root)
  start_tmux 120 40
  tmux_test split-window -h -p 25
  load_plugin
}

teardown() {
  stop_tmux
}

@test "manual pane resize becomes the new reference" {
  tmux_test resize-window -t @0 -x 180 -y 50
  wait_until state_is_settled @0 180x50

  old_reference=$(window_option @0 @pane-ratio-saver-reference-layout)
  tmux_test resize-pane -t %0 -R 12
  wait_until reference_matches_layout @0
  new_reference=$(window_option @0 @pane-ratio-saver-reference-layout)
  [ "$new_reference" != "$old_reference" ]

  tmux_test resize-window -t @0 -x 220 -y 70
  wait_until state_is_settled @0 220x70
  actual=$(window_layout @0)
  [ "$actual" = "$(scale_for_current_root "$new_reference" "$actual")" ]
}

@test "split and kill capture topology instead of restoring the old tree" {
  tmux_test split-window -v -t %1
  wait_until reference_matches_layout @0
  split_reference=$(window_option @0 @pane-ratio-saver-reference-layout)
  [ "$(printf '%s\n' "$split_reference" | awk -v mode=signature -f "$ROOT/lib/scale-layout.awk")" = \
    'LR(LEAF:0,TB(LEAF:1,LEAF:2))' ]

  tmux_test kill-pane -t %2
  wait_until reference_matches_layout @0
  killed_reference=$(window_option @0 @pane-ratio-saver-reference-layout)
  [ "$killed_reference" != "$split_reference" ]
}

@test "swap and select-layout are respected as user changes" {
  tmux_test swap-pane -s %0 -t %1
  wait_until reference_matches_layout @0
  swapped=$(window_option @0 @pane-ratio-saver-reference-layout)
  signature=$(printf '%s\n' "$swapped" | awk -v mode=signature -f "$ROOT/lib/scale-layout.awk")
  [ "$signature" = 'LR(LEAF:1,LEAF:0)' ]

  tmux_test select-layout -t @0 even-horizontal >/dev/null
  wait_until reference_matches_layout @0
  [ "$(window_option @0 @pane-ratio-saver-reference-layout)" = "$(window_layout @0)" ]

  before_rotate=$(window_option @0 @pane-ratio-saver-reference-layout)
  tmux_test rotate-window -t @0
  rotated_layout=$(window_layout @0)
  expected_reference=$(
    printf '%s\n%s\n' "$before_rotate" "$rotated_layout" |
      awk -v mode=rebind -f "$ROOT/lib/scale-layout.awk"
  )

  # tmux versions that do not notify window-layout-changed for rotate-window
  # are handled on the next resize without losing the old split geometry.
  tmux_test resize-window -t @0 -x 190 -y 60
  wait_until state_is_settled @0 190x60
  [ "$(window_option @0 @pane-ratio-saver-reference-layout)" = "$expected_reference" ]
  actual=$(window_layout @0)
  [ "$actual" = "$(scale_for_current_root "$expected_reference" "$actual")" ]
}
