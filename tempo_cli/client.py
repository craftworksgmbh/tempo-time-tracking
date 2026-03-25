import requests

from tempo_cli.config import TempoConfig


class JiraClient:
    """Minimal Jira Cloud REST API client for resolving issue keys and account info."""

    def __init__(self, config: TempoConfig):
        self.config = config
        self.session = requests.Session()
        self.session.auth = (config.jira_email, config.jira_api_token)
        self.session.headers.update({"Accept": "application/json"})
        self._account_id = None

    def _url(self, path):
        return f"{self.config.jira_url}/rest/api/3{path}"

    def get_my_account_id(self):
        if self._account_id:
            return self._account_id
        resp = self.session.get(self._url("/myself"))
        resp.raise_for_status()
        self._account_id = resp.json()["accountId"]
        return self._account_id

    def resolve_issue_id(self, issue_key):
        """Resolve an issue key (e.g., PROJ-123) to its numeric ID."""
        resp = self.session.get(self._url(f"/issue/{issue_key}"), params={"fields": "id"})
        resp.raise_for_status()
        return int(resp.json()["id"])


class TempoClient:
    """Tempo Cloud REST API v4 client."""

    def __init__(self, config: TempoConfig):
        self.config = config
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Bearer {config.tempo_api_token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        })
        self.jira = JiraClient(config)

    def _url(self, path):
        return f"{self.config.tempo_base_url}{path}"

    def _handle_response(self, resp):
        if resp.status_code >= 400:
            try:
                detail = resp.json()
            except Exception:
                detail = resp.text
            raise RuntimeError(f"Tempo API error {resp.status_code}: {detail}")
        return resp

    def _resolve_issue(self, issue):
        """Accept either a numeric ID or an issue key like PROJ-123."""
        try:
            return int(issue)
        except ValueError:
            return self.jira.resolve_issue_id(issue)

    def create_worklog(self, issue, time_spent_seconds, start_date, description=None, author_account_id=None):
        if not author_account_id:
            author_account_id = self.jira.get_my_account_id()
        payload = {
            "authorAccountId": author_account_id,
            "issueId": self._resolve_issue(issue),
            "startDate": start_date,
            "timeSpentSeconds": time_spent_seconds,
        }
        if description:
            payload["description"] = description
        resp = self.session.post(self._url("/worklogs"), json=payload)
        self._handle_response(resp)
        return resp.json()

    def search_worklogs(self, from_date, to_date, author_ids=None, issue_ids=None, project_ids=None):
        payload = {
            "from": from_date,
            "to": to_date,
        }
        if author_ids:
            payload["authorIds"] = author_ids if isinstance(author_ids, list) else [author_ids]
        if issue_ids:
            payload["issueIds"] = issue_ids if isinstance(issue_ids, list) else [issue_ids]
        if project_ids:
            payload["projectIds"] = project_ids if isinstance(project_ids, list) else [project_ids]
        resp = self.session.post(self._url("/worklogs/search"), json=payload)
        self._handle_response(resp)
        data = resp.json()
        return data.get("results", [])

    def get_worklogs_for_user(self, account_id, from_date, to_date):
        params = {"from": from_date, "to": to_date}
        resp = self.session.get(self._url(f"/worklogs/user/{account_id}"), params=params)
        self._handle_response(resp)
        data = resp.json()
        return data.get("results", [])

    def get_worklog(self, worklog_id):
        resp = self.session.get(self._url(f"/worklogs/{worklog_id}"))
        self._handle_response(resp)
        return resp.json()

    def update_worklog(self, worklog_id, time_spent_seconds, start_date, author_account_id=None, description=None):
        if not author_account_id:
            author_account_id = self.jira.get_my_account_id()
        payload = {
            "authorAccountId": author_account_id,
            "startDate": start_date,
            "timeSpentSeconds": time_spent_seconds,
        }
        if description is not None:
            payload["description"] = description
        resp = self.session.put(self._url(f"/worklogs/{worklog_id}"), json=payload)
        self._handle_response(resp)
        return resp.json()

    def delete_worklog(self, worklog_id):
        resp = self.session.delete(self._url(f"/worklogs/{worklog_id}"))
        self._handle_response(resp)
