#!/usr/bin/env bash
# verl-ci-watch daily runner.
#
# Two stages:
#   1. Collect (this script, deterministic, no LLM): pull the last ~26h of
#      nightly_ascend.yml runs, save per-run job metadata, download logs of
#      failed jobs into a dated data dir.
#   2. Analyze (headless `claude -p`): only if at least one job actually
#      failed. Green/cancelled-only days get a bash-only stub report.
#
# Portable: works under Git Bash (Windows) and Linux. No jq required (gh's
# built-in --jq is used). Deploy on Linux via cron (see README.md).
#
# Usage:
#   bin/daily.sh                       # normal daily run
#   bin/daily.sh --since-hours 54      # backfill a wider window
#   bin/daily.sh --label 2026-08-17    # override the dated dir name
#   bin/daily.sh --collect-only        # stop after stage 1
#   bin/daily.sh --no-llm-report       # like collect-only but writes stub report
#
# Environment overrides:
#   VERL_CI_REPO, VERL_CI_WORKFLOW, CLAUDE_BIN, CLAUDE_MODEL, CLAUDE_FLAGS

set -euo pipefail

# --- configuration -----------------------------------------------------------

REPO="${VERL_CI_REPO:-verl-project/verl}"
WORKFLOW="${VERL_CI_WORKFLOW:-nightly_ascend.yml}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
WATCH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SINCE_HOURS=26          # covers the 3 daily waves (17/18/19 UTC) + margin
LABEL="$(date +%F)"     # dated dir name, local calendar day
COLLECT_ONLY=0
NO_LLM_REPORT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --since-hours)  SINCE_HOURS="$2"; shift 2 ;;
    --label)        LABEL="$2"; shift 2 ;;
    --collect-only) COLLECT_ONLY=1; shift ;;
    --no-llm-report) NO_LLM_REPORT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

DATA_DIR="$WATCH_ROOT/data/$LABEL"
LOG_DIR="$DATA_DIR/logs"
STATE_DIR="$WATCH_ROOT/state"
REPORT="$WATCH_ROOT/reports/$LABEL.md"
mkdir -p "$DATA_DIR" "$LOG_DIR" "$STATE_DIR" "$WATCH_ROOT/reports" "$WATCH_ROOT/logs"

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
fail() { log "ERROR: $*"; exit 1; }

# --- stage 1: collect --------------------------------------------------------

command -v gh >/dev/null 2>&1 || fail "gh CLI not found in PATH"

CUTOFF_UTC="$(date -u -d "-${SINCE_HOURS} hours" '+%Y-%m-%dT%H:%M:%SZ')"
log "collecting ${WORKFLOW} runs from ${REPO} created since ${CUTOFF_UTC}"

# gh's built-in jq selects runs newer than the cutoff. CUTOFF_UTC is a safe
# charset (digits/dashes/colons/Z) so interpolating it into the filter is OK.
# Two calls: runs.json is the full pretty reference for the agent; runs.tsv is
# the compact driver for the loop below.
gh run list \
  --repo "$REPO" \
  --workflow "$WORKFLOW" \
  --limit 30 \
  --json databaseId,displayTitle,status,conclusion,event,createdAt,updatedAt,headBranch \
  --jq "map(select(.createdAt > \"${CUTOFF_UTC}\"))" > "$DATA_DIR/runs.json"

gh run list \
  --repo "$REPO" \
  --workflow "$WORKFLOW" \
  --limit 30 \
  --json databaseId,status,conclusion,createdAt \
  --jq "map(select(.createdAt > \"${CUTOFF_UTC}\")) | .[] | [.databaseId, .status, (.conclusion // \"\"), .createdAt] | @tsv" \
  > "$DATA_DIR/runs.tsv"

RUNS_IN_WINDOW="$(wc -l < "$DATA_DIR/runs.tsv")"
log "found ${RUNS_IN_WINDOW} run(s) in window"

FAILED_JOBS=()   # "runId|jobId|jobName"
CANCELLED_RUNS=()

while IFS=$'\t' read -r run_id status conclusion _created_at; do
  [ -n "$run_id" ] || continue
  if [ "$conclusion" = "cancelled" ]; then
    CANCELLED_RUNS+=("$run_id")
    continue
  fi
  [ "$status" = "completed" ] || { log "run $run_id still $status — skipping job detail"; continue; }
  [ "$conclusion" = "failure" ] || continue

  gh run view "$run_id" --repo "$REPO" --json jobs \
    --jq '.jobs[] | select(.conclusion == "failure" or .conclusion == "timed_out") | [.databaseId, .name, .conclusion, .startedAt, .completedAt] | @tsv' \
    > "$DATA_DIR/jobs_run${run_id}.tsv"

  while IFS=$'\t' read -r job_id job_name job_conclusion _ _; do
    [ -n "$job_id" ] || continue
    FAILED_JOBS+=("${run_id}|${job_id}|${job_name}")
    safe_name="$(printf '%s' "$job_name" | tr -c 'A-Za-z0-9._-' '_' | sed 's/_*$//;s/^_*//')"
    out="$LOG_DIR/r${run_id}_${safe_name}.log"
    if [ -s "$out" ] && ! head -n1 "$out" | grep -q '^LOG FETCH FAILED'; then
      log "log already present: $out"
    else
      log "downloading failed job log: $job_name (run $run_id, $job_conclusion)"
      if ! gh run view --repo "$REPO" --job "$job_id" --log > "$out" 2>"$out.err"; then
        printf 'LOG FETCH FAILED\n' > "$out"
        log "WARN: log fetch failed for job $job_id (expired?); recorded placeholder"
      else
        rm -f "$out.err"
      fi
    fi
  done < "$DATA_DIR/jobs_run${run_id}.tsv"
done < "$DATA_DIR/runs.tsv"

# --- decide whether the LLM stage is needed -----------------------------------

write_stub_report() {
  {
    echo "# verl nightly Ascend CI watch — ${LABEL}"
    echo
    echo "- No failed jobs in the last ${SINCE_HOURS}h."
    if [ "${#CANCELLED_RUNS[@]}" -gt 0 ]; then
      echo "- Cancelled runs (infra noise, not analyzed):"
      for rid in "${CANCELLED_RUNS[@]}"; do
        echo "  - [${rid}](https://github.com/${REPO}/actions/runs/${rid})"
      done
    fi
    echo "- Raw run metadata: \`data/${LABEL}/runs.json\`"
  } > "$REPORT"
  log "stub report written: $REPORT"
}

if [ "${#FAILED_JOBS[@]}" -eq 0 ]; then
  log "no failed jobs — writing stub report, skipping LLM analysis"
  write_stub_report
  exit 0
fi

[ "$COLLECT_ONLY" = "1" ] && { log "--collect-only: stopping before analysis"; exit 0; }

# --- stage 2: headless analysis ----------------------------------------------

command -v "$CLAUDE_BIN" >/dev/null 2>&1 || fail "claude CLI not found (CLAUDE_BIN=$CLAUDE_BIN)"

# Ensure the analysis work clone exists (public repo; no auth needed to clone).
if [ ! -d "$WATCH_ROOT/work/verl/.git" ]; then
  log "initial clone of verl into work/verl (one-time)"
  git clone --quiet https://github.com/verl-project/verl "$WATCH_ROOT/work/verl"
fi

PROMPT="$(cat "$WATCH_ROOT/PROMPT.md")

---

# Invocation context (appended by bin/daily.sh — trust these values)

- Report date label: ${LABEL}
- Data directory: ${DATA_DIR}
- Failed jobs to analyze (${#FAILED_JOBS[@]}):"

for entry in "${FAILED_JOBS[@]}"; do
  IFS='|' read -r run_id job_id job_name <<< "$entry"
  safe_name="$(printf '%s' "$job_name" | tr -c 'A-Za-z0-9._-' '_' | sed 's/_*$//;s/^_*//')"
  PROMPT="$PROMPT
  - ${job_name} — run ${run_id}, job ${job_id}, log: ${LOG_DIR}/r${run_id}_${safe_name}.log, url: https://github.com/${REPO}/actions/runs/${run_id}/job/${job_id}"
done

PROMPT="$PROMPT
- Cancelled runs in window (report as infra noise only): ${CANCELLED_RUNS[*]:-none}
- Actions link forms (link every run/job id mentioned in the report to its page):
  run https://github.com/${REPO}/actions/runs/<runId>
  job https://github.com/${REPO}/actions/runs/<runId>/job/<jobId>
- Watch root: ${WATCH_ROOT}
- Write the dated report to: ${REPORT}"

log "starting headless analysis (${#FAILED_JOBS[@]} failed job(s)) — output to logs/${LABEL}-agent.log"

# Tool permissions are passed as CLI flags because an untrusted workspace's
# .claude/settings.json entries are silently ignored in headless mode. These
# mirror .claude/settings.json (which takes over once the dir is trusted).
# Policy (user-approved 2026-08-18): broad Bash + WebSearch — the dedicated
# PAT is content-view + PR-create only, bounding GitHub-side blast radius.
# Hard denies still block ready/merge/comment/upstream-push/rerun/rm -rf;
# PROMPT.md rule 5 keeps commands in simple form so denies match reliably.
ALLOW_TOOLS='Bash,WebSearch'
DENY_TOOLS='Bash(git push origin:*),Bash(gh pr ready:*),Bash(gh pr merge:*),Bash(gh pr comment:*),Bash(gh issue create:*),Bash(gh issue comment:*),Bash(gh run rerun:*),Bash(gh workflow:*),Bash(rm -rf:*),WebFetch'

run_claude() {
  "$CLAUDE_BIN" -p "$PROMPT" \
    ${CLAUDE_MODEL:+--model "$CLAUDE_MODEL"} \
    ${CLAUDE_FLAGS:-} \
    --permission-mode acceptEdits \
    --allowedTools "$ALLOW_TOOLS" \
    --disallowedTools "$DENY_TOOLS" \
    2>&1 | tee "$WATCH_ROOT/logs/${LABEL}-agent.log"
}

cd "$WATCH_ROOT"
set +e
run_claude; RC="${PIPESTATUS[0]}"
if [ "$RC" -ne 0 ]; then
  log "claude exited ${RC} (transient gateway errors are common) — one retry in 60s"
  sleep 60
  run_claude; RC="${PIPESTATUS[0]}"
fi
set -e

if [ "$RC" -ne 0 ]; then
  log "WARN: claude exited with code ${RC}; check logs/${LABEL}-agent.log"
  # Leave a visible artifact for the morning review even on hard failure.
  {
    echo "# verl nightly Ascend CI watch — ${LABEL}"
    echo
    echo "- ⚠ Analysis stage FAILED (claude exit ${RC})."
    echo "- Cause is in the CI run log (or \`logs/${LABEL}-agent.log\` locally);"
    echo "  typically gateway 529 or missing/expired \`ANTHROPIC_AUTH_TOKEN\`."
    echo "- Collected data is intact under \`data/${LABEL}/\` — rerun"
    echo "  \`bin/daily.sh --label ${LABEL} --since-hours <N>\` once recovered."
  } > "$REPORT"
  [ "$NO_LLM_REPORT" = "1" ] || exit "$RC"
fi

log "done. report: $REPORT (exit ok)"
