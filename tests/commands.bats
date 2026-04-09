#!/usr/bin/env bats
# Command tests using a file-based mocked curl — no real network calls.
#
# Responses are stored as files in a temp dir and consumed in order.
# File-based state persists correctly across subshells created by $(...).

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
FIXTURES="$SCRIPT_DIR/fixtures"

# shellcheck source=../tempo.sh
source "$SCRIPT_DIR/../tempo.sh"

# ── File-based mock curl ───────────────────────────────────────────────────────
# Each queued response is a pair of files: NNNN.code and NNNN.body.
# curl reads the lowest-numbered pair and deletes it after reading.
# Because rm affects the real filesystem, state is shared across all subshells.

_MOCK_DIR=""
_MOCK_SEQ=0

_mock_curl_reset() {
  [[ -n "$_MOCK_DIR" && -d "$_MOCK_DIR" ]] && rm -rf "$_MOCK_DIR"
  _MOCK_DIR=$(mktemp -d)
  _MOCK_SEQ=0
  export _MOCK_DIR  # must be exported so subshells can find it
}

_mock_curl_queue() {
  local body="$1" code="${2:-200}"
  local n; n=$(printf '%04d' "$_MOCK_SEQ")
  printf '%s' "$code" > "$_MOCK_DIR/${n}.code"
  printf '%s' "$body" > "$_MOCK_DIR/${n}.body"
  _MOCK_SEQ=$(( _MOCK_SEQ + 1 ))
}

curl() {
  local outfile="" args=("$@") i
  for (( i=0; i<${#args[@]}; i++ )); do
    [[ "${args[$i]}" == "-o" ]] && outfile="${args[$((i+1))]}"
  done

  local code="200" body="{}"
  if [[ -n "$_MOCK_DIR" && -d "$_MOCK_DIR" ]]; then
    local next_code
    next_code=$(ls "$_MOCK_DIR"/*.code 2>/dev/null | sort | head -1 || true)
    if [[ -n "$next_code" ]]; then
      code=$(cat "$next_code")
      local next_body="${next_code%.code}.body"
      [[ -f "$next_body" ]] && body=$(cat "$next_body")
      rm -f "$next_code" "$next_body"
    fi
  fi

  [[ -n "$outfile" ]] && printf '%s' "$body" > "$outfile"
  echo "$code"
}
export -f curl

# ── Setup / teardown ──────────────────────────────────────────────────────────

setup() {
  export TEMPO_API_TOKEN="test-tempo-token"
  export JIRA_URL="https://test.atlassian.net"
  export JIRA_EMAIL="test@example.com"
  export JIRA_API_TOKEN="test-jira-token"
  _mock_curl_reset
  _ACCOUNT_ID=""
  _detect_platform
}

teardown() {
  [[ -n "$_MOCK_DIR" && -d "$_MOCK_DIR" ]] && rm -rf "$_MOCK_DIR"
}

# ── cmd_config ────────────────────────────────────────────────────────────────

@test "cmd_config: shows masked tokens" {
  run cmd_config
  [ "$status" -eq 0 ]
  [[ "$output" =~ "test****" ]]
  [[ "$output" =~ "test.atlassian.net" ]]
  [[ "$output" =~ "test@example.com" ]]
}

@test "cmd_config: does not print full token values" {
  run cmd_config
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "test-tempo-token" ]]
  [[ ! "$output" =~ "test-jira-token" ]]
}

# ── cmd_get ───────────────────────────────────────────────────────────────────

@test "cmd_get: displays worklog details" {
  _mock_curl_queue "$(cat "$FIXTURES/worklog.json")"
  run cmd_get 98765
  [ "$status" -eq 0 ]
  [[ "$output" =~ "98765" ]]
  [[ "$output" =~ "2026-04-09" ]]
  [[ "$output" =~ "2h" ]]
  [[ "$output" =~ "Worked on feature X" ]]
}

@test "cmd_get: fails without worklog ID" {
  run cmd_get
  [ "$status" -eq 1 ]
  [[ "$output" =~ "worklog ID required" ]]
}

@test "cmd_get: fails with non-numeric ID" {
  run cmd_get "abc"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "must be a number" ]]
}

@test "cmd_get: exits non-zero on API error" {
  _mock_curl_queue '{"message":"Worklog not found"}' 404
  run cmd_get 99999
  [ "$status" -eq 1 ]
}

# ── cmd_list ──────────────────────────────────────────────────────────────────

@test "cmd_list --today: shows worklogs table" {
  _mock_curl_queue "$(cat "$FIXTURES/myself.json")"
  _mock_curl_queue "$(cat "$FIXTURES/worklogs_list.json")"
  run cmd_list --today
  [ "$status" -eq 0 ]
  [[ "$output" =~ "98765" ]]
  [[ "$output" =~ "Martin Slovik" ]]
  [[ "$output" =~ "2h" ]]
}

@test "cmd_list --week: fetches worklogs for current week" {
  _mock_curl_queue "$(cat "$FIXTURES/myself.json")"
  _mock_curl_queue "$(cat "$FIXTURES/worklogs_list.json")"
  run cmd_list --week
  [ "$status" -eq 0 ]
  [[ "$output" =~ "98765" ]]
}

@test "cmd_list --from/--to: accepts explicit date range" {
  _mock_curl_queue "$(cat "$FIXTURES/myself.json")"
  _mock_curl_queue "$(cat "$FIXTURES/worklogs_list.json")"
  run cmd_list --from 2026-04-01 --to 2026-04-09
  [ "$status" -eq 0 ]
  [[ "$output" =~ "98765" ]]
}

@test "cmd_list: shows multiple worklogs" {
  _mock_curl_queue "$(cat "$FIXTURES/myself.json")"
  _mock_curl_queue "$(cat "$FIXTURES/worklogs_list.json")"
  run cmd_list --today
  [ "$status" -eq 0 ]
  [[ "$output" =~ "98765" ]]
  [[ "$output" =~ "98766" ]]
}

@test "cmd_list: fails without date args" {
  run cmd_list
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Provide --from and --to" ]]
}

@test "cmd_list: shows 'No worklogs found' for empty results" {
  _mock_curl_queue "$(cat "$FIXTURES/myself.json")"
  _mock_curl_queue '{"results":[]}'
  run cmd_list --today
  [ "$status" -eq 0 ]
  [[ "$output" =~ "No worklogs found" ]]
}

# ── cmd_log ───────────────────────────────────────────────────────────────────

@test "cmd_log: logs time and prints confirmation" {
  _mock_curl_queue "$(cat "$FIXTURES/myself.json")"
  _mock_curl_queue "$(cat "$FIXTURES/issue.json")"
  _mock_curl_queue "$(cat "$FIXTURES/created_worklog.json")"
  run cmd_log -i PROJ-123 -t 2h -c "Implemented feature X"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Logged 2h" ]]
  [[ "$output" =~ "PROJ-123" ]]
  [[ "$output" =~ "99000" ]]
}

@test "cmd_log: accepts numeric issue ID (skips Jira resolve call)" {
  _mock_curl_queue "$(cat "$FIXTURES/myself.json")"
  _mock_curl_queue "$(cat "$FIXTURES/created_worklog.json")"
  run cmd_log -i 10042 -t 1h
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Logged 1h" ]]
}

@test "cmd_log: fails without --issue" {
  run cmd_log -t 2h
  [ "$status" -eq 1 ]
  [[ "$output" =~ "--issue is required" ]]
}

@test "cmd_log: fails without --time" {
  run cmd_log -i PROJ-123
  [ "$status" -eq 1 ]
  [[ "$output" =~ "--time is required" ]]
}

@test "cmd_log: fails with invalid duration" {
  run cmd_log -i PROJ-123 -t "badtime"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Invalid duration" ]]
}

# ── cmd_update ────────────────────────────────────────────────────────────────

@test "cmd_update: updates worklog and prints confirmation" {
  _mock_curl_queue "$(cat "$FIXTURES/worklog.json")"
  _mock_curl_queue "$(cat "$FIXTURES/worklog.json")"
  run cmd_update 98765 -t 3h
  [ "$status" -eq 0 ]
  [[ "$output" =~ "98765 updated" ]]
}

@test "cmd_update: preserves existing description when not specified" {
  _mock_curl_queue "$(cat "$FIXTURES/worklog.json")"
  _mock_curl_queue "$(cat "$FIXTURES/worklog.json")"
  run cmd_update 98765 -t 3h
  [ "$status" -eq 0 ]
}

@test "cmd_update: fails without worklog ID" {
  run cmd_update
  [ "$status" -eq 1 ]
  [[ "$output" =~ "worklog ID required" ]]
}

@test "cmd_update: fails with non-numeric ID" {
  run cmd_update "abc" -t 1h
  [ "$status" -eq 1 ]
  [[ "$output" =~ "must be a number" ]]
}

# ── cmd_delete ────────────────────────────────────────────────────────────────

@test "cmd_delete: deletes worklog" {
  _mock_curl_queue "" 204
  run cmd_delete 98765
  [ "$status" -eq 0 ]
  [[ "$output" =~ "98765 deleted" ]]
}

@test "cmd_delete: fails without worklog ID" {
  run cmd_delete
  [ "$status" -eq 1 ]
  [[ "$output" =~ "worklog ID required" ]]
}

@test "cmd_delete: fails with non-numeric ID" {
  run cmd_delete "abc"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "must be a number" ]]
}

