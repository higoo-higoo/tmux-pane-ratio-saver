project_root() {
  cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd
}

checksum_layout() {
  body=$1
  checksum=$(printf '%s' "$body" | "$(project_root)/lib/checksum.sh")
  printf '%s,%s\n' "$checksum" "$body"
}
