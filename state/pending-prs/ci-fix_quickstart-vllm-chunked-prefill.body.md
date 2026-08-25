> Draft auto-prepared by the nightly Ascend CI triage (log analysis only,
> no NPU validation). @maintainer-friendly: it will be marked ready after
> human review.

### What does this PR do?

Fixes a hard startup crash in the Ascend NPU vLLM nightly jobs introduced
by #7508 (`82e35343`).

#7508 fixed `build_cli_args_from_config` to emit an explicit `False` as
`--no-<flag>` for `Optional[bool]` vLLM engine args. Before it, every
`enable_chunked_prefill=False` was **silently dropped**, so the rollout
engine actually ran with vLLM's default — chunked prefill **enabled**.

Several Ascend NPU scripts set `enable_chunked_prefill=False` while leaving
`rollout.max_model_len` unset, so verl derives `max_model_len` from the
model's `max_position_embeddings` (40960 for Qwen3-0.6B) in
`vLLMHttpServer._validate_configs`. With chunked prefill now *genuinely*
disabled, vLLM's `SchedulerConfig` requires
`max_num_batched_tokens >= max_model_len` and aborts before the first step:

```
pydantic_core._pydantic_core.ValidationError: 1 validation error for SchedulerConfig
  Value error, max_num_batched_tokens (8192) is smaller than max_model_len (40960).
  This effectively limits the maximum sequence length to max_num_batched_tokens
  and makes vLLM reject longer sequences. Please increase max_num_batched_tokens
  or decrease max_model_len.
```

The emitted server args in the failing run are exactly the contradiction:

```
'--max_model_len', '40960',
'--no-enable_chunked_prefill',
'--max_num_batched_tokens', '8192',
```

…followed by vLLM's own `WARNING ... This model does not officially support
disabling chunked prefill. Disabling this manually may cause the engine to
crash or produce incorrect outputs.`

**Two changes:**

1. **Drop the stale `enable_chunked_prefill=False`** from the four Ascend NPU
   scripts listed below, restoring the configuration those jobs were actually
   running — and were green with — before #7508. vLLM explicitly warns
   against disabling chunked prefill for these models, so re-enabling it is
   the safe direction.
2. **Fail fast in `vLLMHttpServer._validate_configs`** when
   `enable_chunked_prefill=False` is combined with
   `max_num_batched_tokens < max_model_len`, so the next contradictory config
   gets an actionable verl-side message naming the knobs instead of the
   pydantic traceback above from inside vLLM.

**Affected scripts** (all in `tests/special_npu/`):

| script | nightly job | status |
|---|---|---|
| `quick_start/run_qwen3_0_6b_fsdp2_vllm_ascend.sh` | `quick_start_qwen3_0_6b_fsdp2_vllm_ascend` | **failing** since 2026-08-25 (run 32881976946, job 97913402009) |
| `quick_start/run_qwen3_0_6b_megatron_vllm_ascend.sh` | `quick_start_qwen3_0_6b_megatron_vllm_ascend` | **failing** since 2026-08-25 (run 32881976946, job 97913402004) |
| `run_qwen3_vl_8b_Instruct_fsdp2_npu.sh` | `nightlyCI_grpo_qwen3_vl_8b_Instruct_fsdp2_vllm_ascend` | **predicted** — `enable_chunked_prefill=False`, `max_num_batched_tokens` left at the 8192 default, no `max_model_len` |
| `nightly_ci_ascend/run_dapo_moonlight-16b_megatron_npu.sh` | `nightlyCI_dapo-moonlight-16b-megatron-vllm_ascend` | **predicted** — `enable_chunked_prefill=False`, `max_num_batched_tokens=3072` (1024 prompt + 2048 response), no `max_model_len` |

The last two have not failed yet only because their `0 17 * * *` schedule did
not run against a post-#7508 `main` (run 32876498657 was cancelled). The
maintainer should feel free to drop those two hunks if the prediction is
unwelcome — the first two hunks are the confirmed fix.

**Cross-check that isolates the cause:** on run 32881976946 the two *sglang*
quick_start jobs on the same runner and image were **green**, and
`nightlyCI_gspo-qwen3-8b-fsdp2-vllm_ascend` (vLLM, but
`enable_chunked_prefill=True` + explicit `max_num_batched_tokens`) completed
15/15 steps on the same night. Only the jobs that set
`enable_chunked_prefill=False` without a matching token budget broke.

### Checklist Before Starting

- [x] Search for similar PRs:
  - https://github.com/verl-project/verl/pulls?q=is%3Apr+max_num_batched_tokens+max_model_len
    → only #259 (merged, ancient "disable chunked-prefill by default") and
    #5856 (merged, unrelated trtllm CI speedup).
  - https://github.com/verl-project/verl/issues?q=max_num_batched_tokens+is%3Aissue+is%3Aopen
    → no open issue.
  - https://github.com/verl-project/verl/pulls?q=is%3Apr+is%3Aopen+enable_chunked_prefill
    → no open PR.
- [x] Format the PR title as `[{modules}] {type}: {description}`.

### Test

**No NPU/GPU hardware was available to the author — validation was log
analysis only.** Specifically:

- Root-caused from the archived job logs of run
  [32881976946](https://github.com/verl-project/verl/actions/runs/32881976946)
  (jobs [97913402004](https://github.com/verl-project/verl/actions/runs/32881976946/job/97913402004)
  and [97913402009](https://github.com/verl-project/verl/actions/runs/32881976946/job/97913402009)).
- `python -m py_compile verl/workers/rollout/vllm_rollout/vllm_async_server.py` — clean.
- `bash -n` on all four touched shell scripts — clean.
- Confirmed no unit test constructs a `vLLMHttpServer` with
  `enable_chunked_prefill=False`
  (`tests/workers/rollout/test_vllm_cli_args_on_cpu.py` uses `True`), so the
  new guard should not affect the CPU suite. `pytest` is not installed in the
  authoring environment, so this was **not** executed.

**The nightly jobs that should verify this** (a human should confirm before
marking ready, or request a CI run):

```
quick_start_qwen3_0_6b_fsdp2_vllm_ascend        # 0 18 * * * schedule
quick_start_qwen3_0_6b_megatron_vllm_ascend     # 0 18 * * * schedule
```

Both should reach `Training Progress: 1/1` instead of dying in
`vLLMHttpServer.launch_server`. Note the two predicted-affected jobs
(`0 17 * * *` schedule) will also flip from "baseline mismatch" to a real
run if this lands, and their throughput/memory baselines may need
re-recording since chunked prefill will now be on for them.

### API and Usage Example

No API change. The new validation raises instead of crashing deeper down:

```
ValueError: rollout.enable_chunked_prefill=False requires
rollout.max_num_batched_tokens (8192) to be at least rollout.max_model_len
(40960). Raise max_num_batched_tokens, lower max_model_len, or leave
enable_chunked_prefill at its default (True).
```

### Design & Code Changes

- `verl/workers/rollout/vllm_rollout/vllm_async_server.py` — extend the
  existing `_validate_configs()` (which already validates the
  `max_model_len` ↔ `max_position_embeddings` relationship) with the
  chunked-prefill/token-budget invariant. No override of
  `_validate_configs` exists elsewhere in the tree.
- Four `tests/special_npu/**.sh` — one-line removal of
  `actor_rollout_ref.rollout.enable_chunked_prefill=False`, letting the
  config fall back to the documented default `True`
  (`verl/trainer/config/rollout/rollout.yaml:87`).

**Worth a follow-up someone may want to own** (deliberately *not* done here):
`rollout.max_num_batched_tokens` defaults to 8192 while verl auto-derives
`max_model_len` from the model's native context, which is 4–32× larger for
most Qwen models. Every user who copies `enable_chunked_prefill=False` from
these scripts will hit this. A future change could default `max_model_len`
to `prompt_length + response_length` for RL rollouts instead of
`max_position_embeddings`.

### Checklist Before Submitting

- [ ] Read the [Contribute Guide](https://github.com/verl-project/verl/blob/main/CONTRIBUTING.md).
- [ ] Apply pre-commit checks: `pre-commit install && pre-commit run --all-files --show-diff-on-failure --color=always`
- [ ] Add / Update [the documentation](https://github.com/verl-project/verl/tree/main/docs).
- [x] Add unit or end-to-end test(s) — the touched code paths are only
      exercised on NPU hardware; the change is covered by the four nightly
      jobs named above. A CPU unit test for the new `_validate_configs`
      branch would be a reasonable addition if a maintainer wants one.
- [ ] Once your PR is ready for CI, send a message in the [the `ci-request` channel](https://verl-project.slack.com/archives/C091TCESWB1).
- [ ] If your PR is related to the `recipe` submodule, please also update the reference to the submodule commit.

---

**AI assistance disclosure**: this draft was prepared automatically by the
nightly Ascend CI triage job from archived job logs, with no access to NPU
hardware. It is opened as a **draft** and will be marked ready only after a
human has reviewed and understood every changed line.
