#!/usr/bin/env bats

setup() {
  load ../helpers.bash
  ROOT=$(project_root)
  AWK_SCRIPT="$ROOT/lib/scale-layout.awk"
}

@test "canonical layouts round trip byte-for-byte" {
  for body in \
    '80x24,0,0,0' \
    '120x40,0,0{89x40,0,0,0,30x40,90,0,1}' \
    '120x40,0,0{60x40,0,0,0,59x40,61,0[59x20,61,0,1,59x19,61,21,2]}'
  do
    layout=$(checksum_layout "$body")
    run sh -c "printf '%s\n' '$layout' | awk -v mode=serialize -f '$AWK_SCRIPT'"
    [ "$status" -eq 0 ]
    [ "$output" = "$layout" ]
  done
}
