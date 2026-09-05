#!/usr/bin/env bats

setup() {
  load ../helpers.bash
  ROOT=$(project_root)
  AWK_SCRIPT="$ROOT/lib/scale-layout.awk"
}

scale_bodies() {
  reference=$(checksum_layout "$1")
  current=$(checksum_layout "$2")
  printf '%s\n%s\n' "$reference" "$current" | awk -v mode=scale -f "$AWK_SCRIPT"
}

@test "scales an 80:20 split with largest remainder rounding" {
  run scale_bodies \
    '120x40,0,0{89x40,0,0,0,30x40,90,0,1}' \
    '200x40,0,0{100x40,0,0,0,99x40,101,0,1}'
  [ "$status" -eq 0 ]
  expected=$(checksum_layout '200x40,0,0{149x40,0,0,0,50x40,150,0,1}')
  [ "$output" = "$expected" ]
}

@test "ties are resolved in original child order" {
  run scale_bodies \
    '5x10,0,0{2x10,0,0,0,2x10,3,0,1}' \
    '6x10,0,0{3x10,0,0,0,2x10,4,0,1}'
  [ "$status" -eq 0 ]
  expected=$(checksum_layout '6x10,0,0{3x10,0,0,0,2x10,4,0,1}')
  [ "$output" = "$expected" ]
}

@test "supports three siblings and simultaneous width and height changes" {
  run scale_bodies \
    '32x20,0,0{10x20,0,0,0,10x20,11,0,1,10x20,22,0,2}' \
    '42x30,3,4{14x30,3,4,0,13x30,18,4,1,13x30,32,4,2}'
  [ "$status" -eq 0 ]
  expected=$(checksum_layout '42x30,3,4{14x30,3,4,0,13x30,18,4,1,13x30,32,4,2}')
  [ "$output" = "$expected" ]
}

@test "recursively scales nested splits" {
  run scale_bodies \
    '120x40,0,0{60x40,0,0,0,59x40,61,0[59x20,61,0,1,59x19,61,21,2]}' \
    '200x80,0,0{100x80,0,0,0,99x80,101,0[99x40,101,0,1,99x39,101,41,2]}'
  [ "$status" -eq 0 ]
  expected=$(checksum_layout '200x80,0,0{100x80,0,0,0,99x80,101,0[99x41,101,0,1,99x38,101,42,2]}')
  [ "$output" = "$expected" ]
}

@test "bounded allocation clamps a child to its subtree minimum" {
  run scale_bodies \
    '104x10,0,0{100x10,0,0,0,3x10,101,0{1x10,101,0,1,1x10,103,0,2}}' \
    '7x10,0,0{3x10,0,0,0,3x10,4,0{1x10,4,0,1,1x10,6,0,2}}'
  [ "$status" -eq 0 ]
  expected=$(checksum_layout '7x10,0,0{3x10,0,0,0,3x10,4,0{1x10,4,0,1,1x10,6,0,2}}')
  [ "$output" = "$expected" ]
}

@test "fails when an explicit target is smaller than the topology minimum" {
  layout=$(checksum_layout '5x10,0,0{2x10,0,0,0,2x10,3,0,1}')
  run sh -c "printf '%s\n%s\n' '$layout' '$layout' | awk -v mode=scale -v target_width=2 -f '$AWK_SCRIPT'"
  [ "$status" -eq 4 ]
}

@test "does not scale across a topology change" {
  reference=$(checksum_layout '80x24,0,0{40x24,0,0,0,39x24,41,0,1}')
  current=$(checksum_layout '80x24,0,0[80x12,0,0,0,80x11,0,13,1]')
  run sh -c "printf '%s\n%s\n' '$reference' '$current' | awk -v mode=scale -f '$AWK_SCRIPT'"
  [ "$status" -eq 3 ]
}
