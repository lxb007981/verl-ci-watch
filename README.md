# verl-ci-watch

Unattended daily watch of [verl](https://github.com/verl-project/verl)'s
`nightly_ascend.yml` CI. Collects the last night's runs, analyzes every failed
job, pushes `ci-fix/*` fix branches to your fork — **it never opens PRs, not
even drafts**; a human reviews each branch and opens the PR — and writes a
dated report.

```
verl-ci-watch/
├── bin/daily.sh        # entry point — collect (deterministic) + analyze (claude -p)
├── PROMPT.md           # mission spec handed to the headless agent
├── .claude/settings.json  # permission allowlist + hard denies (no upstream push, no PR create/ready/merge/comment)
├── data/<DATE>/        # runs.json, jobs tsv, failed-job logs        (generated)
├── reports/<DATE>.md   # the daily report                            (generated)
├── logs/<DATE>-agent.log  # raw headless-agent transcript            (generated)
├── state/seen-failures.json  # cross-day dedup memory                (generated)
├── state/pending-prs/  # audit records of pushed fix branches        (generated)
└── work/verl/          # clean clone; fixes are branched here        (generated)
```

## What it does per run

1. **Collect** (pure `gh`, no LLM): runs of `nightly_ascend.yml` created in the
   last 26 h, per-run job metadata, full logs of every failed/timed-out job.
2. **Analyze** (headless `claude -p`, only if something actually failed): each
   failed job gets a verdict — `VERL_BUG` / `INFRA` / `KNOWN` / `BASELINE_REGRESSION`
   / `DEPENDENCY` / `UNKNOWN` — following `PROMPT.md`. A `VERL_BUG` gets a minimal
   fix on a `ci-fix/*` branch in `work/verl`, pushed to the fork with an audit
   record and a prepared PR body in `state/pending-prs/` — no PR is opened.
   Opening a PR (even a draft), marking ready, merging, commenting, and pushing
   to upstream are hard-denied (prompt + `deny` rules in `.claude/settings.json`
   and mirrored CLI flags in `bin/daily.sh`).
3. **Report**: `reports/<DATE>.md`. Every run/job id in the report links to its
   GitHub Actions page (URL forms are injected by `bin/daily.sh`). Green or
   cancelled-only days get a stub report without spending any tokens.

The nightly workflow fires three waves per day (17:00/18:00/19:00 UTC); jobs
have a 180-min timeout, so the last wave can finish as late as ~06:15 in
UTC+8. **06:30 UTC+8 is the intended fire time.**

## Local test run (Git Bash)

```bash
cd /d/rl/verl-ci-watch
bin/daily.sh --since-hours 54 --label backfill-test   # wide window, dated dir
bin/daily.sh --collect-only                           # collection dry-run
```

## Deployment A: GitHub Actions (no server needed)

The kit is itself a git repo with a ready workflow
(`.github/workflows/daily.yml`): scheduled at **22:30 UTC = 06:30 Asia/Shanghai**
plus two safety-net slots (23:30 / 00:30 UTC) that no-op via a guard step once
the day's report exists — GitHub's scheduler is best-effort and has dropped a
slot outright (2026-08-26). A report left by a failed analysis does not count
as done, so the later slots also retry it. Plus a manual `workflow_dispatch`
(with `since-hours` / `label` inputs) for tests and backfills. The ephemeral
runner loses nothing: the workflow commits
`state/` and `reports/` back to this repo after every run; `data/`, `logs/`,
`work/` are gitignored.

One-time setup on the kit repo:

```bash
gh secret set VERL_FORK_PAT        # fine-grained PAT on your fork
                                   # (Contents + Workflows read/write):
                                   # pushes ci-fix/* branches to your fork (PRs are human-opened)
gh secret set ANTHROPIC_AUTH_TOKEN # API key for your Anthropic-compatible endpoint
gh secret set ANTHROPIC_BASE_URL   # e.g. https://open.bigmodel.cn/api/anthropic
```

Run each in a real terminal (secrets must not pass through chat transcripts).
Without `VERL_FORK_PAT` the run degrades gracefully to analysis-only
(collection + report, no fix branches). Without `ANTHROPIC_AUTH_TOKEN` the
analysis stage cannot run.

Test end-to-end:

```bash
gh workflow run daily.yml -f since-hours=54 -f label=dispatch-test
gh run watch
```

Notes:

- GitHub cron is UTC-only and may fire a few minutes late — fine here, since
  the last nightly wave can itself run until ~22:15 UTC. Slots can also be
  dropped entirely under load; that is what the safety-net crons are for
  (backfill a missed day with `gh workflow run daily.yml -f since-hours=36`).
- Scheduled workflows auto-disable after 60 days without repo activity; the
  daily state commits keep the repo active.
- Private-repo usage: a ~45 min/day run ≈ 1.4k Actions minutes/month, inside
  the free 2k tier. A public kit repo would be unlimited, at the cost of
  publishing your reports.

## Notes

- **Permission posture** (user-approved 2026-08-18): broad Bash + WebSearch
  for the unattended agent; safety rests on the dedicated PAT and the hard
  denies — `git push origin`, `gh pr create/ready/merge/comment`,
  `gh issue create/comment`, `gh run rerun`, `rm -rf` — in the
  `ALLOW_TOOLS`/`DENY_TOOLS` strings in `bin/daily.sh` (mirrored in
  `.claude/settings.json`), plus PROMPT.md rule 5 keeping commands in simple
  form so denies match reliably.
- Transient gateway errors (e.g. API 529) are retried once after 60 s.
- `CLAUDE_MODEL`, `CLAUDE_BIN`, `VERL_CI_REPO`, `VERL_CI_WORKFLOW` are env
  overrides (see top of `bin/daily.sh`).

## Reviewing a pushed fix branch (you open the PR)

The agent never opens PRs. It pushes `ci-fix/*` branches to your fork, writes
a prepared PR body to `state/pending-prs/ci-fix_<slug>.body.md`, and records an
audit entry in `state/pending-prs/ci-fix_<slug>.md` (branch URL, compare link,
root cause). Find candidates via the daily report, the audit records, or:

```bash
git ls-remote --heads https://github.com/<you>/verl 'ci-fix/*'
```

Per branch: review the diff (the audit record's compare link is the quickest
view), adjust the prepared title/body as needed, then open the PR yourself:

```bash
gh pr create --repo verl-project/verl --head <you>:ci-fix/<slug> \
  --title "<title>" --body-file state/pending-prs/ci-fix_<slug>.body.md
```

Delete the audit `.md` (and `.body.md`) after the PR is merged or closed so it
isn't re-reported.

## Housekeeping (local runs only)

On Actions `data/`, `logs/`, and `work/` are gitignored and ephemeral; these
only matter when you run `bin/daily.sh` locally.

- `work/verl` is reset to `origin/main` at the start of every analysis;
  `ci-fix/*` branches are preserved. Delete a branch after its PR is merged.
- Old `data/` and `logs/` dirs can be pruned; keep `state/` (it is the dedup
  memory) and `reports/`.
