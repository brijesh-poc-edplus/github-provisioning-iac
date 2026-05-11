import os
from dataclasses import dataclass
from typing import Any

import requests


REQUEST_LABEL = "repo-request"
PROCESSED_LABEL = "agent-processed"
BLOCKED_LABEL = "agent-blocked"


@dataclass(frozen=True)
class RepoRequestIssue:
    number: int
    title: str
    body: str
    url: str
    labels: list[str]


class GitHubIssueClient:
    """Phase 1 adapter: GitHub Issues behave like the JSM ticket source."""

    def __init__(self) -> None:
        self.repository = os.environ["GITHUB_REPOSITORY"]
        self.token = os.environ["GITHUB_TOKEN"]

    def fetch_open_repo_requests(self) -> list[RepoRequestIssue]:
        response = requests.get(
            f"https://api.github.com/repos/{self.repository}/issues",
            headers=self._headers(),
            params={
                "state": "open",
                "labels": REQUEST_LABEL,
                "per_page": "100",
            },
            timeout=30,
        )
        response.raise_for_status()

        issues = []
        for issue in response.json():
            if "pull_request" in issue:
                continue
            labels = [label["name"] for label in issue.get("labels", [])]
            if PROCESSED_LABEL in labels:
                continue
            issues.append(
                RepoRequestIssue(
                    number=issue["number"],
                    title=issue["title"],
                    body=issue.get("body") or "",
                    url=issue["html_url"],
                    labels=labels,
                )
            )
        return issues

    def add_comment(self, issue_number: int, body: str) -> None:
        response = requests.post(
            f"https://api.github.com/repos/{self.repository}/issues/{issue_number}/comments",
            headers=self._headers(),
            json={"body": body},
            timeout=30,
        )
        response.raise_for_status()

    def add_labels(self, issue_number: int, labels: list[str]) -> None:
        self._ensure_labels(labels)
        response = requests.post(
            f"https://api.github.com/repos/{self.repository}/issues/{issue_number}/labels",
            headers=self._headers(),
            json={"labels": labels},
            timeout=30,
        )
        response.raise_for_status()

    def _ensure_labels(self, labels: list[str]) -> None:
        for label in labels:
            response = requests.post(
                f"https://api.github.com/repos/{self.repository}/labels",
                headers=self._headers(),
                json=_label_payload(label),
                timeout=30,
            )
            if response.status_code not in {201, 422}:
                response.raise_for_status()

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self.token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        }


def _label_payload(label: str) -> dict[str, Any]:
    colors = {
        REQUEST_LABEL: "0e8a16",
        PROCESSED_LABEL: "5319e7",
        BLOCKED_LABEL: "b60205",
    }
    return {
        "name": label,
        "color": colors.get(label, "ededed"),
        "description": "Managed by the repository request agent.",
    }
