# verl-ci-watch

Unattended daily watch of [verl](https://github.com/verl-project/verl)'s
`nightly_ascend.yml` CI. Collects the last night's runs, analyzes every failed
job, opens fix PRs in **draft** state on verl-project/verl (a human marks them
ready), and writes a dated report.

```
verl-ci-watch/
├── bin/daily.sh        # entry point — collect (deterministic) + analyze (claude -p)
├── PROMPT.md           # mission spec handed to the headless agent
├── .claude/settings.json  # permission allowlist + hard denies (no push, no PR create)
├── data/<DATE>/        # runs.json, jobs tsv, failed-job logs        (generated)
├── reports/<DATE>.md   # the daily report                            (generated)
├── logs/<DATE>-agent.log  # raw headless-agent transcript            (generated)
├── state/seen-failures.json  # cross-day dedup memory                (generated)
├── state/pending-prs/  # audit records of auto-opened draft PRs      (generated)
└── work/verl/          # clean clone; fixes are branched here        (generated)
```

## What it does per run

1. **Collect** (pure `gh`, no LLM): runs of `nightly_ascend.yml` created in the
   last 26 h, per-run job metadata, full logs of every failed/timed-out job.
2. **Analyze** (headless `claude -p`, only if something actually failed): each
   failed job gets a verdict — `VERL_BUG` / `INFRA` / `KNOWN` / `BASELINE_REGRESSION`
   / `DEPENDENCY` / `UNKNOWN` — following `PROMPT.md`. A `VERL_BUG` gets a minimal
   fix on a `ci-fix/*` branch in `work/verl`, pushed to the fork and opened as a
   **draft PR** on verl-project/verl, with an audit record in
   `state/pending-prs/`. Marking a PR ready, merging, commenting, and pushing to
   upstream are hard-denied (prompt + `deny` rules in `.claude/settings.json`
   and mirrored CLI flags in `bin/daily.sh`).
3. **Report**: `reports/<DATE>.md`. Green or cancelled-only days get a stub
   report without spending any tokens.

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
plus a manual `workflow_dispatch` (with `since-hours` / `label` inputs) for
tests and backfills. The ephemeral runner loses nothing: the workflow commits
`state/` and `reports/` back to this repo after every run; `data/`, `logs/`,
`work/` are gitignored.

One-time setup on the kit repo:

```bash
gh secret set VERL_FORK_PAT        # PAT (classic) with `repo` scope:
                                   # pushes branches to your fork + opens draft PRs on verl-project/verl
gh secret set ANTHROPIC_AUTH_TOKEN # API key for your Anthropic-compatible endpoint
gh secret set ANTHROPIC_BASE_URL   # e.g. https://open.bigmodel.cn/api/anthropic
```

Run each in a real terminal (secrets must not pass through chat transcripts).
Without `VERL_FORK_PAT` the run degrades gracefully to analysis-only
(collection + report, no draft PRs). Without `ANTHROPIC_AUTH_TOKEN` the
analysis stage cannot run.

Test end-to-end:

```bash
gh workflow run daily.yml -f since-hours=54 -f label=dispatch-test
gh run watch
```

Notes:

- GitHub cron is UTC-only and may fire a few minutes late — fine here, since
  the last nightly wave can itself run until ~22:15 UTC.
- Scheduled workflows auto-disable after 60 days without repo activity; the
  daily state commits keep the repo active.
- Private-repo usage: a ~45 min/day run ≈ 1.4k Actions minutes/month, inside
  the free 2k tier. A public kit repo would be unlimited, at the cost of
  publishing your reports.
- Once the dispatch test passes, remove any local interim trigger
  (e.g. `CronDelete 7f65dabb`) so the job doesn't run twice per day.

## Deployment B: Linux server (24/7)

Prereqs on the server, once:

```bash
gh auth login          # needs 'repo' scope (read public + push to your fork)
claude                 # Claude Code CLI installed and authenticated
git config --global user.name  "..."   # for fix commits
git config --global user.email "..."
```

Then:

```bash
git clone <this-kit> ~/verl-ci-watch   # or rsync it from Windows
crontab -e
```

Add (assumes server local time is UTC+8; otherwise set `CRON_TZ=Asia/Shanghai`
at the top of the crontab):

```
30 6 * * * ~/verl-ci-watch/bin/daily.sh >> ~/verl-ci-watch/logs/cron.log 2>&1
```

Notes:

- The headless run uses `--permission-mode acceptEdits` plus allow/deny tool
  lists passed as CLI flags (headless runs in an untrusted workspace ignore
  `.claude/settings.json`; the flags mirror it). To instead rely on the
  settings file, open `claude` once interactively in the kit directory and
  accept the trust dialog.
- Transient gateway errors (e.g. API 529) are retried once after 60 s.
- If legitimate analysis commands keep getting blocked, extend the allow list
  (both in `.claude/settings.json` and the `ALLOW_TOOLS`/`DENY_TOOLS` strings
  in `bin/daily.sh`), or on a dedicated server account switch to
  `CLAUDE_FLAGS="--dangerously-skip-permissions"` — the prompt-level "draft
  only, never ready/merge/comment" rules still apply.
- `CLAUDE_MODEL`, `CLAUDE_BIN`, `VERL_CI_REPO`, `VERL_CI_WORKFLOW`,
  `VERL_CI_SINCE_HOURS` are env overrides (see top of `bin/daily.sh`).

## Reviewing an auto-opened draft PR

The agent opens drafts itself; you review and promote them. Find them via the
daily report, the audit records in `state/pending-prs/*.md`, or:

```bash
gh pr list --repo verl-project/verl --author @me --state open
```

Per draft: check the title fits verl's convention `[<modules>] <type>: <description>`,
review the diff, fill in the remaining PR-body checklist items (CI-request Slack
message etc.), then mark it ready:

```bash
gh pr ready --repo verl-project/verl <number>
```

Delete the audit `.md` after the PR is merged or closed so it isn't re-reported.

## Housekeeping

- `work/verl` is reset to `origin/main` at the start of every analysis;
  `ci-fix/*` branches are preserved. Delete a branch after its PR is merged.
- Old `data/` and `logs/` dirs can be pruned; keep `state/` (it is the dedup
  memory) and `reports/`.
