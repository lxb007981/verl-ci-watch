# ci-fix/ascend-a3-mbridge-clone-collision — audit record

- **Date pushed:** 2026-09-05 (analyzing nightly window of 2026-09-04 UTC evening); rebased & re-pushed 2026-09-08, 2026-09-09
- **PR title (for the human to reuse):** `[ci] fix: clear pre-baked /Megatron-Bridge before cloning pinned commit`
- **Branch:** `ci-fix/ascend-a3-mbridge-clone-collision` (originally from `origin/main` = `23af6a7a`, head `be8d19aa`; 2026-09-08 rebased onto `d040717b`, head `586416d5`; since 2026-09-09 rebased onto `origin/main` = `7cb65014`, head `bf8c4495`, force-with-lease pushed)
- **Fork branch URL:** https://github.com/lxb007981/verl/tree/ci-fix/ascend-a3-mbridge-clone-collision
- **Compare link:** https://github.com/verl-project/verl/compare/main...lxb007981:ci-fix/ascend-a3-mbridge-clone-collision
- **PR body:** `state/pending-prs/ci-fix_ascend-a3-mbridge-clone-collision.body.md`
- **Target jobs/runs (nightlyCI_grpo_qwen3_5_2b_fsdp2_vllm_ascend, only affected job):**
  - run 33904257189 / job 101125321989 (2026-09-04, first occurrence)
  - run 34050704168 / job 101533680490 (2026-09-06 18:10 UTC, second observable occurrence)
  - run 34150398515 / job 101831291940 (2026-09-07 18:08 UTC, third observable occurrence)
  - run 34261271359 / job 102179531195 (2026-09-08 18:08 UTC, fourth observable occurrence)

## Root cause

#7604 (`3d36367e`, merged 2026-09-04 02:30 UTC, "upgrade Ascend stack to
Megatron 0.18.0") rebuilt the a3 image `verl:latest-vllm-a3-ubuntu`:
`docker/ascend/Dockerfile.ascend_9.1.0_a3` now clones Megatron-Bridge
(v0.5.0) to `/Megatron-Bridge` and `scripts/install_vllm_mcore_npu.sh`
pip-installs it editable. The workflow step "Clone Megatron Bridge" in
`nightlyCI_grpo_qwen3_5_2b_fsdp2_vllm_ascend` (unchanged since #7081)
unconditionally clones into that path. First run on the rebuilt image died
in setup at 18:14 UTC: `fatal: destination path '/Megatron-Bridge' already
exists and is not an empty directory` → exit 128 → job dead before any
training. The job will fail every 18:00 UTC night until fixed.

Cross-evidence: last green run of the job (2026-09-03, run 33788722446 /
job 100759772698) shows the old image (`megatron-core 0.16.2`, no
megatron-bridge) and a successful clone. The 19:11 UTC sibling
(fsdp_turbo, clones `/FSDPTurbo` on the 910b image) ran green 2026-09-04,
so the collision is specific to the a3 image + this step. Pinned mbridge
commit `de93536e` (2026-03-10) differs from the image's baked v0.5.0 tip
`fcbb603`, so dropping the step instead would change the version under
test — the fix keeps the pin.

## Change

One line in `.github/workflows/nightly_ascend.yml` (step "Clone Megatron
Bridge" of nightlyCI_grpo_qwen3_5_2b_fsdp2_vllm_ascend): `rm -rf
/Megatron-Bridge` before the `git clone`. No-op on old images.

## Validation status

Log analysis only — no NPU hardware; the fix was not executed. YAML parse
checked. Verification path: next 18:00 UTC run of the job must pass the
"Clone Megatron Bridge" step and reach training.

## Notes

- No upstream issue/PR tracks this (gh search issues/prs on
  verl-project/verl: empty).
- The commented-out dapo-moonlight-16b job has a copy of the same step; same
  guard needed if ever re-enabled on a baking image (noted in the PR body).

## Status updates

- **2026-09-06:** Signature NOT observable on the 2026-09-05 18:06 UTC night
  (run 33983034076 / job 101351547356, still main 23af6a7a): the job died one
  step EARLIER, at "Install the current repository" — pip build isolation
  could not fetch `setuptools>=61.0` from pypi.org (INFRA egress flake, see
  seen-failures `pip-install-build-deps-setuptools-pypi-unreachable`). The
  clone step never ran, so the collision remains unfixed and latent; it will
  fire again on the next night where pip install succeeds. Branch still
  present on fork (verified via ls-remote, head be8d19aa); main has not moved
  (still 23af6a7a), so no rebase needed. Still awaiting a human-opened PR.

- **2026-09-07:** RECURRED exactly as predicted. Run 34050704168 / job
  101533680490 (2026-09-06 18:10 UTC, still main 23af6a7a): pip install
  succeeded this time (build deps fetched from pypi.org fine at 18:11, verl
  installed 18:22 — the Sep 5 pypi INFRA mask cleared), then the "Clone
  Megatron Bridge" step failed identically: `fatal: destination path
  '/Megatron-Bridge' already exists and is not an empty directory.` → exit
  128 at 18:22:43, job dead before training. Initial pip list confirms the
  baked collision precondition (megatron-bridge 0.5.0+fcbb603 at
  /Megatron-Bridge). Branch re-verified on fork (fetched, head be8d19aa,
  parent 23af6a7a = current origin/main) — no rebase needed, no re-push.
  Second observable occurrence; the job fails EVERY 18:00 UTC night the
  pypi fetch survives. Still awaiting a human-opened PR.

- **2026-09-08:** RECURRED a third time. Run 34150398515 / job 101831291940
  (2026-09-07 18:08 UTC, main d040717b): identical failure — pip install
  succeeded (pip dependency warnings against the baked mbridge 0.5.0+fcbb603
  at 18:28:33), then `git clone --depth 1
  https://github.com/NVIDIA-NeMo/Megatron-Bridge.git /Megatron-Bridge` →
  `fatal: destination path '/Megatron-Bridge' already exists and is not an
  empty directory.` → exit 128 at 18:28:38, job dead in setup. Initial pip
  list again shows the baked megatron-bridge 0.5.0+fcbb603. Main moved
  (23af6a7a → d040717b), so the branch was REBASED onto d040717b (same
  one-line change, new head 586416d5) and force-with-lease pushed to the
  fork. Still awaiting a human-opened PR; the job fails every 18:00 UTC
  night whose pypi fetch survives until this lands.

- **2026-09-09:** RECURRED a fourth time. Run 34261271359 / job 102179531195
  (2026-09-08 18:08 UTC, main 7cb65014): identical failure — pip install
  succeeded at 18:10, then the "Clone Megatron Bridge" step failed with the
  same `fatal: destination path '/Megatron-Bridge' already exists and is not
  an empty directory.` → exit 128 at 18:10:32, job dead in setup (~6 min in).
  None of the 4 commits in d040717b..7cb65014 touch the workflow or the a3
  image (verified: only #7786 revert, #7770/#7722 profiler, #7792 DAPO
  filter). Main moved (d040717b → 7cb65014), so the branch was REBASED onto
  7cb65014 (same one-line change, new head bf8c4495) and force-with-lease
  pushed to the fork. Upstream tracking re-checked (gh search issues + PRs
  "Megatron-Bridge clone" / "Megatron-Bridge already exists"): still empty.
  Still awaiting a human-opened PR; the job fails every 18:00 UTC night
  whose pypi fetch survives until this lands.

- **2026-09-10: RESOLVED UPSTREAM — branch SUPERSEDED, do NOT open a PR.**
  verl PR #7799 (`bf84b14b`, authored by fork owner lxb007981, merged
  2026-09-09 ~03:35 UTC as part of main `1252cc71`) fixed the job by
  REMOVING the "Clone Megatron Bridge" step and the
  `export PYTHONPATH=/Megatron-Bridge/src` line from
  `nightlyCI_grpo_qwen3_5_2b_fsdp2_vllm_ascend` in `.github/workflows/
  nightly_ascend.yml` (upstream chose removal over our rm -rf-before-clone
  guard; equivalent effect — the image bakes mbridge 0.5.0+fcbb603 and the
  pinned de93536e clone was redundant). VERIFIED GREEN on the first night
  after the fix: run 34387178376 (2026-09-09 18:08 UTC, main 1252cc71),
  job `nightlyCI_grpo_qwen3_5_2b_fsdp2_vllm_ascend` = success, alongside
  gspo-30b and all four quick_start jobs. Branch left on the fork untouched
  (head bf8c4495; deletion is outside kit push scope) — recommend the owner
  discard it. PR body retained below for the record only.
