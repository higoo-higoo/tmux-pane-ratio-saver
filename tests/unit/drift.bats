#!/usr/bin/env bats

setup() {
  load ../helpers.bash
  ROOT=$(project_root)
  AWK_SCRIPT="$ROOT/lib/scale-layout.awk"
}

make_current() {
  width=$1
  left=$(( (width - 1) / 2 ))
  right=$(( width - left - 1 ))
  checksum_layout "${width}x40,0,0{${left}x40,0,0,0,${right}x40,$((left + 1)),0,1}"
}

@test "every resize is derived from the immutable reference" {
  reference_body='120x40,0,0{89x40,0,0,0,30x40,90,0,1}'
  reference=$(checksum_layout "$reference_body")

  for width in 120 121 119 160 73 120; do
    current=$(make_current "$width")
    result=$(printf '%s\n%s\n' "$reference" "$current" | awk -v mode=scale -f "$AWK_SCRIPT")
  done
  [ "$result" = "$reference" ]

  i=0
  while [ "$i" -lt 120 ]; do
    width=$((73 + (i * 47) % 128))
    current=$(make_current "$width")
    result=$(printf '%s\n%s\n' "$reference" "$current" | awk -v mode=scale -f "$AWK_SCRIPT")
    i=$((i + 1))
  done
  current=$(make_current 120)
  result=$(printf '%s\n%s\n' "$reference" "$current" | awk -v mode=scale -f "$AWK_SCRIPT")
  [ "$result" = "$reference" ]
}
