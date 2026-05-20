# Tempo Timesheets CLI

A command-line interface to track time and manage your Tempo Timesheets directly from your terminal.

## Installation

**Requirements:** `curl` (pre-installed on macOS/Linux) and [`jq`](https://jqlang.github.io/jq/)

```bash
# 1. Install jq (if not already installed)
brew install jq          # macOS
# apt install jq         # Debian/Ubuntu

# 2. Install tempo
sudo make install             # copies to /usr/local/bin/tempo

# Or without make:
sudo cp tempo.sh /usr/local/bin/tempo && sudo chmod +x /usr/local/bin/tempo

# To install to a custom location (e.g. ~/.local/bin):
make install INSTALL_DIR=~/.local/bin
```

### First-time setup

Run the setup wizard to configure your API credentials:

```bash
tempo init
```

This will prompt for your tokens and save them to `~/.config/tempo/.env`. Credentials are loaded automatically on every `tempo` command — no shell restart needed.

Where to get the tokens:
- **Tempo token:** Jira → Tempo → Settings → API Integration
- **Jira token:** https://id.atlassian.com/manage-profile/security/api-tokens

Alternatively, you can edit `~/.config/tempo/.env` directly:

```bash
export TEMPO_API_TOKEN=your-tempo-api-token
export JIRA_URL=https://yoursite.atlassian.net
export JIRA_EMAIL=your-email@example.com
export JIRA_API_TOKEN=your-atlassian-api-token
```

> `TEMPO_API_URL` is hardcoded to `https://api.tempo.io` and does not need to be set.

Run `tempo config` to verify your configuration.

### Uninstall

```bash
sudo make uninstall
```

---

## Commands Overview

| Command | Description |
|---------|-------------|
| `init` | Set up API credentials interactively |
| `log` | Log time to a Jira issue |
| `list` | Search and list worklogs |
| `get` | Get details of a specific worklog |
| `update` | Update an existing worklog |
| `delete` | Delete a worklog |
| `config` | Show current configuration |

---

## Command Reference

### `init`
Interactive first-time setup wizard. Prompts for all required credentials and saves them to `~/.config/tempo/.env`.

```bash
tempo init
```

---

### `log`
Log time to a Jira issue.

**Usage:**
```bash
tempo log --issue <ISSUE_KEY> --time <DURATION> [OPTIONS]
```

**Options:**

| Option | Shortcut | Required | Default | Description |
| :--- | :---: | :---: | :--- | :--- |
| `--issue` | `-i` | **Yes** | - | Issue key (e.g., `PROJ-123`) or numeric ID. |
| `--time` | `-t` | **Yes** | - | Duration (e.g., `1h`, `2h30m`, `45m`, `1d`). |
| `--date` | `-d` | No | Today | Date in `YYYY-MM-DD` format. |
| `--comment`| `-c` | No | - | Description of the work done. |

**Example:**
```bash
tempo log -i PROJ-123 -t 2h -c "Implemented user authentication"
```

---

### `list`
Search and list worklogs. You must provide a date range or use one of the built-in shortcuts.

**Usage:**
```bash
tempo list [OPTIONS]
```

**Options:**

| Option | Shortcut | Description |
| :--- | :---: | :--- |
| `--from` | `-f` | Start date (`YYYY-MM-DD`). |
| `--to` | `-t` | End date (`YYYY-MM-DD`). |
| `--today` | - | **Shortcut:** Show today's worklogs. |
| `--week` | - | **Shortcut:** Show the current week's worklogs (Mon–Sun). |

**Example:**
```bash
tempo list --week
tempo list --from 2026-04-01 --to 2026-04-09
```

---

### `get`
Fetch and display the full details of a specific worklog.

**Usage:**
```bash
tempo get <WORKLOG_ID>
```

**Arguments:**
* `worklog_id` (integer): The unique ID of the worklog.

---

### `update`
Update an existing worklog.

> **Note:** Tempo's API replaces the entire worklog on update. This CLI automatically fetches the existing worklog first so that any fields you do not explicitly specify remain unchanged.

**Usage:**
```bash
tempo update <WORKLOG_ID> [OPTIONS]
```

**Options:**

| Option | Shortcut | Description |
| :--- | :---: | :--- |
| `--time` | `-t` | New duration (e.g., `2h30m`). |
| `--date` | `-d` | New start date (`YYYY-MM-DD`). |
| `--comment` | `-c` | New description of the work. |

**Example:**
```bash
tempo update 98765 -t 3h -c "Updated time and description"
```

---

### `delete`
Delete a specific worklog. By default, you will be prompted to confirm the deletion.

**Usage:**
```bash
tempo delete <WORKLOG_ID> [OPTIONS]
```

**Options:**

| Option | Shortcut | Description |
| :--- | :---: | :--- |
| `--yes` | `-y` | Skip the confirmation prompt and delete immediately. |

**Example:**
```bash
tempo delete 98765 --yes
```

---

### `config`
Display your current CLI configuration settings (e.g., Jira host, API tokens — tokens are masked).

**Usage:**
```bash
tempo config
```

---

## Development

### Running tests

**Requirement:** [bats-core](https://github.com/bats-core/bats-core)

```bash
brew install bats-core   # macOS
# apt install bats       # Debian/Ubuntu
```

Run all tests:

```bash
make test
```

Or run specific files directly:

```bash
bats tests/unit.bats        # pure utility functions (no network)
bats tests/commands.bats    # CLI commands with mocked curl
```

Filter by test name:

```bash
bats tests/unit.bats --filter "_parse_duration"
```

Tests use a file-based mock for `curl` — no real API calls are made.

---

## Agent Skill

This repo ships with an Agent Skill for [Claude Code](https://claude.ai/code) and [OpenCode](https://opencode.ai) located at `./skills/tempo-time-tracking/SKILL.md`.

When working inside this project directory, Claude Code and OpenCode discover the skill automatically. To make it available globally (across all projects), install it once:

```bash
# Claude Code (global)
cp -r ./skills/tempo-time-tracking ~/.claude/skills/

# OpenCode (global)
cp -r ./skills/tempo-time-tracking ~/.opencode/skills/
```

Once installed, you can say things like _"log 2 hours to PROJ-123"_ or _"show this week's worklogs"_ and the AI will invoke the correct `tempo` commands.
