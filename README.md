# Tempo Timesheets CLI

A command-line interface to track time and manage your Tempo Timesheets directly from your terminal. 

## Installation

**Requirements:** Python 3.9+, [pipx](https://pipx.pypa.io)

```bash
    # 1. Install pipx (if not already installed)
    brew install pipx
    pipx ensurepath
    # Restart your terminal after this step

    # 2. Install tempo globally
    pipx install .
```

`tempo` will be available on your PATH in any directory and shell session.

> For development (live code changes): `pipx install -e .`
> To update after code changes: `pipx reinstall tempo-cli`

### Environment variables

Set these before using the CLI:

```bash
    export TEMPO_API_TOKEN=your-tempo-api-token
    export JIRA_URL=https://yoursite.atlassian.net
    export JIRA_EMAIL=your-email@example.com
    export JIRA_API_TOKEN=your-atlassian-api-token
```

Run `tempo config` to verify your configuration.

---

## Commands Overview

The CLI provides the following commands to manage your worklogs:

* `log`: Log time to a Jira issue.
* `list`: Search and list worklogs.
* `get`: Get details of a specific worklog.
* `update`: Update an existing worklog.
* `delete`: Delete a worklog.
* `config`: Show current configuration.

*(Note: The examples below assume your CLI entry point is configured as `tempo-cli`.)*

---

## Command Reference

### `log`
Log time to a Jira issue. 

**Usage:**
```bash
  tempo-cli log --issue <ISSUE_KEY> --time <DURATION> [OPTIONS]
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
  tempo-cli log -i PROJ-123 -t 2h -c "Implemented user authentication"
```

---

### `list`
Search and list worklogs. You must provide a date range or use one of the built-in shortcuts.

**Usage:**
```bash
  tempo-cli list [OPTIONS]
```

**Options:**

| Option | Shortcut | Description |
| :--- | :---: | :--- |
| `--from` | `-f` | Start date (`YYYY-MM-DD`). |
| `--to` | `-t` | End date (`YYYY-MM-DD`). |
| `--today` | - | **Shortcut:** Show today's worklogs. |
| `--week` | - | **Shortcut:** Show the current week's worklogs. |

**Example:**
```bash
  tempo-cli list --week --mine
```

---

### `get`
Fetch and display the full details of a specific worklog.

**Usage:**
```bash
  tempo-cli get <WORKLOG_ID>
```

**Arguments:**
* `worklog_id` (integer): The unique ID of the worklog.

---

### `update`
Update an existing worklog. 

> **Note:** Tempo's API replaces the entire worklog on update. This CLI automatically fetches the existing worklog first so that any fields you do not explicitly specify remain unchanged.

**Usage:**
```bash
  tempo-cli update <WORKLOG_ID> [OPTIONS]
```

**Options:**

| Option | Shortcut | Description |
| :--- | :---: | :--- |
| `--time` | `-t` | New duration (e.g., `2h30m`). |
| `--date` | `-d` | New start date (`YYYY-MM-DD`). |
| `--comment` | `-c` | New description of the work. |

**Example:**
```bash
  tempo-cli update 98765 -t 3h -c "Updated time and description"
```

---

### `delete`
Delete a specific worklog. By default, you will be prompted to confirm the deletion.

**Usage:**
```bash
  tempo-cli delete <WORKLOG_ID> [OPTIONS]
```

**Options:**

| Option | Shortcut | Description |
| :--- | :---: | :--- |
| `--yes` | `-y` | Skip the confirmation prompt and delete immediately. |

**Example:**
```bash
  tempo-cli delete 98765 --yes
```

---

### `config`
Display your current CLI configuration settings (e.g., Jira host, API tokens).

**Usage:**
```bash
  tempo-cli config
```

---

## Agent Skill

This repo ships with an Agent Skill for [Claude Code](https://code.claude.com) and [OpenCode](https://opencode.ai) located at `./skills/tempo-time-tracking/SKILL.md`.

When working inside this project directory, Claude Code and OpenCode discover the skill automatically. To make it available globally (across all projects), install it once:

```bash
  # Claude Code (global)
  cp -r ./skills/tempo-time-tracking ~/.claude/skills/

  # OpenCode (global)
  cp -r ./skills/tempo-time-tracking ~/.config/opencode/skills/
```

Once installed, you can say things like _"log 2 hours to PROJ-123"_ or _"show this week's worklogs"_ and the AI will invoke the correct `tempo` commands.