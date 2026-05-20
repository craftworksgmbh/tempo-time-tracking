#!/usr/bin/env bats
# Unit tests for pure utility functions — no network calls, no mocking needed.

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
# shellcheck source=../tempo.sh
source "$SCRIPT_DIR/../tempo.sh"

# ── _parse_duration ───────────────────────────────────────────────────────────

@test "_parse_duration: 1h returns 3600" {
  run _parse_duration "1h"
  [ "$status" -eq 0 ]
  [ "$output" -eq 3600 ]
}

@test "_parse_duration: 2h30m returns 9000" {
  run _parse_duration "2h30m"
  [ "$status" -eq 0 ]
  [ "$output" -eq 9000 ]
}

@test "_parse_duration: 45m returns 2700" {
  run _parse_duration "45m"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2700 ]
}

@test "_parse_duration: 1d returns 28800 (8h workday)" {
  run _parse_duration "1d"
  [ "$status" -eq 0 ]
  [ "$output" -eq 28800 ]
}

@test "_parse_duration: 1d2h30m returns 37800" {
  run _parse_duration "1d2h30m"
  [ "$status" -eq 0 ]
  [ "$output" -eq 37800 ]  # 28800 + 7200 + 1800
}

@test "_parse_duration: case insensitive (2H30M)" {
  run _parse_duration "2H30M"
  [ "$status" -eq 0 ]
  [ "$output" -eq 9000 ]
}

@test "_parse_duration: invalid string fails with message" {
  run _parse_duration "abc"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Invalid duration" ]]
}

@test "_parse_duration: zero duration fails" {
  run _parse_duration "0h"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "greater than zero" ]]
}

@test "_parse_duration: empty string fails" {
  run _parse_duration ""
  [ "$status" -eq 1 ]
}

@test "_parse_duration: number-only string fails" {
  run _parse_duration "123"
  [ "$status" -eq 1 ]
}

# ── _format_duration ──────────────────────────────────────────────────────────

@test "_format_duration: 0 returns 0m" {
  run _format_duration 0
  [ "$status" -eq 0 ]
  [ "$output" = "0m" ]
}

@test "_format_duration: 3600 returns 1h" {
  run _format_duration 3600
  [ "$status" -eq 0 ]
  [ "$output" = "1h" ]
}

@test "_format_duration: 9000 returns 2h30m" {
  run _format_duration 9000
  [ "$status" -eq 0 ]
  [ "$output" = "2h30m" ]
}

@test "_format_duration: 2700 returns 45m" {
  run _format_duration 2700
  [ "$status" -eq 0 ]
  [ "$output" = "45m" ]
}

@test "_format_duration: 28800 returns 8h" {
  run _format_duration 28800
  [ "$status" -eq 0 ]
  [ "$output" = "8h" ]
}

@test "_format_duration: roundtrip with _parse_duration" {
  local secs; secs=$(_parse_duration "2h30m")
  run _format_duration "$secs"
  [ "$output" = "2h30m" ]
}

# ── _mask ─────────────────────────────────────────────────────────────────────

@test "_mask: empty string returns ****" {
  run _mask ""
  [ "$status" -eq 0 ]
  [ "$output" = "****" ]
}

@test "_mask: short token (<=4 chars) returns ****" {
  run _mask "abc"
  [ "$status" -eq 0 ]
  [ "$output" = "****" ]
}

@test "_mask: exactly 4 chars returns ****" {
  run _mask "abcd"
  [ "$status" -eq 0 ]
  [ "$output" = "****" ]
}

@test "_mask: longer token shows first 4 chars + stars" {
  run _mask "abcdefgh"
  [ "$status" -eq 0 ]
  [ "$output" = "abcd****" ]
}

@test "_mask: star count matches hidden chars" {
  run _mask "abcdefghij"  # 10 chars → abcd + 6 stars
  [ "$status" -eq 0 ]
  [ "$output" = "abcd******" ]
}

# ── _get_today ────────────────────────────────────────────────────────────────

@test "_get_today: returns YYYY-MM-DD format" {
  run _get_today
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

# ── _get_week_range ───────────────────────────────────────────────────────────

@test "_get_week_range: returns exactly two lines" {
  _detect_platform
  run _get_week_range
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "_get_week_range: both lines are YYYY-MM-DD" {
  _detect_platform
  run _get_week_range
  [ "$status" -eq 0 ]
  local monday; monday=$(echo "$output" | head -1)
  local sunday; sunday=$(echo "$output" | tail -1)
  [[ "$monday" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
  [[ "$sunday" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

@test "_get_week_range: monday is before sunday" {
  _detect_platform
  run _get_week_range
  [ "$status" -eq 0 ]
  local monday; monday=$(echo "$output" | head -1)
  local sunday; sunday=$(echo "$output" | tail -1)
  [[ "$monday" < "$sunday" || "$monday" == "$sunday" ]]
}

# ── _load_config ──────────────────────────────────────────────────────────────

@test "_load_config: fails when all vars missing" {
  local tmp_home; tmp_home=$(mktemp -d)
  run env -i HOME="$tmp_home" PATH="$PATH" bash -c "
    source '$SCRIPT_DIR/../tempo.sh'
    _load_config
  "
  rm -rf "$tmp_home"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Missing environment variables" ]]
}

@test "_load_config: succeeds when all vars set" {
  run env TEMPO_API_TOKEN="tok" JIRA_URL="https://x.atlassian.net" \
      JIRA_EMAIL="a@b.com" JIRA_API_TOKEN="jtok" \
      HOME="$HOME" PATH="$PATH" bash -c "
        source '$SCRIPT_DIR/../tempo.sh'
        _load_config
      "
  [ "$status" -eq 0 ]
}

@test "_load_config: strips trailing slash from JIRA_URL" {
  export TEMPO_API_TOKEN="tok" JIRA_URL="https://x.atlassian.net/" \
         JIRA_EMAIL="a@b.com" JIRA_API_TOKEN="jtok"
  _load_config
  [ "$JIRA_URL" = "https://x.atlassian.net" ]
}

@test "_load_config: reports all missing vars" {
  local tmp_home; tmp_home=$(mktemp -d)
  run env -i HOME="$tmp_home" PATH="$PATH" bash -c "
    source '$SCRIPT_DIR/../tempo.sh'
    _load_config
  "
  rm -rf "$tmp_home"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "TEMPO_API_TOKEN" ]]
  [[ "$output" =~ "JIRA_URL" ]]
  [[ "$output" =~ "JIRA_EMAIL" ]]
  [[ "$output" =~ "JIRA_API_TOKEN" ]]
}
