#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/project/scripts"
  export RTK_TEST_ROOT="$(cd "$TEST_TEMP_DIR/project" && pwd -P)"
  cp "$SCRIPTS_DIR/rtk-manager.sh" "$RTK_TEST_ROOT/scripts/rtk-manager.sh"
  chmod +x "$RTK_TEST_ROOT/scripts/rtk-manager.sh"
  export LBWC_RTK_DIR="$RTK_TEST_ROOT/.lbwc-planning/tools/rtk"
  export LBWC_RTK_BINARY="$LBWC_RTK_DIR/rtk"
  export LBWC_RTK_RECEIPT="$LBWC_RTK_DIR/rtk-install.json"
  export LBWC_RTK_BACKUPS="$LBWC_RTK_DIR/backups"
  export RTK_REPO_API='https://fixture.invalid/release.json'
  export PATH="$TEST_TEMP_DIR/bin:$PATH"
  mkdir -p "$TEST_TEMP_DIR/bin" "$TEST_TEMP_DIR/release/payload"
  write_fake_claude
  write_fake_curl
  prepare_release
}

teardown() {
  teardown_temp_dir
}

manager() {
  bash "$RTK_TEST_ROOT/scripts/rtk-manager.sh" "$@"
}

target_name() {
  case "$(uname -s):$(uname -m)" in
    Darwin:arm64|Darwin:aarch64) printf '%s\n' 'aarch64-apple-darwin' ;;
    Darwin:x86_64) printf '%s\n' 'x86_64-apple-darwin' ;;
    Linux:arm64|Linux:aarch64) printf '%s\n' 'aarch64-unknown-linux-gnu' ;;
    *) printf '%s\n' 'x86_64-unknown-linux-musl' ;;
  esac
}

sha256_value() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

write_fake_claude() {
  cat > "$TEST_TEMP_DIR/bin/claude" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = --version ] || exit 2
printf 'Claude Code fixture\n'
EOF
  chmod +x "$TEST_TEMP_DIR/bin/claude"
}

write_fake_curl() {
  cat > "$TEST_TEMP_DIR/bin/curl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
url=''
output=''
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    -o) output="\$2"; shift 2 ;;
    --max-time) shift 2 ;;
    -*) shift ;;
    *) url="\$1"; shift ;;
  esac
done
case "\$url" in
  https://fixture.invalid/release.json) source="$TEST_TEMP_DIR/release/release.json" ;;
  https://fixture.invalid/checksums.txt) source="$TEST_TEMP_DIR/release/checksums.txt" ;;
  https://fixture.invalid/*.tar.gz) source="$TEST_TEMP_DIR/release/archive.tar.gz" ;;
  *) exit 44 ;;
esac
if [ -n "\$output" ]; then
  cp "\$source" "\$output"
else
  cat "\$source"
fi
EOF
  chmod +x "$TEST_TEMP_DIR/bin/curl"
}

prepare_release() {
  local target asset checksum
  target="$(target_name)"
  asset="rtk-${target}.tar.gz"
  cat > "$TEST_TEMP_DIR/release/payload/rtk" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --version) printf 'rtk 9.9.9\n' ;;
  proxy)
    [ "${RTK_FIXTURE_PROXY_FAILURE:-false}" = true ] && exit 81
    shift
    "$@"
    ;;
  *) exit 2 ;;
esac
EOF
  chmod +x "$TEST_TEMP_DIR/release/payload/rtk"
  tar -czf "$TEST_TEMP_DIR/release/archive.tar.gz" -C "$TEST_TEMP_DIR/release/payload" rtk
  checksum="$(sha256_value "$TEST_TEMP_DIR/release/archive.tar.gz")"
  printf '%s  %s\n' "$checksum" "$asset" > "$TEST_TEMP_DIR/release/checksums.txt"
  cat > "$TEST_TEMP_DIR/release/release.json" <<EOF
{"tag_name":"v9.9.9","assets":[
  {"name":"$asset","browser_download_url":"https://fixture.invalid/$asset"},
  {"name":"checksums.txt","browser_download_url":"https://fixture.invalid/checksums.txt"}
]}
EOF
}

@test "rtk-manager: status reports a missing project-local install" {
  run manager status --json

  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.installed')" = false ]
  [ "$(printf '%s' "$output" | jq -r '.binary')" = "$LBWC_RTK_BINARY" ]
}

@test "rtk-manager: install requires explicit confirmation" {
  run manager install

  [ "$status" -eq 2 ]
  [[ "$output" == *'install requires --yes'* ]]
  [ ! -e "$LBWC_RTK_BINARY" ]
}

@test "rtk-manager: update requires explicit confirmation" {
  run manager update

  [ "$status" -eq 2 ]
  [[ "$output" == *'update requires --yes'* ]]
}

@test "rtk-manager: uninstall requires explicit confirmation" {
  run manager uninstall

  [ "$status" -eq 2 ]
  [[ "$output" == *'uninstall requires --yes'* ]]
}

@test "rtk-manager: rejects state paths outside the project" {
  run env LBWC_RTK_DIR="$TEST_TEMP_DIR/outside" bash "$RTK_TEST_ROOT/scripts/rtk-manager.sh" status

  [ "$status" -eq 2 ]
  [[ "$output" == *'state must stay inside this project'* ]]
}

@test "rtk-manager: rejects project paths that traverse a symbolic link" {
  mkdir -p "$TEST_TEMP_DIR/outside"
  ln -s "$TEST_TEMP_DIR/outside" "$RTK_TEST_ROOT/escape"

  run env -u LBWC_RTK_BINARY -u LBWC_RTK_RECEIPT -u LBWC_RTK_BACKUPS LBWC_RTK_DIR="$RTK_TEST_ROOT/escape/rtk" bash "$RTK_TEST_ROOT/scripts/rtk-manager.sh" install --yes

  [ "$status" -eq 2 ]
  [[ "$output" == *'may not traverse symbolic links'* ]]
  [ ! -e "$TEST_TEMP_DIR/outside/rtk" ]
}

@test "rtk-manager: dry-run validates a checksummed release without writing state" {
  run manager install --yes --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *'dry-run: install RTK v9.9.9'* ]]
  [ ! -e "$LBWC_RTK_BINARY" ]
  [ ! -e "$LBWC_RTK_RECEIPT" ]
}

@test "rtk-manager: install writes a receipt and verify runs the smoke check" {
  run manager install --yes

  [ "$status" -eq 0 ]
  [ -x "$LBWC_RTK_BINARY" ]
  [ -f "$LBWC_RTK_RECEIPT" ]
  [ "$(jq -r '.release.tag' "$LBWC_RTK_RECEIPT")" = v9.9.9 ]
  [ "$(jq -r '.claude_code_smoke' "$LBWC_RTK_RECEIPT")" = available ]

  run manager verify --json

  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.verified')" = true ]
  [ "$(printf '%s' "$output" | jq -r '.claude_code_smoke')" = available ]
}

@test "rtk-manager: update creates a unique backup before replacement" {
  manager install --yes
  printf 'old binary\n' > "$LBWC_RTK_BINARY"
  chmod +x "$LBWC_RTK_BINARY"

  run manager update --yes

  [ "$status" -eq 0 ]
  [ "$(find "$LBWC_RTK_BACKUPS" -type f -name rtk | wc -l | tr -d '[:space:]')" = 1 ]
  [ "$(find "$LBWC_RTK_BACKUPS" -type f -name rtk-install.json | wc -l | tr -d '[:space:]')" = 1 ]
  "$LBWC_RTK_BINARY" --version
}

@test "rtk-manager: backup creation failure preserves the current install" {
  manager install --yes
  before_binary="$(sha256_value "$LBWC_RTK_BINARY")"
  before_receipt="$(sha256_value "$LBWC_RTK_RECEIPT")"
  printf 'blocked\n' > "$LBWC_RTK_DIR/blocked"
  export LBWC_RTK_BACKUPS="$LBWC_RTK_DIR/blocked"

  run manager update --yes

  [ "$status" -eq 2 ]
  [[ "$output" == *'could not create a backup'* ]]
  [ "$(sha256_value "$LBWC_RTK_BINARY")" = "$before_binary" ]
  [ "$(sha256_value "$LBWC_RTK_RECEIPT")" = "$before_receipt" ]
}

@test "rtk-manager: smoke failure rolls back the verified binary and receipt" {
  manager install --yes
  before_binary="$(sha256_value "$LBWC_RTK_BINARY")"
  before_receipt="$(sha256_value "$LBWC_RTK_RECEIPT")"
  export RTK_FIXTURE_PROXY_FAILURE=true

  run manager update --yes

  [ "$status" -eq 2 ]
  [[ "$output" == *'compatibility smoke check'* ]]
  [ "$(sha256_value "$LBWC_RTK_BINARY")" = "$before_binary" ]
  [ "$(sha256_value "$LBWC_RTK_RECEIPT")" = "$before_receipt" ]
}

@test "rtk-manager: checksum mismatch prevents installation" {
  printf '%064d  rtk-%s.tar.gz\n' 0 "$(target_name)" > "$TEST_TEMP_DIR/release/checksums.txt"

  run manager install --yes

  [ "$status" -eq 2 ]
  [[ "$output" == *'checksum mismatch'* ]]
  [ ! -e "$LBWC_RTK_BINARY" ]
}

@test "rtk-manager: unsafe archive paths prevent installation" {
  mkdir -p "$TEST_TEMP_DIR/unsafe/dir"
  printf 'bad\n' > "$TEST_TEMP_DIR/unsafe/rtk"
  tar -czf "$TEST_TEMP_DIR/release/archive.tar.gz" -C "$TEST_TEMP_DIR/unsafe" dir/../rtk
  printf '%s  rtk-%s.tar.gz\n' "$(sha256_value "$TEST_TEMP_DIR/release/archive.tar.gz")" "$(target_name)" > "$TEST_TEMP_DIR/release/checksums.txt"

  run manager install --yes

  [ "$status" -eq 2 ]
  [[ "$output" == *'unsafe or empty paths'* ]]
  [ ! -e "$LBWC_RTK_BINARY" ]
}

@test "rtk-manager: uninstall dry-run preserves state and confirmed uninstall keeps a backup" {
  manager install --yes

  run manager uninstall --yes --dry-run

  [ "$status" -eq 0 ]
  [ -x "$LBWC_RTK_BINARY" ]

  run manager uninstall --yes

  [ "$status" -eq 0 ]
  [ ! -e "$LBWC_RTK_BINARY" ]
  [ ! -e "$LBWC_RTK_RECEIPT" ]
  [ "$(find "$LBWC_RTK_BACKUPS" -type f -name rtk | wc -l | tr -d '[:space:]')" = 1 ]
}
