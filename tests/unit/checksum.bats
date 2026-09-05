#!/usr/bin/env bats

setup() {
  load ../helpers.bash
  ROOT=$(project_root)
}

@test "calculates known tmux checksum" {
  body='120x40,0,0{60x40,0,0,0,59x40,61,0[59x20,61,0,1,59x19,61,21,2]}'
  run sh -c "printf '%s' '$body' | '$ROOT/lib/checksum.sh'"
  [ "$status" -eq 0 ]
  [ "$output" = '95e4' ]
}

@test "empty input has a zero checksum" {
  run sh -c "printf '' | '$ROOT/lib/checksum.sh'"
  [ "$status" -eq 0 ]
  [ "$output" = '0000' ]
}

@test "checksum is independent of locale" {
  body='80x24,0,0[80x12,0,0,0,80x11,0,13,1]'
  expected=$(printf '%s' "$body" | "$ROOT/lib/checksum.sh")
  run sh -c "LC_ALL=C printf '%s' '$body' | '$ROOT/lib/checksum.sh'"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}
