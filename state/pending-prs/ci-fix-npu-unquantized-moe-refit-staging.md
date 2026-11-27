# Pending fix branch — ci-fix/npu-unquantized-moe-refit-staging

- **Branch:** `ci-fix/npu-unquantized-moe-refit-staging` (one commit, `47672a6f`, on `origin/main` `f4fb2b63`)
- **Fork branch URL:** https://github.com/lxb007981/verl/tree/ci-fix/npu-unquantized-moe-refit-staging
- **Compare link:** https://github.com/verl-project/verl/compare/main...lxb007981:ci-fix/npu-unquantized-moe-refit-staging
- **PR body to reuse:** `state/pending-prs/ci-fix-npu-unquantized-moe-refit-staging.body.md` (no PR opened)
- **PR title:** `[vllm, rollout] fix: restore unquantized MoE staging for the NPU vLLM refit`
- **Prepared:** 2026-11-27

## Target job / run

- Job: `nightlyCI_gspo-qwen3-30b-megatron-vllm_ascend` (18:05 UTC wave, image `verl:latest-vllm-a3-ubuntu`)
- Failing run: 45873069877, job 140093159472 (2026-11-26 18:05 UTC, `main` `8612d029`, pod 10.0.11.118, driver 26.0.rc3) — https://github.com/verl-project/verl/actions/runs/45873069877/job/140093159472
- Last passing run: 45671460966, job 139407565297 (2026-11-25 18:05 UTC, `main` `d577845e`) — https://github.com/verl-project/verl/actions/runs/45671460966/job/139407565297

Note: GitHub records the failing job as `cancelled` (180-minute timeout), so it is absent from the failed-job list that the watch collector builds.

## Signature

`nightlyCI_gspo-qwen3-30b-megatron-vllm_ascend::moe-refit-shape-mismatch-ez1007-after-vllm-reload-refactor`

## Root cause

`VERL_BUG`, a regression from #8780 (`95ede340`, merged 2026-11-26 01:48 UTC). vllm-ascend's
`AscendUnquantizedFusedMoEMethod.process_weights_after_loading` transposes `w13_weight` / `w2_weight`
to `[E, H, 2I]` / `[E, I, H]`. #8780 deleted the staging (`stage_unquantized_moe_params` /
`fold_unquantized_moe_params`) that viewed them back to checkpoint layout for a refit, and replaced it
with vLLM's `start_reload` / `finish_reload` on non-NPU devices only. The Ascend image ships vLLM
0.30.0, which has no `start_reload`, so on NPU the first bucket's expert load hits the transposed
parameter: `[96, 2048]` into `[96, 192]`, `EZ1007`, in `routed_experts.py:508 _load_w13`.

Ruled out: launch command, recipe submodule pointer, resolved trainer config (all identical between the
passing and the failing night); vLLM, torch, torch-npu, Megatron stack (identical); vllm-ascend (moved
by a docs commit and a sparse-attention kernel rename).

## Fix

Restore `verl/utils/vllm/vllm_unquant_utils.py` from `95ede340~1` (three helpers moved in from the
deleted `vllm_fp8_utils.py`) and stage / fold again on NPU for unquantized models in
`update_weights_from_ipc`. Tests: the deleted `tests/utils/test_vllm_unquant_utils_on_cpu.py` restored
(+1 vllm-ascend-style case) and one parametrized wiring test in the rollout CPU harness.

## Validation

- CPU only, locally (Python 3.14, torch 2.15.0+cpu, vLLM stubbed): 11 passed in the staging test file;
  21 passed in the rollout harness on the branch, the new unquantized case RED on `main` `f4fb2b63`.
- `ruff` 0.12.2 check/format, `check_license`, `check_device_api_usage`, `validate_structure`: clean.
- **Not run on NPU.** The 2026-11-27 nightly (`nightlyCI_gspo-qwen3-30b-megatron-vllm_ascend`) is the
  first real verification; it is not in the failed-job list unless it fails fast, so check that the job
  completes in ~30 minutes.

## Related upstream

- #8780 — the regression (merged).
- #8858 — open, post-merge fixes for #8780 by the same author; touches the same NPU branch but does not
  restore the unquantized-MoE staging. Likely textual conflict in the `is_npu_available` loop if it lands first.

## Follow-ups for the human (not addressed)

- The NPU branch for quantized models lost its staging in #8780 as well; unexercised by any nightly job.
- After the crash the trainer never surfaced the vLLM worker error and the job idled until the timeout.
