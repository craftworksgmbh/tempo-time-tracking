---
name: tempo-time-tracking
description: Manages Tempo Timesheets worklogs via the tempo CLI. Use when the user wants to log time, track hours, list or review worklogs, update or delete time entries, or manage Tempo time tracking for Jira issues. Requires TEMPO_API_TOKEN, JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN environment variables to be set.
compatibility: claude code, opencode
---

# Tempo Time Tracking

Manages Tempo Timesheets worklogs via the `tempo` CLI.

## Workflow for delete and update

**NEVER run `tempo delete` or `tempo update` without explicit user approval in the conversation first.**

Before running either command:
1. Show the user exactly what will happen:
   - For `delete`: run `tempo get <WORKLOG_ID>`, show the details, then ask: *"Shall I delete this worklog?"*
   - For `update`: show the proposed changes (current value → new value), then ask: *"Shall I apply these changes?"*
2. Wait for the user to reply with a clear yes ("yes", "go ahead", "do it", etc.)
3. Only then run the command

**Do NOT use pipes, input redirection, or any shell trick to pre-answer prompts. Run the command directly after the user confirms.**

## Guardrails

**STOP and ask the user if any of the following are unknown:**
- Jira issue key (e.g., `PROJ-123`) — NEVER guess or invent one
- Worklog ID — run `tempo list` first if not provided
- Duration — ask if not stated; only `1h`, `2h30m`, `45m`, `1d` formats are accepted
- Date — default to today only if the user has not specified one

**STOP and run `tempo config` first** if you are unsure whether the environment is configured.

**On success:** respond with ✅ after every successfully completed operation.

**On command failure:** show the exact error output and ask the user how to proceed. Do not retry with guessed values.

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

### List worklogs
```bash
tempo list [--today | --week | --from YYYY-MM-DD --to YYYY-MM-DD]
```
Use this to find worklog IDs before running get, update, or delete.

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
tempo delete <WORKLOG_ID>
```

## Examples

```bash
# Log 2 hours to PROJ-123
tempo log -i PROJ-123 -t 2h -c "Implemented feature X"

# Show this week's worklogs (use this to find worklog IDs)
tempo list --week

# Update time and comment on worklog 98765
tempo update 98765 -t 3h -c "Added tests"

# Delete worklog 98765
tempo delete 98765
```
