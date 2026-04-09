#!/usr/bin/env bash
# tempo — Tempo Timesheets CLI
# Requirements: curl, jq | macOS and Linux only

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
#  GLOBALS
# ──────────────────────────────────────────────────────────────────────────────
_DATE_IMPL=gnu   # set by _detect_platform
_ACCOUNT_ID=""   # cached by _get_account_id

# ──────────────────────────────────────────────────────────────────────────────
#  DEPENDENCY CHECK
# ──────────────────────────────────────────────────────────────────────────────
_check_deps() {
  local missing=()
  for cmd in curl jq; do
    command -v "$cmd" > /dev/null 2>&1 || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: required tools not found: ${missing[*]}" >&2
    echo "  brew install jq   # macOS" >&2
    echo "  apt install jq    # Debian/Ubuntu" >&2
    exit 1
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
#  PLATFORM DETECTION
# ──────────────────────────────────────────────────────────────────────────────
_detect_platform() {
  if date -v1d > /dev/null 2>&1; then
    _DATE_IMPL=bsd
  else
    _DATE_IMPL=gnu
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
#  CONFIG
# ──────────────────────────────────────────────────────────────────────────────
_mask() {
  local v="$1"
  if [[ ${#v} -le 4 ]]; then echo "****"; return; fi
  local stars; stars=$(printf '%*s' "$(( ${#v} - 4 ))" '' | tr ' ' '*')
  echo "${v:0:4}${stars}"
}

_load_config() {
  TEMPO_API_TOKEN="${TEMPO_API_TOKEN:-}"
  JIRA_URL="${JIRA_URL:-}"
  JIRA_EMAIL="${JIRA_EMAIL:-}"
  JIRA_API_TOKEN="${JIRA_API_TOKEN:-}"

  JIRA_URL="${JIRA_URL%/}"
  TEMPO_BASE_URL="https://api.tempo.io/4"

  local missing=()
  [[ -z "$TEMPO_API_TOKEN" ]] && missing+=("TEMPO_API_TOKEN")
  [[ -z "$JIRA_URL"        ]] && missing+=("JIRA_URL")
  [[ -z "$JIRA_EMAIL"      ]] && missing+=("JIRA_EMAIL")
  [[ -z "$JIRA_API_TOKEN"  ]] && missing+=("JIRA_API_TOKEN")

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: Missing environment variables: ${missing[*]}" >&2
    echo "" >&2
    echo "Set them with:" >&2
    echo "  export TEMPO_API_TOKEN=your-tempo-api-token" >&2
    echo "  export JIRA_URL=https://yoursite.atlassian.net" >&2
    echo "  export JIRA_EMAIL=your-email@example.com" >&2
    echo "  export JIRA_API_TOKEN=your-atlassian-api-token" >&2
    echo "" >&2
    echo "Tempo token: Jira > Tempo > Settings > API Integration" >&2
    echo "Jira token:  https://id.atlassian.com/manage-profile/security/api-tokens" >&2
    echo "" >&2
    echo "Or run: tempo init" >&2
    exit 1
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
#  HTTP HELPERS
# ──────────────────────────────────────────────────────────────────────────────
_check_http() {
  local code="$1" body="$2"
  [[ "$code" -eq 204 ]] && return 0  # No Content (DELETE success)
  if [[ "$code" -ge 400 ]]; then
    local msg; msg=$(jq -r '.message // .errors // "Unknown error"' <<< "$body" 2>/dev/null || echo "$body")
    echo "API Error $code: $msg" >&2
    exit 1
  fi
}

_jira_get() {
  local path="$1"
  local url="${JIRA_URL}/rest/api/3${path}"
  local tmpfile; tmpfile=$(mktemp)
  local code
  code=$(curl -s \
    -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
    -H "Accept: application/json" \
    -o "$tmpfile" -w "%{http_code}" "$url")
  local body; body=$(cat "$tmpfile"); rm -f "$tmpfile"
  _check_http "$code" "$body"
  echo "$body"
}

_tempo_request() {
  local method="$1" path="$2" payload="${3:-}"
  local url="${TEMPO_BASE_URL}${path}"
  local tmpfile; tmpfile=$(mktemp)
  local curl_args=(-s -X "$method"
    -H "Authorization: Bearer ${TEMPO_API_TOKEN}"
    -H "Accept: application/json"
    -H "Content-Type: application/json"
    -o "$tmpfile" -w "%{http_code}")
  [[ -n "$payload" ]] && curl_args+=(-d "$payload")
  local code
  code=$(curl "${curl_args[@]}" "$url")
  local body; body=$(cat "$tmpfile"); rm -f "$tmpfile"
  _check_http "$code" "$body"
  echo "$body"
}

# ──────────────────────────────────────────────────────────────────────────────
#  UTILITIES
# ──────────────────────────────────────────────────────────────────────────────
_parse_duration() {
  local s="${1,,}"  # lowercase
  if [[ "$s" =~ ^([0-9]+d)?([0-9]+h)?([0-9]+m)?$ ]] && \
     [[ -n "${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}" ]]; then
    local days=0 hours=0 mins=0
    [[ -n "${BASH_REMATCH[1]}" ]] && days="${BASH_REMATCH[1]%d}"
    [[ -n "${BASH_REMATCH[2]}" ]] && hours="${BASH_REMATCH[2]%h}"
    [[ -n "${BASH_REMATCH[3]}" ]] && mins="${BASH_REMATCH[3]%m}"
    local total=$(( days * 8 * 3600 + hours * 3600 + mins * 60 ))
    if [[ "$total" -eq 0 ]]; then
      echo "Error: Duration must be greater than zero" >&2; exit 1
    fi
    echo "$total"
  else
    echo "Error: Invalid duration '${1}'. Use format like '1d', '2h', '2h30m', '45m'" >&2
    exit 1
  fi
}

_format_duration() {
  local secs="${1:-0}"
  if [[ "$secs" -eq 0 ]]; then echo "0m"; return; fi
  local h=$(( secs / 3600 ))
  local m=$(( (secs % 3600) / 60 ))
  local out=""
  (( h > 0 )) && out+="${h}h"
  (( m > 0 )) && out+="${m}m"
  echo "${out:-0m}"
}

_get_today() {
  date +%Y-%m-%d
}

_get_week_range() {
  local dow; dow=$(date +%u)  # 1=Mon, 7=Sun
  local monday sunday
  if [[ "$_DATE_IMPL" == "bsd" ]]; then
    monday=$(date -v-$(( dow - 1 ))d +%Y-%m-%d)
    sunday=$(date -v+$(( 7 - dow ))d +%Y-%m-%d)
  else
    monday=$(date -d "-$(( dow - 1 )) days" +%Y-%m-%d)
    sunday=$(date -d "+$(( 7 - dow )) days" +%Y-%m-%d)
  fi
  echo "$monday"
  echo "$sunday"
}

_get_account_id() {
  if [[ -z "$_ACCOUNT_ID" ]]; then
    _ACCOUNT_ID=$(_jira_get "/myself" | jq -r '.accountId')
  fi
  echo "$_ACCOUNT_ID"
}

_resolve_issue() {
  local issue="$1"
  if [[ "$issue" =~ ^[0-9]+$ ]]; then
    echo "$issue"
  else
    _jira_get "/issue/${issue}?fields=id" | jq -r '.id'
  fi
}

_format_worklogs_table() {
  local json="$1"
  local count; count=$(jq '. | length' <<< "$json")
  if [[ "$count" -eq 0 ]]; then
    echo "No worklogs found."
    return
  fi

  printf "%-10s %-12s %-20s %-12s %-8s %s\n" "ID" "Issue" "Author" "Date" "Time" "Description"
  printf "%-10s %-12s %-20s %-12s %-8s %s\n" \
    "----------" "------------" "--------------------" "------------" "--------" "-----------"

  while IFS=$'\t' read -r id issue_id author date secs desc; do
    local duration; duration=$(_format_duration "$secs")
    printf "%-10s %-12s %-20s %-12s %-8s %s\n" \
      "$id" "$issue_id" "${author:0:20}" "$date" "$duration" "${desc:0:50}"
  done < <(jq -r '.[] | [
    (.tempoWorklogId // ""),
    ((.issue // {}).id // "N/A"),
    ((.author // {}).displayName // "N/A"),
    (.startDate // ""),
    (.timeSpentSeconds // 0),
    (.description // "")
  ] | @tsv' <<< "$json")
}

_format_worklog_detail() {
  local json="$1"
  local id issue_id author_name author_id date start_time secs billable_secs desc created updated
  id=$(jq -r '.tempoWorklogId // "N/A"' <<< "$json")
  issue_id=$(jq -r '(.issue // {}).id // "N/A"' <<< "$json")
  author_name=$(jq -r '(.author // {}).displayName // "N/A"' <<< "$json")
  author_id=$(jq -r '(.author // {}).accountId // ""' <<< "$json")
  date=$(jq -r '.startDate // "N/A"' <<< "$json")
  start_time=$(jq -r '.startTime // "N/A"' <<< "$json")
  secs=$(jq -r '.timeSpentSeconds // 0' <<< "$json")
  billable_secs=$(jq -r '.billableSeconds // 0' <<< "$json")
  desc=$(jq -r '.description // "(none)"' <<< "$json")
  created=$(jq -r '.createdAt // "N/A"' <<< "$json")
  updated=$(jq -r '.updatedAt // "N/A"' <<< "$json")

  printf "Worklog ID:   %s\n" "$id"
  printf "Issue ID:     %s\n" "$issue_id"
  printf "Author:       %s (%s)\n" "$author_name" "$author_id"
  printf "Date:         %s\n" "$date"
  printf "Start Time:   %s\n" "$start_time"
  printf "Time Spent:   %s\n" "$(_format_duration "$secs")"
  printf "Billable:     %s\n" "$(_format_duration "$billable_secs")"
  printf "Description:  %s\n" "$desc"
  printf "Created:      %s\n" "$created"
  printf "Updated:      %s\n" "$updated"
}

# ──────────────────────────────────────────────────────────────────────────────
#  COMMANDS
# ──────────────────────────────────────────────────────────────────────────────

cmd_init() {
  local shell_name; shell_name=$(basename "${SHELL:-bash}")
  local rc_file
  case "$shell_name" in
    zsh)  rc_file="$HOME/.zshrc" ;;
    bash)
      if [[ "$(uname)" == "Darwin" ]]; then
        rc_file="$HOME/.bash_profile"
      else
        rc_file="$HOME/.bashrc"
      fi
      ;;
    *)
      rc_file="$HOME/.profile"
      echo "Note: Shell '$shell_name' not fully supported. Writing to $rc_file." >&2
      ;;
  esac

  echo "Tempo CLI — First-time Setup"
  echo "=============================="
  echo "Credentials will be saved to: $rc_file"
  echo ""
  echo "Where to get tokens:"
  echo "  Tempo token: Jira > Tempo > Settings > API Integration"
  echo "  Jira token:  https://id.atlassian.com/manage-profile/security/api-tokens"
  echo ""

  local tempo_token jira_url jira_email jira_token

  read -r -s -p "TEMPO_API_TOKEN: " tempo_token; echo
  [[ -z "$tempo_token" ]] && { echo "Error: TEMPO_API_TOKEN cannot be empty" >&2; exit 1; }

  read -r -p "JIRA_URL (e.g. https://yourcompany.atlassian.net): " jira_url
  [[ -z "$jira_url" ]] && { echo "Error: JIRA_URL cannot be empty" >&2; exit 1; }

  read -r -p "JIRA_EMAIL: " jira_email
  [[ -z "$jira_email" ]] && { echo "Error: JIRA_EMAIL cannot be empty" >&2; exit 1; }

  read -r -s -p "JIRA_API_TOKEN: " jira_token; echo
  [[ -z "$jira_token" ]] && { echo "Error: JIRA_API_TOKEN cannot be empty" >&2; exit 1; }

  echo ""
  echo "Writing configuration to $rc_file ..."

  local marker_start="# >>> tempo-cli configuration >>>"
  local marker_end="# <<< tempo-cli configuration <<<"

  # Remove existing block if present
  if grep -qF "$marker_start" "$rc_file" 2>/dev/null; then
    local tmp; tmp=$(mktemp)
    sed -e "/$marker_start/,/$marker_end/d" "$rc_file" > "$tmp"
    mv "$tmp" "$rc_file"
  fi

  # Append new block (variables are intentionally expanded here)
  cat >> "$rc_file" << ENVBLOCK

$marker_start
export TEMPO_API_TOKEN="$tempo_token"
export JIRA_URL="$jira_url"
export JIRA_EMAIL="$jira_email"
export JIRA_API_TOKEN="$jira_token"
$marker_end
ENVBLOCK

  echo "Done!"
  echo ""
  echo "Reload your shell:"
  echo "  source $rc_file"
  echo ""
  echo "Then verify with: tempo config"
}

cmd_log() {
  _load_config
  local issue="" duration="" start_date="" description=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --issue|-i)   issue="$2";       shift 2 ;;
      --time|-t)    duration="$2";    shift 2 ;;
      --date|-d)    start_date="$2";  shift 2 ;;
      --comment|-c) description="$2"; shift 2 ;;
      *) echo "Error: Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  [[ -z "$issue"    ]] && { echo "Error: --issue is required" >&2; exit 1; }
  [[ -z "$duration" ]] && { echo "Error: --time is required" >&2; exit 1; }

  local seconds; seconds=$(_parse_duration "$duration")
  start_date="${start_date:-$(_get_today)}"
  local account_id; account_id=$(_get_account_id)
  local issue_id; issue_id=$(_resolve_issue "$issue")

  local payload
  payload=$(jq -n \
    --arg  authorId          "$account_id" \
    --arg  issueId           "$issue_id" \
    --arg  startDate         "$start_date" \
    --argjson timeSpentSeconds "$seconds" \
    --arg  description       "$description" \
    'if $description != ""
     then {authorAccountId:$authorId, issueId:($issueId|tonumber), startDate:$startDate,
           timeSpentSeconds:$timeSpentSeconds, description:$description}
     else {authorAccountId:$authorId, issueId:($issueId|tonumber), startDate:$startDate,
           timeSpentSeconds:$timeSpentSeconds}
     end')

  local result; result=$(_tempo_request POST /worklogs "$payload")
  local wl_id; wl_id=$(jq -r '.tempoWorklogId // "?"' <<< "$result")
  echo "Logged $(_format_duration "$seconds") to $issue on $start_date (worklog ID: $wl_id)"
}

cmd_list() {
  _load_config
  local from_date="" to_date="" shortcut=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from|-f) from_date="$2"; shift 2 ;;
      --to|-t)   to_date="$2";   shift 2 ;;
      --today)   shortcut="today"; shift ;;
      --week)    shortcut="week";  shift ;;
      *) echo "Error: Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  case "$shortcut" in
    today)
      from_date=$(_get_today)
      to_date="$from_date"
      ;;
    week)
      local week_range; week_range=$(_get_week_range)
      from_date=$(echo "$week_range" | head -1)
      to_date=$(echo "$week_range" | tail -1)
      ;;
  esac

  if [[ -z "$from_date" || -z "$to_date" ]]; then
    echo "Error: Provide --from and --to dates, or use --today / --week" >&2
    exit 1
  fi

  local account_id; account_id=$(_get_account_id)
  local response; response=$(_tempo_request GET "/worklogs/user/${account_id}?from=${from_date}&to=${to_date}")
  local worklogs; worklogs=$(jq '.results // []' <<< "$response")
  _format_worklogs_table "$worklogs"
}

cmd_get() {
  _load_config
  local worklog_id="${1:-}"
  [[ -z "$worklog_id" ]]            && { echo "Error: worklog ID required" >&2;           exit 1; }
  [[ ! "$worklog_id" =~ ^[0-9]+$ ]] && { echo "Error: worklog ID must be a number" >&2;  exit 1; }

  local result; result=$(_tempo_request GET "/worklogs/${worklog_id}")
  _format_worklog_detail "$result"
}

cmd_update() {
  _load_config
  local worklog_id="${1:-}"
  [[ -z "$worklog_id" ]]            && { echo "Error: worklog ID required" >&2;           exit 1; }
  [[ ! "$worklog_id" =~ ^[0-9]+$ ]] && { echo "Error: worklog ID must be a number" >&2;  exit 1; }
  shift

  local duration="" start_date="" description="" _desc_set=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --time|-t)    duration="$2";    shift 2 ;;
      --date|-d)    start_date="$2";  shift 2 ;;
      --comment|-c) description="$2"; _desc_set=true; shift 2 ;;
      *) echo "Error: Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  # Fetch existing worklog to preserve unmodified fields
  local existing; existing=$(_tempo_request GET "/worklogs/${worklog_id}")
  local cur_secs;   cur_secs=$(jq -r   '.timeSpentSeconds // 0' <<< "$existing")
  local cur_date;   cur_date=$(jq -r   '.startDate // ""'       <<< "$existing")
  local cur_desc;   cur_desc=$(jq -r   '.description // ""'     <<< "$existing")
  local cur_author; cur_author=$(jq -r '(.author // {}).accountId // ""' <<< "$existing")

  local seconds
  if [[ -n "$duration" ]]; then
    seconds=$(_parse_duration "$duration")
  else
    seconds="$cur_secs"
  fi
  start_date="${start_date:-$cur_date}"
  if [[ "$_desc_set" == "false" ]]; then
    description="$cur_desc"
  fi
  local account_id="$cur_author"
  [[ -z "$account_id" ]] && account_id=$(_get_account_id)

  local payload
  payload=$(jq -n \
    --arg  authorId            "$account_id" \
    --arg  startDate           "$start_date" \
    --argjson timeSpentSeconds "$seconds" \
    --arg  description         "$description" \
    'if $description != ""
     then {authorAccountId:$authorId, startDate:$startDate,
           timeSpentSeconds:$timeSpentSeconds, description:$description}
     else {authorAccountId:$authorId, startDate:$startDate,
           timeSpentSeconds:$timeSpentSeconds}
     end')

  _tempo_request PUT "/worklogs/${worklog_id}" "$payload" > /dev/null
  echo "Worklog ${worklog_id} updated."
}

cmd_delete() {
  _load_config
  local worklog_id="${1:-}"
  [[ -z "$worklog_id" ]]            && { echo "Error: worklog ID required" >&2;           exit 1; }
  [[ ! "$worklog_id" =~ ^[0-9]+$ ]] && { echo "Error: worklog ID must be a number" >&2;  exit 1; }
  shift

  local yes=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes|-y) yes=true; shift ;;
      *) echo "Error: Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [[ "$yes" == "false" ]]; then
    local confirm=""
    read -r -p "Delete worklog ${worklog_id}? [y/N] " confirm || true
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
      echo "Aborted."
      exit 0
    fi
  fi

  _tempo_request DELETE "/worklogs/${worklog_id}" > /dev/null
  echo "Worklog ${worklog_id} deleted."
}

cmd_config() {
  _load_config
  printf "Tempo Token:    %s\n" "$(_mask "$TEMPO_API_TOKEN")"
  printf "Jira URL:       %s\n" "$JIRA_URL"
  printf "Jira Email:     %s\n" "$JIRA_EMAIL"
  printf "Jira Token:     %s\n" "$(_mask "$JIRA_API_TOKEN")"
}

# ──────────────────────────────────────────────────────────────────────────────
#  USAGE
# ──────────────────────────────────────────────────────────────────────────────
_usage() {
  cat << 'USAGE'
Tempo Timesheets CLI — track time from your terminal

Usage: tempo <command> [options]

Commands:
  init                     Set up API credentials interactively
  log                      Log time to a Jira issue
  list                     Search and list worklogs
  get <worklog_id>         Get details of a specific worklog
  update <worklog_id>      Update an existing worklog
  delete <worklog_id>      Delete a worklog
  config                   Show current configuration

Options for log:
  -i, --issue <KEY|ID>     Jira issue key (e.g. PROJ-123) or numeric ID  [required]
  -t, --time  <DURATION>   Duration: 1h, 2h30m, 45m, 1d (1d = 8h)       [required]
  -d, --date  <YYYY-MM-DD> Date (default: today)
  -c, --comment <TEXT>     Work description

Options for list:
  -f, --from <YYYY-MM-DD>  Start date
  -t, --to   <YYYY-MM-DD>  End date
      --today              Show today's worklogs
      --week               Show this week's worklogs (Mon–Sun)

Options for update:
  -t, --time  <DURATION>   New duration
  -d, --date  <YYYY-MM-DD> New date
  -c, --comment <TEXT>     New description

Options for delete:
  -y, --yes                Skip confirmation prompt

Examples:
  tempo init
  tempo log -i PROJ-123 -t 2h -c "Implemented feature X"
  tempo list --week
  tempo list --from 2026-04-01 --to 2026-04-09
  tempo get 98765
  tempo update 98765 -t 3h -c "Added tests"
  tempo delete 98765
USAGE
}

# ──────────────────────────────────────────────────────────────────────────────
#  MAIN
# ──────────────────────────────────────────────────────────────────────────────
main() {
  _check_deps
  _detect_platform

  local cmd="${1:-}"
  if [[ -z "$cmd" ]]; then
    _usage
    exit 1
  fi
  shift

  case "$cmd" in
    init)         cmd_init   "$@" ;;
    log)          cmd_log    "$@" ;;
    list)         cmd_list   "$@" ;;
    get)          cmd_get    "$@" ;;
    update)       cmd_update "$@" ;;
    delete)       cmd_delete "$@" ;;
    config)       cmd_config "$@" ;;
    --help|-h|help) _usage  ;;
    *) echo "Unknown command: $cmd" >&2; echo "" >&2; _usage >&2; exit 1 ;;
  esac
}

main "$@"
