#!/usr/bin/env bats

setup() {
  load ../helpers.bash
  ROOT=$(project_root)
  AWK_SCRIPT="$ROOT/lib/scale-layout.awk"
}

validate_body() {
  layout=$(checksum_layout "$1")
  printf '%s\n' "$layout" | awk -v mode=validate -f "$AWK_SCRIPT"
}

@test "accepts single pane and multi-digit pane ids" {
  run validate_body '80x24,0,0,42'
  [ "$status" -eq 0 ]
}

@test "accepts left-right, top-bottom, and nested trees" {
  run validate_body '120x40,0,0{60x40,0,0,0,59x40,61,0[59x20,61,0,1,59x19,61,21,2]}'
  [ "$status" -eq 0 ]

  run validate_body '80x24,0,0{40x24,0,0[40x12,0,0,0,40x11,0,13,1],39x24,41,0[39x12,41,0,2,39x11,41,13,3]}'
  [ "$status" -eq 0 ]
}

@test "rejects a bad checksum" {
  run sh -c "printf '%s\n' '0000,80x24,0,0,0' | awk -v mode=validate -f '$AWK_SCRIPT'"
  [ "$status" -ne 0 ]
}

@test "rejects malformed input" {
  for body in \
    '80x24,0,0{40x24,0,0,0,39x24,41,0,1' \
    '80x,0,0,0' \
    '80x24,0,0,0garbage'
  do
    run validate_body "$body"
    [ "$status" -ne 0 ]
  done
}

@test "rejects duplicate pane ids" {
  run validate_body '80x24,0,0{40x24,0,0,7,39x24,41,0,7}'
  [ "$status" -ne 0 ]
}

@test "rejects inconsistent child sizes and offsets" {
  run validate_body '80x24,0,0{40x24,0,0,0,39x24,40,0,1}'
  [ "$status" -ne 0 ]

  run validate_body '80x24,0,0[79x12,0,0,0,79x11,0,13,1]'
  [ "$status" -ne 0 ]
}

@test "rejects unsupported layout tokens" {
  run validate_body '80x24,0,0<80x24,0,0,0>'
  [ "$status" -ne 0 ]
}
