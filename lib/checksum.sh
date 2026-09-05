#!/bin/sh

# Calculate tmux's 16-bit layout checksum for the bytes read on stdin.
# The C locale is required so od always reports individual bytes.
LC_ALL=C od -An -tu1 | awk '
{
    for (i = 1; i <= NF; i++) {
        low_bit = checksum % 2
        checksum = int(checksum / 2) + low_bit * 32768
        checksum = (checksum + $i) % 65536
    }
}
END {
    printf "%04x\n", checksum
}
'
