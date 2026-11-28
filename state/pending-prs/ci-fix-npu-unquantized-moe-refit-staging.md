# Pending fix branch — ci-fix/npu-unquantized-moe-refit-staging

- **Branch:** `ci-fix/npu-unquantized-moe-refit-staging` (one commit, `6cb46cdb`, on `origin/main` `22a8903a`)
- **Fork branch URL:** https://github.com/lxb007981/verl/tree/ci-fix/npu-unquantized-moe-refit-staging
- **Compare link:** https://github.com/verl-project/verl/compare/main...lxb007981:ci-fix/npu-unquantized-moe-refit-staging
- **PR body to reuse:** `state/pending-prs/ci-fix-npu-unquantized-moe-refit-staging.body.md` (no PR opened)
- **PR title:** `[vllm, rollout] fix: restore unquantized MoE staging for the NPU vLLM refit`
- **Prepared:** 2026-11-27 (commit `47672a6f` on `f4fb2b63`); **rebased 2026-11-28** onto `22a8903a`

## Target job / run

- Job: `nightlyCI_gspo-qwen3-30b-megatron-vllm_ascend` (18:05 UTC wave, image `verl:latest-vllm-a3-ubuntu`)
- Latest failing run: 46046744980, job 140667789320 (2026-11-27 18:05 UTC, `main` `f4fb2b63`, pod 10.0.5.244,
  driver 26.0.rc3) — https://github.com/verl-project/verl/actions/runs/46046744980/job/140667789320
- Previous failing run: 45873069877, job 140093159472 (2026-11-26 18:05 UTC, `main` `8612d029`, pod 10.0.11.118,
  driver 26.0.rc3) — https://github.com/verl-project/verl/actions/runs/45873069877/job/140093159472
- Last passing run: 45671460966, job 139407565297 (2026-11-25 18:05 UTC, `main` `d577845e`) —
  https://github.com/verl-project/verl/actions/runs/45671460966/job/139407565297

Note: GitHub records the failing job as `cancelled` (180-minute timeout), so it is absent from the failed-job list that
the watch collector builds. Check the job's conclusion directly each night until the fix lands.

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

Ruled out on 2026-11-27: launch command, recipe submodule pointer, resolved trainer config (all identical between the
passing and the failing night); vLLM, torch, torch-npu, Megatron stack (identical); vllm-ascend (moved
by a docs commit and a sparse-attention kernel rename).

Still failing on 2026-11-28 (waves of Nov 27), second night in a row: same terminal error on `main` `f4fb2b63`, 13 min
into the job, then idle until the 21:05:27 UTC timeout. `main` has gained no change to the refit path since.

### Premises re-checked on 2026-11-28 against the pinned upstream sources

Read with the GitHub API, not executed:

- vllm-ascend `a2ed69c2b3`, `vllm_ascend/ops/fused_moe/routed_experts.py`: line 52
  `class AscendUnquantizedFusedMoEMethod(UnquantizedFusedMoEMethod)` (the `isinstance` gate the staging relies on);
  lines 107-111 transpose `w13` / `w2` and install them through vllm-ascend's own imported `replace_parameter`
  (line 30), which the fold's patch does not intercept, so they are folded on the context manager's exit.
- vLLM `v0.30.0`, `fused_moe/unquantized_fused_moe_method.py`: imports `replace_parameter` (lines 30-32), which the
  staging requires.
- vLLM `v0.30.0`, `model_loader/reload/__init__.py`: exports `initialize_layerwise_reload`,
  `finalize_layerwise_processing`, `finalize_layerwise_reload`, `record_metadata_for_reloading`,
  `set_torchao_reload_attrs`, `support_quantized_model_reload_from_hp_weights`. No `start_reload` / `finish_reload`.
- vLLM `v0.30.0`, `model_loader/reload/layerwise.py`: `LAYERWISE_INFO` with `restore_metadata` (lines 48-63);
  `model_loader/utils.py:60` calls `record_metadata_for_reloading(model)` unconditionally at model init, before any
  weight is loaded, so the checkpoint shapes are on record at refit time.
- vLLM `v0.30.0`, `fused_moe/routed_experts.py`: `_load_w13` at line 459 and `expert_data.copy_(loaded_weight)` at
  508, the lines in the traceback, so the image's file matches the tag here. Shape arithmetic, per rank with TP 8:
  checkpoint layout `[128, 192, 2048]` (1536 / 8); in the transposed layout `[128, 2048, 192]` the loader takes
  `shard_size = 2048 // 2 = 1024`, then narrows to the loaded slice's 96 rows: `[96, 192]` against a `[96, 2048]` load.

Caveat: the image reports `vllm 0.30.0+empty` from an editable `/vllm`, so "the tag" is an inference from the version
string and the matching line numbers.

## Fix

Restore `verl/utils/vllm/vllm_unquant_utils.py` from `95ede340~1` (three helpers moved in from the
deleted `vllm_fp8_utils.py`) and stage / fold again on NPU for unquantized models in
`update_weights_from_ipc`. Tests: the deleted `tests/utils/test_vllm_unquant_utils_on_cpu.py` restored
(+1 vllm-ascend-style case) and one parametrized wiring test in the rollout CPU harness.

## Validation

- CPU only, locally on 2026-11-27 (Python 3.14, torch 2.15.0+cpu, vLLM stubbed): 11 passed in the staging test file;
  21 passed in the rollout harness on the branch, the new unquantized case RED on `main` `f4fb2b63`.
  `ruff` 0.12.2 check/format, `check_license`, `check_device_api_usage`, `validate_structure`: clean.
- 2026-11-28, re-run on the rebased commit `6cb46cdb` in a fresh CPU venv (Python 3.14.4, torch 2.15.0+cpu, pytest 9.2.0,
  ruff 0.12.2, plus the numpy, ray, tensordict, omegaconf and transformers that `verl/__init__.py` imports; vLLM stubbed by
  the tests). Same results as the day before:
  - `pytest tests/utils/test_vllm_unquant_utils_on_cpu.py`: 11 passed.
  - `pytest tests/workers/rollout/test_vllm_weight_update_utils_on_cpu.py`: 21 passed.
  - The branch's test file overlaid on unmodified `main` `22a8903a`: the new
    `test_npu_unquantized_moe_refit_is_bracketed_by_moe_staging[False]` fails with `['bucket', 'bucket', 'postprocess']`
    (no staging, no fold); `[True]` passes.
  - `ruff check` and `ruff format --check` on the four files, and the repo's `check_license`, `check_docstrings`,
    `check_device_api_usage`, `validate_structure`: clean.
  Also on 2026-11-28: `git range-diff` reports the commit `=` (identical patch), and the only refit entry point in `verl/`
  is still `update_weights_from_ipc`. Not run: the full pre-commit suite, CI's `uv` environment, and anything on NPU.
- **Not run on NPU.** The next 18:05 UTC nightly of `nightlyCI_gspo-qwen3-30b-megatron-vllm_ascend` is the first real
  verification; it is not in the failed-job list unless it fails fast, so check that the job completes in ~30 minutes.

## Related upstream

- #8780 — the regression (merged).
- #8858 — open on 2026-11-28 (head `6781e7fd`, last updated 2026-11-26), post-merge fixes for #8780 by the same
  author; touches the same NPU branch but does not restore the unquantized-MoE staging. Likely textual conflict in the
  `is_npu_available` loop if it lands first.
- No PR exists from this branch (checked 2026-11-28 with `gh pr list --head lxb007981:ci-fix/npu-unquantized-moe-refit-staging --state all`).

## Follow-ups for the human (not addressed)

- The NPU branch for quantized models lost its staging in #8780 as well; unexercised by any nightly job.
- After the crash the trainer never surfaced the vLLM worker error and the job idled until the timeout.
