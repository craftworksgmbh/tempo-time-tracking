---
name: tempo-time-tracking
description: Manages Tempo Timesheets worklogs via the tempo CLI. Use when the user wants to log time, track hours, list or review worklogs, update or delete time entries, or manage Tempo time tracking for Jira issues. Requires TEMPO_API_TOKEN, JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN environment variables to be set.
compatibility: claude code, opencode
---

# Tempo Time Tracking

Manages Tempo Timesheets worklogs via the `tempo` CLI. Install with `pip install -e .` from the repo root.

## Guardrails — read before running any command

**STOP and ask the user if any of the following are unknown:**

- Jira issue key (e.g., `PROJ-123`) — NEVER guess or invent one
- Worklog ID for `get`, `update`, or `delete` — run `tempo list` first if not provided
- Duration — ask the user if not stated; confirm the format matches `1h`, `2h30m`, `45m`, `1d`
- Date — default to today only if the user has not specified one; use `YYYY-MM-DD` format exactly

**STOP and run `tempo config` first** if you are unsure whether the environment is configured. If it reports missing variables, tell the user which ones to set before proceeding.

**Destructive operations (`delete`, `update`):**
- Before running `delete`, state the worklog ID and ask the user to confirm
- Before running `update`, show the proposed change and ask the user to confirm

**On command failure:**
- Show the exact error output to the user
- Do not retry with guessed values — ask the user how to proceed

## Prerequisites

Required environment variables:
- `TEMPO_API_TOKEN` – Tempo Cloud API token
- `JIRA_URL` – Jira instance URL (e.g., `https://yoursite.atlassian.net`)
- `JIRA_EMAIL` – Jira account email
- `JIRA_API_TOKEN` – Atlassian API token

## Commands

### Log time
```bash
  tempo log --issue <ISSUE_KEY> --time <DURATION> [--date YYYY-MM-DD] [--comment "description"]
```
Duration format: `1h`, `2h30m`, `45m`, `1d` — no other formats are accepted.

### List worklogs
```bash
  tempo list [--today | --week | --from YYYY-MM-DD --to YYYY-MM-DD]
```
Defaults to current user's worklogs (`--mine` is implicit). Use this to find worklog IDs.

### Get worklog details
```bash
  tempo get <WORKLOG_ID>
```

### Update worklog
```bash
  tempo update <WORKLOG_ID> [--time DURATION] [--date YYYY-MM-DD] [--comment "text"]
```
Unspecified fields are preserved from the existing worklog.

### Delete worklog
```bash
  tempo delete <WORKLOG_ID> [--yes]
```
Omit `--yes` to get a confirmation prompt. Prefer omitting it.

## Examples

```bash
# Log 2 hours to PROJ-123
  tempo log -i PROJ-123 -t 2h -c "Implemented feature X"

# Show this week's worklogs (use this to find worklog IDs)
  tempo list --week

# Update time and comment on worklog 98765
  tempo update 98765 -t 3h -c "Added tests"

# Delete — prefer interactive confirmation
  tempo delete 98765
```
