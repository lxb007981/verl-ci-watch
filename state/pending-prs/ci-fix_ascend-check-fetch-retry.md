# ci-fix/ascend-check-fetch-retry — audit record

- PR title (for the human to reuse): `[ci] fix: harden nightly Ascend check-step fetches against runner egress brownouts`
- Branch: `ci-fix/ascend-check-fetch-retry` (head c7d4aa3e, parent = origin/main 3efe38c7)
- Fork branch URL: https://github.com/lxb007981/verl/tree/ci-fix/ascend-check-fetch-retry
- Compare link: https://github.com/verl-project/verl/compare/main...lxb007981:ci-fix/ascend-check-fetch-retry
- PR body: `state/pending-prs/ci-fix_ascend-check-fetch-retry.body.md`
- Date pushed: 2026-09-12; REBASED 2026-09-19 onto main 3efe38c7 (was 96827a98 on 10db40d0; conflicted with #7852's qwen3_vl check-step log-diagnostics — resolution keeps #7852's wait/`ls -l`/`wc -c`/`tail` block and `--log "$LOG"` and hardens its two curl lines; delta re-verified = exactly the 10 curl lines of the 5 active jobs, yaml.safe_load OK). Still awaiting a human-opened PR.
- Target job/run ids:
  - nightlyCI_ppo-qwen3-8b-fsdp-vllm_ascend — run 34626310730, job 103352157796 (2026-09-11 17:12 UTC, exit 56 on baseline.txt fetch after 15.5-min stall; training had completed a healthy 15/15)
  - (family precedent) same job — run 33783219400, job 100741676218 (2026-09-04, exit 52 on check_npu.py fetch after 12.6-min hang)
- Root cause: INFRA (runner-cluster egress brownout to raw.githubusercontent.com) + a verl-workflow weakness: `--retry 3` without `--retry-all-errors` never retries curl exit 52/56, so one blocked SSL_read burned 15.5 min and then failed the step, discarding a healthy run. Fix = harden all 10 check-step curl lines (5 active jobs) with `--retry 5 --retry-all-errors --retry-delay 5 --connect-timeout 15 --max-time 120`.
- Validation: log analysis only, no NPU. yaml.safe_load OK; exact new curl command executed against the real recipe URL (6188 B fetch OK, curl 8.5.0); dry-run caught and fixed a wrong flag spelling (`--maximum-time` → `--max-time`) before commit. CI images are Ubuntu 22.04-based (curl ≥ 7.81 ≥ 7.71.1 required by --retry-all-errors).
- Upstream duplicate check (2026-09-12): `gh search prs/issues` for "nightly_ascend curl retry", "check_npu baseline", "retry-all-errors" — empty (two unrelated GPU issue hits).
- Classification note: the failure itself is INFRA (network), but the run-killing weakness is in verl's own workflow, so the hardening branch is a `ci` fix. First occurrence 2026-09-04 was deliberately left unpatched as a one-off; the 2026-09-11 recurrence (plus two stall-recover evenings 09-09/09-11) triggered this per the standing note in seen-failures.
- STATUS 2026-09-21: branch NOT rebased — main moved 3efe38c7 -> f542ae22 but none of the 6 new commits touches `.github/workflows/nightly_ascend.yml`; `git merge-tree` against f542ae22 is conflict-free, so head c7d4aa3e still applies cleanly. Curl-INFRA did not recur tonight (ppo-8b check-step fetches ~3 s). Still awaiting a human-opened PR.
