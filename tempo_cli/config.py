import os
import sys


def _mask(value):
    if not value or len(value) <= 4:
        return "****"
    return value[:4] + "*" * (len(value) - 4)


class TempoConfig:
    def __init__(self):
        # Required: Tempo Cloud API
        self.tempo_api_token = os.environ.get("TEMPO_API_TOKEN", "")
        self.tempo_api_url = os.environ.get("TEMPO_API_URL", "https://api.tempo.io").rstrip("/")

        # Required: Jira Cloud (for resolving issue keys and getting account ID)
        self.jira_url = os.environ.get("JIRA_URL", "").rstrip("/")
        self.jira_email = os.environ.get("JIRA_EMAIL", "")
        self.jira_api_token = os.environ.get("JIRA_API_TOKEN", "")

    def validate(self):
        missing = []
        if not self.tempo_api_token:
            missing.append("TEMPO_API_TOKEN")
        if not self.jira_url:
            missing.append("JIRA_URL")
        if not self.jira_email:
            missing.append("JIRA_EMAIL")
        if not self.jira_api_token:
            missing.append("JIRA_API_TOKEN")
        if missing:
            print(f"Error: Missing environment variables: {', '.join(missing)}", file=sys.stderr)
            print("\nSet them with:", file=sys.stderr)
            print("  export TEMPO_API_TOKEN=your-tempo-api-token", file=sys.stderr)
            print("  export JIRA_URL=https://yoursite.atlassian.net", file=sys.stderr)
            print("  export JIRA_EMAIL=your-email@example.com", file=sys.stderr)
            print("  export JIRA_API_TOKEN=your-atlassian-api-token", file=sys.stderr)
            print("\nTempo token: Jira > Tempo > Settings > API Integration", file=sys.stderr)
            print("Jira token:  https://id.atlassian.com/manage-profile/security/api-tokens", file=sys.stderr)
            sys.exit(1)

    @property
    def tempo_base_url(self):
        return f"{self.tempo_api_url}/4"

    def display(self):
        return (
            f"Tempo API URL:  {self.tempo_api_url}\n"
            f"Tempo Token:    {_mask(self.tempo_api_token)}\n"
            f"Jira URL:       {self.jira_url}\n"
            f"Jira Email:     {self.jira_email}\n"
            f"Jira Token:     {_mask(self.jira_api_token)}"
        )


def load_config():
    config = TempoConfig()
    config.validate()
    return config
