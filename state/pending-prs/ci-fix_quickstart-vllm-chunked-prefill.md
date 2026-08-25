# Pending draft PR — ci-fix/quickstart-vllm-chunked-prefill

> **STATUS: NOT OPENED — blocked by PAT permissions** (identical block to
> `ci-fix_gspo-qwen3-8b-8npu.md`, 2026-08-20). The branch **is pushed to the
> fork** and the PR body is final; only the `gh pr create` call is denied.
> Ready-to-open compare link for a human:
> https://github.com/verl-project/verl/compare/main...lxb007981:verl:ci-fix/quickstart-vllm-chunked-prefill?expand=1

- **Date**: 2026-08-26
- **PR title**: `[vllm, ci] fix: drop stale enable_chunked_prefill=False from Ascend NPU scripts`
- **PR URL**: not opened — 403 "Resource not accessible by personal access token"
  on both `gh pr create --draft` (GraphQL) and `POST /repos/verl-project/verl/pulls`
  (REST). `git push` to the fork **succeeded**.
- **Branch**: `ci-fix/quickstart-vllm-chunked-prefill` on fork `lxb007981/verl`
  (head `eeb1813a`, one commit on top of `origin/main` = `559c337a`).
  Files changed: 5 files, +12 / −4.
- **PR body**: kept verbatim at
  `state/pending-prs/ci-fix_quickstart-vllm-chunked-prefill.body.md`
  (follows `.github/PULL_REQUEST_TEMPLATE.md`; includes the triage note block,
  duplicate-check query links, and an honest "no NPU, log analysis only" Test section).

## Target jobs / runs

Confirmed failing (the ones that motivated the fix):

- `quick_start_qwen3_0_6b_megatron_vllm_ascend` — run `32881976946`, job `97913402004`
- `quick_start_qwen3_0_6b_fsdp2_vllm_ascend` — run `32881976946`, job `97913402009`

Predicted to fail at the next `0 17 * * *` run (fixed pre-emptively in the same
commit; hunks are independently droppable):

- `nightlyCI_grpo_qwen3_vl_8b_Instruct_fsdp2_vllm_ascend` — script
  `tests/special_npu/run_qwen3_vl_8b_Instruct_fsdp2_npu.sh`
- `nightlyCI_dapo-moonlight-16b-megatron-vllm_ascend` — script
  `tests/special_npu/nightly_ci_ascend/run_dapo_moonlight-16b_megatron_npu.sh`

## Root cause

PR #7508 (commit `82e35343`, merged 2026-08-25 03:58 UTC) made
`build_cli_args_from_config` emit `--no-<flag>` for `Optional[bool]` vLLM engine
args set to `False`. Before it, every `enable_chunked_prefill=False` was silently
**dropped**, so the rollout engine ran with chunked prefill **enabled** (vLLM's
default). verl's Ascend NPU scripts had carried that dead flag since #6900.

After #7508 the flag reaches vLLM for real. verl auto-derives
`rollout.max_model_len` from the model's `max_position_embeddings`
(`vllm_async_server.py:995-996`) = 40960 for Qwen3-0.6B, while
`rollout.max_num_batched_tokens` stays at its 8192 default. With chunked prefill
disabled, vLLM's `SchedulerConfig` requires
`max_num_batched_tokens >= max_model_len` and aborts in
`vLLMHttpServer.launch_server` → `create_engine_config`, before step 1:

```
pydantic_core._pydantic_core.ValidationError: 1 validation error for SchedulerConfig
  Value error, max_num_batched_tokens (8192) is smaller than max_model_len (40960). ...
```

Emitted args in the failing run prove it:
`'--max_model_len','40960'`, `'--no-enable_chunked_prefill'`,
`'--max_num_batched_tokens','8192'`, immediately followed by vLLM's
`WARNING ... This model does not officially support disabling chunked prefill.`

Isolating evidence: on the same run/runner/image, the two **sglang** quick_start
jobs were green, and `nightlyCI_gspo-qwen3-8b-fsdp2-vllm_ascend` (vLLM, but
`enable_chunked_prefill=True` + explicit `max_num_batched_tokens`) completed
15/15. Only jobs setting `enable_chunked_prefill=False` without a matching token
budget broke. Timeline matches exactly: all four quick_start jobs green on
Aug 24 (`fc6ca747`, pre-#7508); only the two vLLM ones broke on
Aug 25 (`559c337a`, post-#7508).

## Fix

1. Remove `actor_rollout_ref.rollout.enable_chunked_prefill=False` from the four
   Ascend NPU scripts, restoring the config those jobs were actually running and
   were green with before #7508.
2. Add a fail-fast branch to `vLLMHttpServer._validate_configs` that raises an
   actionable `ValueError` when `enable_chunked_prefill=False` is combined with
   `max_num_batched_tokens < max_model_len`.

## Verification performed (no NPU available)

- `python -m py_compile` on `vllm_async_server.py` — clean.
- `bash -n` on all four shell scripts — clean.
- `rg` confirmed no other `_validate_configs` override and no unit test
  constructing a server with `enable_chunked_prefill=False`.
- `pytest` not installed in the authoring environment — **no tests were run**.

## Next run (tomorrow) should

1. Re-open attempt if the PAT has been fixed:
   `gh pr create --repo verl-project/verl --draft --head "lxb007981:ci-fix/quickstart-vllm-chunked-prefill" --title "[vllm, ci] fix: drop stale enable_chunked_prefill=False from Ascend NPU scripts" --body-file state/pending-prs/ci-fix_quickstart-vllm-chunked-prefill.body.md`
   (branch already on the fork; if upstream `main` moved, `git fetch lxb
   ci-fix/quickstart-vllm-chunked-prefill`, rebase onto `origin/main`, push
   `--force-with-lease`). Do **not** open a second PR if one already exists.
2. Check whether the two predicted jobs (`0 17 * * *` schedule:
   grpo_qwen3_vl_8b and dapo-moonlight-16b) hit the same ValidationError — if
   they do, that confirms the prediction and strengthens the case for the two
   pre-emptive hunks. If they instead ran green on their own, those two hunks
   can be dropped from the PR before it is marked ready.
3. If a human has opened/merged a different fix upstream, mark this record
   SUPERSEDED like `ci-fix_gspo-qwen3-8b-8npu.md` and do not open it.
