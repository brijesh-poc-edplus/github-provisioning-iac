from pathlib import Path

from csv_manager import CsvChange, CsvManager
from issue_parser import parse_issue_body
from jira_client import BLOCKED_LABEL, PROCESSED_LABEL, GitHubIssueClient, RepoRequestIssue
from pr_builder import PullRequest, create_pull_request
from validator import validate_request


def main() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    client = GitHubIssueClient()
    csv_manager = CsvManager(repo_root)

    issues = client.fetch_open_repo_requests()
    if not issues:
        print("No open repository request issues found.")
        return

    processed_issue_numbers: list[int] = []
    all_changes: list[CsvChange] = []
    touched_files: set[Path] = set()
    no_change_issues: list[int] = []

    for issue in issues:
        request = parse_issue_body(issue.body)
        validation = validate_request(request)

        if not validation.is_valid:
            _mark_blocked(client, issue, validation.errors)
            continue

        update_result = csv_manager.apply_request(request, issue.number)
        processed_issue_numbers.append(issue.number)
        all_changes.extend(update_result.changes)
        touched_files.update(update_result.touched_files)

        if not update_result.changed:
            no_change_issues.append(issue.number)

    if not processed_issue_numbers:
        print("No valid repository requests were ready to process.")
        return

    if not touched_files:
        for issue_number in no_change_issues:
            client.add_comment(
                issue_number,
                "The repository request already matches the CSV source of truth. No PR was needed.",
            )
            client.add_labels(issue_number, [PROCESSED_LABEL])
        print("All valid requests already matched the CSV source of truth.")
        return

    pr = create_pull_request(repo_root, processed_issue_numbers, all_changes, touched_files)
    _mark_processed(client, processed_issue_numbers, pr)
    print(f"Created PR: {pr.url}")


def _mark_blocked(client: GitHubIssueClient, issue: RepoRequestIssue, errors: list[str]) -> None:
    body = "\n".join(
        [
            "The repository request agent could not process this issue because validation failed.",
            "",
            "Please fix the form fields and remove the `agent-blocked` label before rerunning the agent.",
            "",
            *[f"- {error}" for error in errors],
        ]
    )
    client.add_comment(issue.number, body)
    client.add_labels(issue.number, [BLOCKED_LABEL])
    print(f"Issue #{issue.number} blocked: {'; '.join(errors)}")


def _mark_processed(client: GitHubIssueClient, issue_numbers: list[int], pr: PullRequest) -> None:
    for issue_number in issue_numbers:
        client.add_comment(
            issue_number,
            "\n".join(
                [
                    "The repository request agent processed this issue.",
                    "",
                    f"Pull request: {pr.url}",
                    f"Branch: `{pr.branch}`",
                ]
            ),
        )
        client.add_labels(issue_number, [PROCESSED_LABEL])


if __name__ == "__main__":
    main()
