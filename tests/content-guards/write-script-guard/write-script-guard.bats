#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SCRIPT="$REPO_ROOT/content-guards/scripts/write-script-guard.sh"
  CURL_PATH="$(command -v curl)"
  BATS_RUN_DIR="$(dirname "$(dirname "$BATS_TEST_TMPDIR")")"
  TARGET_PATH="$BATS_RUN_DIR/new-tool-$BATS_TEST_NUMBER.py"
}

unused_endpoint() {
  local port
  port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
  printf 'http://127.0.0.1:%s/v1/chat/completions' "$port"
}

payload() {
  jq -n --arg fp "$TARGET_PATH" \
    --arg content '#!/bin/sh\nTHIS_CONTENT_MUST_NEVER_BE_LOGGED' \
    '{tool_input:{file_path:$fp,content:$content}}'
}

install_curl_counter() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'EOF'
#!/bin/sh
printf x >> "$GUARD_CURL_CALLS"
exec "$GUARD_REAL_CURL" "$@"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
}

@test "judge unreachable allows by default and logs only the file path" {
  local endpoint data_dir log_file
  endpoint="$(unused_endpoint)"
  data_dir="$BATS_TEST_TMPDIR/plugin-data"
  log_file="$data_dir/content-guards.log"

  run env -u CI GUARD_JUDGE_DOWN= GUARD_JUDGE_URL="$endpoint" \
    CLAUDE_PLUGIN_DATA="$data_dir" bash "$SCRIPT" <<< "$(payload)"

  [ "$status" -eq 0 ]
  [ -f "$log_file" ]
  [[ "$(cat "$log_file")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\ guard=write-script-guard\ decision=judge_down_allow\ path= ]]
  [[ "$(cat "$log_file")" == *"new-tool-$BATS_TEST_NUMBER.py" ]]
  [[ "$(cat "$log_file")" != *"THIS_CONTENT_MUST_NEVER_BE_LOGGED"* ]]
}

@test "judge unreachable blocks after one retry in fail-closed mode" {
  local endpoint data_dir log_file calls
  endpoint="$(unused_endpoint)"
  data_dir="$BATS_TEST_TMPDIR/plugin-data"
  log_file="$data_dir/content-guards.log"
  calls="$BATS_TEST_TMPDIR/curl-calls"
  install_curl_counter

  run env -u CI GUARD_JUDGE_DOWN=closed GUARD_JUDGE_URL="$endpoint" \
    CLAUDE_PLUGIN_DATA="$data_dir" GUARD_CURL_CALLS="$calls" \
    GUARD_REAL_CURL="$CURL_PATH" PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
    bash "$SCRIPT" <<< "$(payload)"

  [ "$status" -eq 2 ]
  [ "$(wc -c < "$calls" | tr -d ' ')" -eq 2 ]
  [[ "$output" == *"The script judge is unreachable and this environment fails closed."* ]]
  [[ "$output" == *"Actual exempt paths: scripts/, hooks/, .github/, tests/, test/, plugins/."* ]]
  [[ "$(cat "$log_file")" == *"decision=judge_down_block"* ]]
}
