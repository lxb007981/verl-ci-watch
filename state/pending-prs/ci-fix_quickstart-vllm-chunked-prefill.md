# ci-fix/quickstart-vllm-chunked-prefill — LANDED UPSTREAM (no PR awaited)

- Status: **resolved** — script changes merged upstream as verl PR
  [#7558](https://github.com/verl-project/verl/pull/7558)
  (commit `8f8b1221`, merged 2026-08-26 07:58:36 UTC), authored by the fork
  owner from this branch's analysis (its PR body cites CI run 32881976946).
- Prepared: 2026-08-26 (kit run). Branch: `ci-fix/quickstart-vllm-chunked-prefill`
  (head `eeb1813a`, single commit
  `[vllm, ci] fix: drop stale enable_chunked_prefill=False from Ascend NPU scripts`).
- Fork URL: https://github.com/lxb007981/verl/tree/ci-fix/quickstart-vllm-chunked-prefill
- Compare: https://github.com/verl-project/verl/compare/main...lxb007981:ci-fix/quickstart-vllm-chunked-prefill
- Target jobs (2026-08-26, run 32881976946):
  [quick_start_qwen3_0_6b_megatron_vllm_ascend](https://github.com/verl-project/verl/actions/runs/32881976946/job/97913402004),
  [quick_start_qwen3_0_6b_fsdp2_vllm_ascend](https://github.com/verl-project/verl/actions/runs/32881976946/job/97913402009).
- Root cause: PR #7508 made `build_cli_args_from_config` emit `--no-<flag>` for
  `Optional[bool]` vLLM engine args set to False, so long-dormant
  `enable_chunked_prefill=False` lines in 4 Ascend NPU scripts reached vLLM,
  which then rejects `max_num_batched_tokens < max_model_len` at startup.

## What landed vs. what did not

- Landed in #7558: deletion of `enable_chunked_prefill=False` from the 4 scripts
  (`run_dapo_moonlight-16b_megatron_npu.sh`, `run_qwen3_0_6b_fsdp2_vllm_ascend.sh`,
  `run_qwen3_0_6b_megatron_vllm_ascend.sh`, `run_qwen3_vl_8b_Instruct_fsdp2_npu.sh`).
- **Not** included in #7558: the branch's 12-line fail-fast in
  `vLLMHttpServer._validate_configs`
  (`verl/workers/rollout/vllm_rollout/vllm_async_server.py`) that raises an
  actionable `ValueError` when `enable_chunked_prefill=False` is combined with
  `max_num_batched_tokens < max_model_len`, instead of the pydantic
  `ValidationError` from inside vLLM. The fork owner evidently chose to keep
  #7558 minimal. The idea remains unlanded; if the same regression class
  recurs, re-propose it from the branch (still valid against main as of
  2026-08-27).

## Verification (2026-08-27)

Run [33000539883](https://github.com/verl-project/verl/actions/runs/33000539883)
(post-#7558 main `8f8b1221`): all four `quick_start_*_ascend` jobs `success`,
including both vLLM ones. The two predicted follow-on breakages did not occur:
`nightlyCI_grpo_qwen3_vl_8b_Instruct_fsdp2_vllm_ascend` and
`nightlyCI_dapo-moonlight-16b-megatron-vllm_ascend` both ran to 15/15 steps.

No PR remains to be opened for this branch. The branch is kept on the fork for
reference (its `vllm_async_server.py` hunk is the only unlanded content).
