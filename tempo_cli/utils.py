import re
from datetime import datetime, timedelta

from tabulate import tabulate


def parse_duration(s):
    """Parse a duration string like '2h30m', '1d', '45m', '1h' into seconds."""
    s = s.strip().lower()
    pattern = re.compile(r"(?:(\d+)d)?(?:(\d+)h)?(?:(\d+)m)?$")
    match = pattern.match(s)
    if not match or not any(match.groups()):
        raise ValueError(
            f"Invalid duration: '{s}'. Use format like '1d', '2h', '2h30m', '45m'"
        )
    days = int(match.group(1) or 0)
    hours = int(match.group(2) or 0)
    minutes = int(match.group(3) or 0)
    total_seconds = (days * 8 * 3600) + (hours * 3600) + (minutes * 60)
    if total_seconds == 0:
        raise ValueError("Duration must be greater than zero")
    return total_seconds


def format_duration(seconds):
    """Convert seconds into a human-readable duration string."""
    if seconds is None or seconds == 0:
        return "0m"
    hours = seconds // 3600
    minutes = (seconds % 3600) // 60
    parts = []
    if hours:
        parts.append(f"{hours}h")
    if minutes:
        parts.append(f"{minutes}m")
    return "".join(parts) if parts else "0m"


def get_today():
    return datetime.now().strftime("%Y-%m-%d")


def get_week_range():
    today = datetime.now()
    start = today - timedelta(days=today.weekday())  # Monday
    end = start + timedelta(days=6)  # Sunday
    return start.strftime("%Y-%m-%d"), end.strftime("%Y-%m-%d")


def format_worklogs_table(worklogs):
    """Format a list of worklog dicts into a table string."""
    if not worklogs:
        return "No worklogs found."

    rows = []
    for wl in worklogs:
        issue = wl.get("issue", {}) or {}
        issue_id = issue.get("id", "N/A")
        author = wl.get("author", {}) or {}
        author_name = author.get("displayName", "N/A")
        rows.append([
            wl.get("tempoWorklogId", ""),
            issue_id,
            author_name,
            wl.get("startDate", ""),
            format_duration(wl.get("timeSpentSeconds", 0)),
            (wl.get("description") or "")[:50],
        ])

    return tabulate(
        rows,
        headers=["ID", "Issue", "Author", "Date", "Time", "Description"],
        tablefmt="simple",
    )


def format_worklog_detail(wl):
    """Format a single worklog dict into a detailed view."""
    issue = wl.get("issue", {}) or {}
    author = wl.get("author", {}) or {}
    lines = [
        f"Worklog ID:   {wl.get('tempoWorklogId', 'N/A')}",
        f"Issue ID:     {issue.get('id', 'N/A')}",
        f"Author:       {author.get('displayName', 'N/A')} ({author.get('accountId', '')})",
        f"Date:         {wl.get('startDate', 'N/A')}",
        f"Start Time:   {wl.get('startTime', 'N/A')}",
        f"Time Spent:   {format_duration(wl.get('timeSpentSeconds', 0))}",
        f"Billable:     {format_duration(wl.get('billableSeconds', 0))}",
        f"Description:  {wl.get('description') or '(none)'}",
        f"Created:      {wl.get('createdAt', 'N/A')}",
        f"Updated:      {wl.get('updatedAt', 'N/A')}",
    ]
    return "\n".join(lines)
