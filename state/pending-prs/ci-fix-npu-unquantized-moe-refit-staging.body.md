> Branch auto-prepared by the nightly Ascend CI triage (log analysis only,
> no NPU validation). PR to be opened by a human after review.

### What does this PR do?

Fixes an NPU regression from #8780 (`95ede340`): the bucketed vLLM refit of an **unquantized MoE** model crashes at its first weight sync on Ascend.

`nightlyCI_gspo-qwen3-30b-megatron-vllm_ascend` (Qwen3-30B-A3B, Megatron TP=2/EP=8 to vLLM TP=8) passed on Nov 24 and Nov 25 ([139407565297](https://github.com/verl-project/verl/actions/runs/45671460966/job/139407565297)) and has died at its first weight sync every night since: Nov 26, the first nightly that carried #8780 ([140093159472](https://github.com/verl-project/verl/actions/runs/45873069877/job/140093159472)), and Nov 27 on `f4fb2b63` ([140667789320](https://github.com/verl-project/verl/actions/runs/46046744980/job/140667789320)). The Nov 26 traceback, abbreviated:

```
File "/__w/verl/verl/verl/workers/rollout/vllm_rollout/utils.py", line 488, in _update_weights
    model.load_weights(model_updates)
File "/vllm/vllm/model_executor/layers/fused_moe/routed_experts.py", line 508, in _load_w13
    expert_data.copy_(loaded_weight)
RuntimeError: copy_d2d_baseformat_opapi:../torch_npu/csrc/aten/ops/op_api/CopyKernelOpApi.cpp:126 NPU function error: call aclnnInplaceCopy failed, error code is 161002
[PID: 36185] Invalid_Argument_Tensor_Input_Shape(EZ1007): Shape [96, 2048] of the tensor of operator aclnnInplaceCopy_111624 has incorrect dimension 2048.
    Reason: The tensor whose shape is [96, 2048] and the tensor whose shape is [96, 192] do not meet the broadcast condition.
```

On Nov 27 the terminal error was identical; only verl's line numbers moved with `f4fb2b63`: `update_weights_from_ipc` (`utils.py:431`) → `BucketedWeightReceiver.receive_weights` (`bucketed_weight_transfer.py:325`) → `_update_weights` (`utils.py:496`) → the same `routed_experts.py:508`.

The job is easy to miss: the crash happens 7–13 minutes in, but the trainer never surfaces it, so GitHub records the job as `cancelled` at the 180-minute timeout.

**Why.** vllm-ascend's `AscendUnquantizedFusedMoEMethod.process_weights_after_loading` transposes `w13_weight` / `w2_weight` to `[E, H, 2I]` / `[E, I, H]`. A refit's checkpoint-layout loads only fit those parameters if something views them back to the checkpoint layout first. Before #8780, `stage_unquantized_moe_params` / `fold_unquantized_moe_params` did that on every device. #8780 replaced them with vLLM's `start_reload` / `finish_reload` on non-NPU devices and left NPU on the bare `process_weights_after_loading` path. The Ascend image ships vLLM 0.30.0, which has no `start_reload`, so on NPU nothing prepares the expert weights any more. vLLM 0.30.0 then slices the `[768, 2048]` expert load to this rank's `[96, 2048]` (768 / TP 8) and narrows the transposed `[2048, 192]` slot as if it were `[2I, H]`, down to `[96, 192]` — the two shapes in the error.

**What.** Restore `verl/utils/vllm/vllm_unquant_utils.py` as it was at `95ede340~1` and call it again on NPU for unquantized models: stage the checkpoint layout before the bucket stream, fold the kernel layout back around the post-load processing. The three helpers it imported move in from the deleted `vllm_fp8_utils.py`, bodies unchanged. The non-NPU, LoRA and quantized paths are untouched.

**Why this is not a duplicate.** #8858 (post-merge fixes for #8780, by its author) edits the same NPU branch, but only restores `disable_mtp_completeness_check` and adds a KV-scale reset for quantized models; nothing in it stages unquantized MoE weights. If #8858 lands first, the conflict is the loop inside the `is_npu_available` branch of `update_weights_from_ipc`.

**Alternative worth considering.** Move NPU onto vLLM's reload lifecycle once the Ascend image carries vLLM >= 0.34, then delete this module with it. vLLM 0.30.0 does ship the older `initialize_layerwise_reload` / `finalize_layerwise_processing`; I did not use them because I cannot check on NPU whether they undo vllm-ascend's transpose.

### Checklist Before Starting

- [x] Search for similar PRs: https://github.com/verl-project/verl/pulls?q=is%3Apr+8780 , https://github.com/verl-project/verl/pulls?q=is%3Apr+vllm+reload+NPU , https://github.com/verl-project/verl/pulls?q=is%3Apr+stage_unquantized_moe_params
- [x] Format the PR title as `[{modules}] {type}: {description}` (This will be checked by the CI)

### Test

**No NPU validation.** The fix was derived from job logs and from reading verl, vLLM 0.30.0 and vllm-ascend source; it has not been run on Ascend hardware. The nightly job that should verify it is `nightlyCI_gspo-qwen3-30b-megatron-vllm_ascend` (18:05 UTC wave, image `verl:latest-vllm-a3-ubuntu`). It will not show up in a failed-job list until it fails fast: on the next run please check that it completes in about 30 minutes rather than sitting until the timeout.

Evidence that the regression is #8780, from the logs of the passing and the failing run:

- Same launch command, same recipe submodule, identical resolved trainer config (356 lines diffed; 4 timestamp-only differences).
- Same vLLM 0.30.0, torch 2.10.0, torch-npu 2.10.0.post7, megatron-core 0.18.2. `vllm-ascend` moved by two commits: `790a881706` (a docs file) and `a2ed69c2b3` (a sparse-attention kernel rename).
- `95ede340` is the only commit on the refit path in `d577845e..8612d029`.

What the fix relies on in the Ascend image's stack, read from the sources at the versions the job log reports (not executed):

- vllm-ascend `a2ed69c2b3`, `vllm_ascend/ops/fused_moe/routed_experts.py`: `AscendUnquantizedFusedMoEMethod` subclasses vLLM's `UnquantizedFusedMoEMethod` (line 52), which is the gate the staging selects layers by; lines 107–111 transpose `w13` / `w2` and install them through vllm-ascend's own imported `replace_parameter`, which the fold's patch does not intercept, so the context manager folds them on exit.
- vLLM `v0.30.0`: `unquantized_fused_moe_method.py` imports `replace_parameter`; `model_loader/utils.py:60` calls `record_metadata_for_reloading(model)` unconditionally at model init, so the checkpoint shapes the staging reads are on record at refit time; `fused_moe/routed_experts.py` has `_load_w13` at line 459 and the `copy_` at 508, the lines in the traceback. The image reports `vllm 0.30.0+empty` from an editable install, so "the `v0.30.0` tag" is inferred from the version string and these line numbers.

Commands run locally, CPU only (Python 3.14, torch 2.15.0+cpu, pytest 9.2.0, ruff 0.12.2, plus the numpy, ray, tensordict, omegaconf and transformers that `verl/__init__.py` imports; vLLM stubbed by the tests):

- `pytest tests/utils/test_vllm_unquant_utils_on_cpu.py`: **11 passed**. Ten are the test file deleted in #8780, restored. One is new and models vllm-ascend (transposed layout installed through an unpatched `replace_parameter`): a checkpoint-layout load raises before staging and is folded back into the live storage after.
- `pytest tests/workers/rollout/test_vllm_weight_update_utils_on_cpu.py`: **21 passed** on this branch. The new `test_npu_unquantized_moe_refit_is_bracketed_by_moe_staging[False]` fails on unmodified `main` (`22a8903a`) with `['bucket', 'bucket', 'postprocess']`, i.e. no staging and no fold; `[True]` (quantized) passes on both.
- `ruff check` and `ruff format --check` (0.12.2, the pre-commit pin) on the four changed files, plus the repo's `check_license`, `check_docstrings`, `check_device_api_usage`, `validate_structure` scripts: clean.

The CPU tests exercise the control flow and the staging logic against stubs. They do not show that the fold yields correct weights on NPU; only the nightly does.

These commands were run twice with the same results: on 2026-11-27 on commit `47672a6f` (`f4fb2b63` + this change) and on 2026-11-28 on the rebased commit `6cb46cdb` (`22a8903a` + this change). `git range-diff` reports the two commits as identical. Not run: the full pre-commit suite, and anything on NPU.

### API and Usage Example

No API or config change.

### Design & Code Changes

- `verl/utils/vllm/vllm_unquant_utils.py`: restored from `95ede340~1`. `_iter_transferable_param_attrs`, `_copy_param_subclass_attrs` and `_fold_into_live_param` move in from the deleted `vllm_fp8_utils.py`; the docstring gains a paragraph on vllm-ascend and one error message no longer says "FP8".
- `verl/workers/rollout/vllm_rollout/utils.py`: on NPU, for an unquantized model, stage before the bucket stream and wrap the post-load loop in the fold. The import is function-local, as the existing `rank_local_bake` import is, so the CPU harness that stubs `verl.utils.vllm` keeps loading this module.
- Tests: the deleted `tests/utils/test_vllm_unquant_utils_on_cpu.py` restored with one added case, and one parametrized test in the existing rollout harness.

Seen while tracing this, not addressed here:

- The NPU branch for **quantized** models lost its staging in #8780 too (`prepare_quanted_weights_for_loading`). No nightly job exercised it, so I did not touch it.
- After the crash the job held a 16-NPU runner for 2 h 52 min until the timeout, because the vLLM worker's error never reached the trainer.

AI assistance: this branch was prepared by an automated agent (Claude) from nightly CI logs. No human has reviewed or run it yet.

### Checklist Before Submitting

> [!IMPORTANT]
> Please check all the following items before requesting a review, otherwise the reviewer might deprioritize this PR for review.

- [ ] Read the [Contribute Guide](https://github.com/verl-project/verl/blob/main/CONTRIBUTING.md).
- [ ] Apply [pre-commit checks](https://github.com/verl-project/verl/blob/main/CONTRIBUTING.md#code-linting-and-formatting): `pre-commit install && pre-commit run --all-files --show-diff-on-failure --color=always`
- [ ] Add / Update [the documentation](https://github.com/verl-project/verl/tree/main/docs).
- [ ] Add unit or end-to-end test(s) to [the CI workflow](https://github.com/verl-project/verl/tree/main/.github/workflows) to cover all the code. If not feasible, explain why: ...
- [ ] Once your PR is ready for CI, send a message in [the `ci-request` channel](https://verl-project.slack.com/archives/C091TCESWB1) in [the `verl` Slack workspace](https://join.slack.com/t/verl-project/shared_invite/zt-3855yhg8g-CTkqXu~hKojPCmo7k_yXTQ). (If not accessible, please try the [Feishu group (飞书群)](https://applink.larkoffice.com/client/chat/chatter/add_by_link?link_token=772jd4f1-cd91-441e-a820-498c6614126a).)
- [ ] If your PR is related to the `recipe` submodule, please also update the reference to the submodule commit via `git submodule update --remote` or `cd recipe && git pull origin main`.
