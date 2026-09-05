# ci-fix/ascend-a3-mbridge-clone-collision — audit record

- **Date pushed:** 2026-09-05 (analyzing nightly window of 2026-09-04 UTC evening)
- **PR title (for the human to reuse):** `[ci] fix: clear pre-baked /Megatron-Bridge before cloning pinned commit`
- **Branch:** `ci-fix/ascend-a3-mbridge-clone-collision` (from `origin/main` = `23af6a7a`, head `be8d19aa`)
- **Fork branch URL:** https://github.com/lxb007981/verl/tree/ci-fix/ascend-a3-mbridge-clone-collision
- **Compare link:** https://github.com/verl-project/verl/compare/main...lxb007981:ci-fix/ascend-a3-mbridge-clone-collision
- **PR body:** `state/pending-prs/ci-fix_ascend-a3-mbridge-clone-collision.body.md`
- **Target jobs/runs:**
  - nightlyCI_grpo_qwen3_5_2b_fsdp2_vllm_ascend — run 33904257189, job 101125321989 (VERL_BUG, only affected job)

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
