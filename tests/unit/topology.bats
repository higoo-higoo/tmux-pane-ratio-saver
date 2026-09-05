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

@test "rebind preserves geometry while adopting a pane permutation" {
  reference=$(checksum_layout '80x24,0,0{59x24,0,0,0,20x24,60,0,1}')
  current=$(checksum_layout '120x40,0,0{60x40,0,0,1,59x40,61,0,0}')
  run sh -c "printf '%s\n%s\n' '$reference' '$current' | awk -v mode=rebind -f '$AWK_SCRIPT'"
  [ "$status" -eq 0 ]
  expected=$(checksum_layout '80x24,0,0{59x24,0,0,1,20x24,60,0,0}')
  [ "$output" = "$expected" ]
}

@test "rebind rejects a different structure or pane set" {
  reference=$(checksum_layout '80x24,0,0{40x24,0,0,0,39x24,41,0,1}')
  current=$(checksum_layout '80x24,0,0[80x12,0,0,0,80x11,0,13,1]')
  run sh -c "printf '%s\n%s\n' '$reference' '$current' | awk -v mode=rebind -f '$AWK_SCRIPT'"
  [ "$status" -eq 3 ]

  current=$(checksum_layout '80x24,0,0{40x24,0,0,0,39x24,41,0,2}')
  run sh -c "printf '%s\n%s\n' '$reference' '$current' | awk -v mode=rebind -f '$AWK_SCRIPT'"
  [ "$status" -eq 3 ]
}
