# Pending draft PR — ci-fix/gspo-qwen3-8b-8npu

> **STATUS: CLOSED 2026-08-21 — SUPERSEDED UPSTREAM, DO NOT OPEN.**
> PR #7456 "[ci] chore: Update ascend ci image" (commit `6cbca9ce`, merged
> 2026-08-20 13:30 UTC) applied the identical one-line fix
> (`NGPUS_PER_NODE:-16` → `:-8`) to
> `tests/special_npu/nightly_ci_ascend/run_gspo_qwen3_8b_fsdp2_npu.sh:25`.
> Verified on `origin/main`. Opening this branch as a PR would be a duplicate.
> The job was **skipped** in both 2026-08-20 nightly runs, so #7456 is not yet
> exercised by a nightly — if the job runs and fails again, investigate fresh
> (do not assume this old signature). The fork branch is left as-is. See
> `reports/2026-08-21.md`.

- **Date**: 2026-08-20
- **PR title**: `[ci] fix: default GSPO Qwen3-8B FSDP2 nightly to 8 NPUs for a2b3-8 runner`
- **PR URL**: **not opened — blocked by PAT permissions** (see below). Ready-to-open:
  https://github.com/verl-project/verl/compare/main...lxb007981:verl:ci-fix/gspo-qwen3-8b-8npu?expand=1
- **Branch**: `ci-fix/gspo-qwen3-8b-8npu` on fork `lxb007981/verl`
  (head `84e85d6b`, one commit on top of fork-main `62ac6d6e`; upstream main
  `b256ebf8` merges cleanly — the only files-changed is the one-line fix below.)
- **Target job/run**: `nightlyCI_gspo-qwen3-8b-fsdp2-vllm_ascend`, run
  `32293302531`, job `96198832871`,
  log `data/2026-08-20/logs/r32293302531_nightlyCI_gspo-qwen3-8b-fsdp2-vllm_ascend.log`
- **Root cause**: PR #7444 (merged 2026-08-17, commit `b5a35481`) moved this
  job from the 16-NPU `linux-aarch64-a3-16` runner to the 8-NPU
  `linux-aarch64-a2b3-8` runner but left
  `tests/special_npu/nightly_ci_ascend/run_gspo_qwen3_8b_fsdp2_npu.sh` at
  `NGPUS_PER_NODE=16`. Every nightly since then aborts in
  `ResourcePoolManager._check_resource_available` with
  `ValueError: Total available GPUs 8.0 is less than total desired GPUs 16`
  before any worker starts (npu-smi at job start shows exactly 8 × 910B3,
  all healthy). Verdict: **VERL_BUG**.
- **Fix**: one line, `NGPUS_PER_NODE=${NGPUS_PER_NODE:-16}` → `:-8`. Matches
  the sibling `run_ppo_qwen3-8b_fsdp_npu.sh` (same model, same runner label).
  All other defaults (SP=2, rollout TP=2, batch 32, mini-batch 16,
  FSDP=-1) divide cleanly with 8 GPUs. `bash -n` clean; no NPU to run e2e.
- **PR body**: kept verbatim at `state/pending-prs/ci-fix_gspo-qwen3-8b-8npu.body.md`
  (follows `.github/PULL_REQUEST_TEMPLATE.md`, includes the triage note block,
  duplicate-check query links, and the honest log-analysis-only Test section).

## Why the PR was not opened (permission block)

- `git push` to the fork: **allowed** (branch is pushed).
- `git push` carrying upstream workflow-file changes: **denied** — PAT lacks
  `workflow` scope ("refusing to allow a Personal Access Token to create or
  update workflow `.github/workflows/e2e_ppo_trainer_megatron_vllm_rocm.yml`
  without `workflow` scope"). Worked around by basing the branch on the fork's
  current main (`62ac6d6e`, an ancestor of upstream main) so the push carries
  only the script-only commit.
- `POST repos/lxb007981/verl/merge-upstream` (fork sync): **denied**, same
  workflow-scope check.
- `POST repos/lxb007981/verl/git/refs` (create branch via API): **denied**
  ("Resource not accessible by personal access token").
- `gh pr create --draft` (GraphQL) and `POST repos/verl-project/verl/pulls`
  (REST): **both denied** — "Resource not accessible by personal access
  token". The token cannot create PRs on verl-project/verl at all.

**Kit fix needed (human)**: issue a PAT that can create PRs on
verl-project/verl (classic PAT with `public_repo` scope is sufficient; a
fine-grained PAT must include verl-project/verl with Pull requests: write).
Optionally add `workflow` scope so fix branches can be based on current
origin/main instead of fork-main.

## Next run (tomorrow) should

1. If the same signature recurs: re-fetch this branch (`git fetch lxb
   ci-fix/gspo-qwen3-8b-8npu`), rebase/cherry-pick onto the new fork-main or
   origin/main (respecting the workflow-scope constraint), push, and retry
   `gh pr create --draft --head lxb007981:ci-fix/gspo-qwen3-8b-8npu
   --body-file state/pending-prs/ci-fix_gspo-qwen3-8b-8npu.body.md` — do not
   open a second PR if one already exists.
2. Update this record with the PR URL once opened, then move it out of
   "pending" only after the PR is merged or closed.
