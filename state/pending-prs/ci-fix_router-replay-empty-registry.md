# ci-fix/router-replay-empty-registry — audit record

- **Date pushed:** 2026-09-08 (analyzing nightly window of 2026-09-07 UTC evening)
- **PR title (for the human to reuse):** `[megatron] fix: treat empty router replay registry as disabled replay`
- **Branch:** `ci-fix/router-replay-empty-registry` (from `origin/main` = `d040717b`, head `a56f3ec7`)
- **Fork branch URL:** https://github.com/lxb007981/verl/tree/ci-fix/router-replay-empty-registry
- **Compare link:** https://github.com/verl-project/verl/compare/main...lxb007981:ci-fix/router-replay-empty-registry
- **PR body:** `state/pending-prs/ci-fix_router-replay-empty-registry.body.md`
- **Target jobs/runs (all four Megatron-engine nightly Ascend jobs):**
  - quick_start_qwen3_0_6b_megatron_vllm_ascend — run 34150398515 / job 101831291862 (2026-09-07 18:08 UTC)
  - quick_start_qwen3_0_6b_megatron_sglang_ascend — run 34150398515 / job 101831291947
  - nightlyCI_gspo-qwen3-30b-megatron-vllm_ascend — run 34150398515 / job 101831291888
  - nightlyCI_grpo-qwen3-30b-megatron-sglang_ascend — run 34146606227 / job 101819898833 (17:12 UTC)

## Root cause

#7106 (`c80729fb`, merged 2026-09-07 ~11:30 UTC, "preserve R2 router replay
for THD-packed batches") made `RouterReplayHelper.get_micro_batch_router_list`
raise `cannot map router replay registry to the current PP/VPP stage` when the
process-global `RouterReplay.router_instances` size matches neither the local
nor the global MoE-layer count. But the registry is only populated when router
replay is enabled on the config (`apply_router_replay_patch` constructs
`RouterReplay` instances only under `enable_routing_replay` /
`moe_enable_routing_replay`), and `forward_step`
(verl/workers/engine/megatron/transformer_impl.py:1297) calls
`is_replay_backward_action` unconditionally. With replay disabled:
registry=0 while `is_moe_layer` (via `moe_layer_freq=1`, the Megatron default
even for dense models) counts 14/28 (dense Qwen3-0.6B, PP=2) or 48/48 (MoE
Qwen3-30B-A3B) → hard crash at the first `compute_log_prob` forward. Pre-#7106
the empty registry sliced to `[]` and every `is_*_action` caller treated it as
"no replay action". First main containing #7106 is d040717b — the exact commit
all four jobs failed on; the same jobs were green on 23af6a7a the previous
night, and the non-Megatron nightly jobs (FSDP/veomni) were green on d040717b.

## Change

- `verl/utils/megatron/router_replay_utils.py`: early-return `[]` when the
  registry is empty (replay machinery never constructed), keeping #7106's
  strict error for non-empty un-mappable registries.
- `tests/workers/engine/megatron/test_router_replay_utils_on_cpu.py`: one
  regression test (empty registry → `[]`).

## Validation status

Log analysis + logic verification only — no NPU. py_compile passed; the fixed
function was exercised directly with stubbed torch/megatron imports (empty
registry → [], local-only registry → correct slice, ambiguous non-empty
registry → still raises, all `is_*_action` falsy on empty, VPP variant → []).
Verification path: the four nightly jobs must get past `compute_log_prob` and
train 15/15 again.

## Notes

- No upstream issue/PR tracks this (gh search issues/prs: empty; the only
  router-replay PRs are #7106 itself and unrelated ones).
- Blast radius: every Megatron-engine job with router replay disabled — i.e.
  the whole nightly Megatron fleet. High priority for a human-opened PR.

## Status updates

- **2026-09-08:** pushed (a56f3ec7 on d040717b). Awaiting human-opened PR.

- **2026-09-09: SUPERSEDED UPSTREAM — no PR needed from this branch; safe to
  discard.** Upstream merged `c8687a02` ("Revert '[megatron] fix: preserve R2
  router replay for THD-packed batches' (#7786)", merged 2026-09-08 02:54 UTC),
  a full revert of #7106 (448 deletions incl.
  `tests/workers/engine/megatron/test_router_replay_utils_on_cpu.py` — the very
  file this branch adds to — and the strict mapping check in
  `verl/utils/megatron/router_replay_utils.py`; verified gone from main
  7cb65014). The 2026-09-08 18:08 UTC nightly run (34261271359) confirms all
  Megatron jobs train through `compute_log_prob` again on main: the gspo-30b
  job ran a healthy 15/15 and failed only at the metric check-script. The
  regression this branch fixed is therefore resolved upstream by revert; the
  branch is redundant (it was built against d040717b and would now conflict
  with the reverted test file). Branch left on the fork untouched (deletion is
  outside this kit's push scope); recommend the human delete it when reviewing.
  No rebase/re-push performed.
