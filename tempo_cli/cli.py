import click

from tempo_cli.config import load_config
from tempo_cli.client import TempoClient
from tempo_cli.utils import (
    format_duration,
    format_worklog_detail,
    format_worklogs_table,
    get_today,
    get_week_range,
    parse_duration,
)


@click.group()
def cli():
    """Tempo Timesheets CLI — track time from your terminal."""
    pass


@cli.command()
@click.option("--issue", "-i", required=True, help="Issue key (e.g., PROJ-123) or numeric ID")
@click.option("--time", "-t", "duration", required=True, help="Duration (e.g., 1h, 2h30m, 45m, 1d)")
@click.option("--date", "-d", "date", default=None, help="Date (YYYY-MM-DD), defaults to today")
@click.option("--comment", "-c", "description", default=None, help="Work description")
def log(issue, duration, date, description):
    """Log time to a Jira issue."""
    config = load_config()
    client = TempoClient(config)

    seconds = parse_duration(duration)
    start_date = date or get_today()

    result = client.create_worklog(
        issue=issue,
        time_spent_seconds=seconds,
        start_date=start_date,
        description=description,
    )

    wl_id = result.get("tempoWorklogId", "?")
    click.echo(f"Logged {format_duration(seconds)} to {issue} on {start_date} (worklog ID: {wl_id})")


@cli.command("list")
@click.option("--from", "-f", "from_date", default=None, help="Start date (YYYY-MM-DD)")
@click.option("--to", "-t", "to_date", default=None, help="End date (YYYY-MM-DD)")
@click.option("--today", "shortcut", flag_value="today", help="Show today's worklogs")
@click.option("--week", "shortcut", flag_value="week", help="Show current week's worklogs")
def list_worklogs(from_date, to_date, shortcut):
    """Search and list worklogs."""
    config = load_config()
    client = TempoClient(config)

    if shortcut == "today":
        from_date = to_date = get_today()
    elif shortcut == "week":
        from_date, to_date = get_week_range()

    if not from_date or not to_date:
        raise click.UsageError("Provide --from and --to dates, or use --today / --week")

    account_id = client.jira.get_my_account_id()
    worklogs = client.get_worklogs_for_user(account_id, from_date, to_date)

    click.echo(format_worklogs_table(worklogs))


@cli.command()
@click.argument("worklog_id", type=int)
def get(worklog_id):
    """Get details of a specific worklog."""
    config = load_config()
    client = TempoClient(config)

    wl = client.get_worklog(worklog_id)
    click.echo(format_worklog_detail(wl))


@cli.command()
@click.argument("worklog_id", type=int)
@click.option("--time", "-t", "duration", default=None, help="New duration (e.g., 2h30m)")
@click.option("--date", "-d", default=None, help="New start date (YYYY-MM-DD)")
@click.option("--comment", "-c", "description", default=None, help="New description")
def update(worklog_id, duration, date, description):
    """Update an existing worklog.

    Note: Tempo's PUT replaces the entire worklog. Fields you don't specify
    will be fetched from the existing worklog to preserve them.
    """
    config = load_config()
    client = TempoClient(config)

    # Fetch existing worklog to preserve unmodified fields
    existing = client.get_worklog(worklog_id)

    seconds = parse_duration(duration) if duration else existing.get("timeSpentSeconds")
    start_date = date or existing.get("startDate")
    if description is None:
        description = existing.get("description")

    client.update_worklog(
        worklog_id=worklog_id,
        time_spent_seconds=seconds,
        start_date=start_date,
        description=description,
    )
    click.echo(f"Worklog {worklog_id} updated.")


@cli.command()
@click.argument("worklog_id", type=int)
@click.option("--yes", "-y", is_flag=True, help="Skip confirmation prompt")
def delete(worklog_id, yes):
    """Delete a worklog."""
    config = load_config()
    client = TempoClient(config)

    if not yes:
        click.confirm(f"Delete worklog {worklog_id}?", abort=True)

    client.delete_worklog(worklog_id)
    click.echo(f"Worklog {worklog_id} deleted.")


@cli.command()
def config():
    """Show current configuration."""
    cfg = load_config()
    click.echo(cfg.display())
