#!/usr/bin/env bats

setup() {
  load ../helpers.bash
  ROOT=$(project_root)
  AWK_SCRIPT="$ROOT/lib/scale-layout.awk"
}

signature() {
  checksum_layout "$1" | awk -v mode=signature -f "$AWK_SCRIPT"
}

@test "signature omits geometry" {
  run signature '100x30,0,0{69x30,0,0,0,30x30,70,0,1}'
  [ "$status" -eq 0 ]
  first=$output
  run signature '200x60,0,0{139x60,0,0,0,60x60,140,0,1}'
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
  [ "$output" = 'LR(LEAF:0,LEAF:1)' ]
}

@test "orientation, order, and pane ids affect signature" {
  lr=$(signature '80x24,0,0{40x24,0,0,0,39x24,41,0,1}')
  tb=$(signature '80x24,0,0[80x12,0,0,0,80x11,0,13,1]')
  swapped=$(signature '80x24,0,0{40x24,0,0,1,39x24,41,0,0}')
  other=$(signature '80x24,0,0{40x24,0,0,0,39x24,41,0,2}')
  [ "$lr" != "$tb" ]
  [ "$lr" != "$swapped" ]
  [ "$lr" != "$other" ]
}
