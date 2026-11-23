"""Prepare the analysis queue and maintainer reminders for one collection."""

import json
import re
import subprocess
import sys
from pathlib import Path


def read_rules(path):
    rules = json.loads(path.read_text(encoding="utf-8"))
    fields = {"job", "log_contains", "reason"}
    if not isinstance(rules, list) or any(
        not isinstance(rule, dict) or rule.keys() != fields
        or not all(isinstance(v, str) and v.strip() and "\n" not in v and "\r" not in v for v in rule.values())
        for rule in rules
    ):
        raise ValueError(f"{path} must contain a list of single-line job, log_contains and reason strings")
    return rules


def failed_output(repo, job_id):
    result = subprocess.run(
        ["gh", "run", "view", "--repo", repo, "--job", job_id, "--log-failed"],
        capture_output=True, encoding="utf-8", errors="replace",
    )
    if result.returncode:
        return []
    lines = []
    for line in result.stdout.splitlines():
        # gh prefixes output with the job name, step name and timestamp.
        message = line.split("\t", 2)[-1]
        message = re.sub(r"^\d{4}-\d\d-\d\dT[\d:.]+Z ", "", message)
        if message.strip():
            lines.append(message)
    return lines


def fragments_in_log(path, fragments):
    found = set()
    if fragments:
        with path.open(encoding="utf-8", errors="replace") as stream:
            for index, line in enumerate(stream):
                if index == 0 and line.startswith("LOG FETCH FAILED"):
                    break
                found.update(fragment for fragment in fragments - found if fragment in line)
                if found == fragments:
                    break
    return found


def prepare(root, data, repo, today):
    rules = read_rules(root / "state/human-handled.json")
    history_path = root / "state/last-human-handled.json"
    history = json.loads(history_path.read_text(encoding="utf-8")) if history_path.exists() else {}
    history_changed = False
    reminders = []
    queue = []
    for row in sys.stdin:
        run, job_id, job, filename, step_count = row.rstrip("\n").split("\t")
        url = f"https://github.com/{repo}/actions/runs/{run}/job/{job_id}"
        relevant = [r for r in rules if r["job"] == job]
        active = {r["log_contains"] for r in relevant}
        known = history.get(job, {})
        found = fragments_in_log(data / filename, active.union(known))
        notes = []
        for fragment in sorted(found - active):
            notes.append(f"Rule removed for {fragment!r}. Investigate afresh if the matching dedup entry was last seen on or before {known[fragment]}.")
        candidates = [r for r in relevant if r["log_contains"] in found]
        if candidates:
            lines = failed_output(repo, job_id)
            matched = [
                rule for rule in candidates
                if not lines or any(rule["log_contains"] in line for line in lines)
            ]
            for rule in matched:
                fragment = rule["log_contains"]
                reminders.append(f"- [{job}]({url}) — {rule['reason']}")
                if known.get(fragment, "") < today:
                    history.setdefault(job, {})[fragment] = today
                    history_changed = True
                notes.append(f"Already reported as human-handled: {fragment!r}. Skip diagnosis and fixes for this error.")
            # Incomplete or mixed evidence stays in the analysis queue.
            if step_count == "1" and lines and matched and all(
                any(rule["log_contains"] in line for rule in matched)
                or re.fullmatch(r"##\[error\]Process completed with exit code \d+\.?", line)
                for line in lines
            ):
                continue
        entry = f"- {job} — run {run}, job {job_id}, log: {(data / filename).as_posix()}, url: {url}"
        queue.append("\n  ".join([entry, *notes]))
    (data / "analysis-queue.txt").write_text("\n".join(queue), encoding="utf-8")
    (data / "human-handled.md").write_text("\n".join(reminders) + ("\n" if reminders else ""), encoding="utf-8")
    if history_changed:
        temp = history_path.with_suffix(".json.new")
        temp.write_text(json.dumps(history, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temp.replace(history_path)


if __name__ == "__main__":
    prepare(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], sys.argv[4])
