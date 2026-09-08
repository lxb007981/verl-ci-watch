> Branch auto-prepared by the nightly Ascend CI triage (log analysis only,
> no NPU validation). PR to be opened by a human after review.

### What does this PR do?

Fixes a regression introduced by #7106 that crashes **every Megatron-engine
run that does not enable router replay** — which is the default — at the
first `compute_log_prob` forward pass:

```
RuntimeError: cannot map router replay registry to the current PP/VPP stage:
registry=0, local_pp_routers=14, global_routers=28, pp_rank=0, vp_rank=0
```

(from `verl/utils/megatron/router_replay_utils.py`, reached via
`verl/workers/engine/megatron/transformer_impl.py:1297` →
`RouterReplayHelper.is_replay_backward_action`)

`RouterReplay` instances register themselves into the process-global
registry only when replay is enabled on the config
(`apply_router_replay_patch` gates `TopKRouter` patching on
`enable_routing_replay` / `moe_enable_routing_replay`), so the registry is
legitimately empty unless the feature is opted into. #7106 replaced the
old benign behavior (slicing an empty registry → `[]`, which all
`is_*_action` callers already treat as "no replay action") with a hard
error. Because `forward_step` calls `is_replay_backward_action`
unconditionally — replay enabled or not — and `is_moe_layer` counts every
layer as MoE when `moe_layer_freq=1` (the Megatron default, even for dense
models), the raise fires for:

- dense models (e.g. Qwen3-0.6B quick_start: `local=14, global=28`), and
- MoE models with replay disabled (e.g. Qwen3-30B-A3B nightlies:
  `local=48, global=48`).

The fix returns `[]` when the registry is empty ("replay machinery was
never constructed in this process"), restoring the pre-#7106 contract,
while keeping #7106's strict mapping error for **non-empty** registries
that cannot be mapped to the local PP/VPP stage (its actual purpose).

Evidence: the four Megatron nightly Ascend jobs that ran on main
`d040717b` (first main containing #7106) all died with this exact error
at the first `compute_log_prob`, while all non-Megatron (FSDP/veomni)
nightly jobs on the same commit stayed green. The same jobs were green on
`23af6a7a` (parent window before #7106). No other commit in
`23af6a7a..d040717b` touches this path.

Affected nightly jobs (2026-09-07 UTC evening, all run 34150398515 /
34146606227):
`quick_start_qwen3_0_6b_megatron_vllm_ascend`,
`quick_start_qwen3_0_6b_megatron_sglang_ascend`,
`nightlyCI_gspo-qwen3-30b-megatron-vllm_ascend`,
`nightlyCI_grpo-qwen3-30b-megatron-sglang_ascend`.

### Checklist Before Starting

- [x] Search for similar PRs. Paste at least one query link here:
  https://github.com/verl-project/verl/pulls?q=is%3Apr+router+replay+registry
  (no open PR or issue tracks this error; #7106 is the commit that
  introduced the raise, verified via `git log` and code reading)
- [x] Format the PR title as `[{modules}] {type}: {description}`:
  `[megatron] fix: treat empty router replay registry as disabled replay`

### Test

**Honesty note:** validation was **log analysis plus logic verification
only** — no NPU hardware was available, so the failing nightly jobs were
not re-run.

What was done:

- `python -m py_compile` on both touched files — passes.
- The fixed `get_micro_batch_router_list` was exercised directly (module
  executed with stubbed `torch`/`megatron.core` imports, since this
  environment has no torch/megatron installed):
  - empty registry → `[]` (no raise) — the regression case;
  - local-only registry (24/24) → correct offset-0 slice — #7106
    behavior preserved;
  - ambiguous non-empty registry (5 vs 24/48) → still raises the #7106
    error — protection preserved;
  - `is_r2_record_action` / `is_replay_forward_action` /
    `is_replay_backward_action` all falsy on empty registry — pre-#7106
    call-site semantics restored;
  - empty registry with VPP enabled → `[]`.
- Added a CPU regression test
  (`tests/workers/engine/megatron/test_router_replay_utils_on_cpu.py::test_get_micro_batch_router_list_with_empty_registry_returns_empty`)
  following the file's existing fixture style; it skips via
  `pytest.importorskip("megatron.core")` where megatron is absent.

Verification path: the four nightly Ascend Megatron jobs above must get
past `compute_log_prob` and train 15/15 again (they died at the first
forward on every run of `d040717b`). The unit test runs in the CPU
unit-test CI.

### API and Usage Example

No API change. Behavior with router replay **enabled** is untouched (the
mapping logic for non-empty registries is byte-identical); with replay
**disabled** the helpers return falsy again instead of raising.

### Design & Code Changes

- `verl/utils/megatron/router_replay_utils.py`
  (`RouterReplayHelper.get_micro_batch_router_list`): early-return `[]`
  when `len(RouterReplay.router_instances) == 0`, with a comment pointing
  at `apply_router_replay_patch` as the (only) populator of the registry.
- `tests/workers/engine/megatron/test_router_replay_utils_on_cpu.py`:
  one regression test asserting the empty-registry case returns `[]`
  even though `moe_layer_freq=1` counts every layer as an MoE layer.

### Checklist Before Submitting

> [!IMPORTANT]
> Please check all the following items before requesting a review, otherwise the reviewer might deprioritize this PR for review.

- [ ] Read the [Contribute Guide](https://github.com/verl-project/verl/blob/main/CONTRIBUTING.md).
- [ ] Apply [pre-commit checks](https://github.com/verl-project/verl/blob/main/CONTRIBUTING.md#code-linting-and-formatting): `pre-commit install && pre-commit run --all-files --show-diff-on-failure --color=always`
- [ ] Add / Update [the documentation](https://github.com/verl-project/verl/tree/main/docs).
- [ ] Add unit or end-to-end test(s) to [the CI workflow](https://github.com/verl-project/verl/tree/main/.github/workflows) to cover all the code. If not feasible, explain why: CPU regression test added; the end-to-end reproduction requires NPU hardware and is covered by the nightly Ascend Megatron jobs.
- [ ] Once your PR is ready for CI, send a message in [the `ci-request` channel](https://verl-project.slack.com/archives/C091TCESWB1) in [the `verl` Slack workspace](https://join.slack.com/t/verl-project/shared_invite/zt-3855yhg8g-CTkqXu~hKojPCmo7k_yXTQ). (If not accessible, please try the [Feishu group (飞书群)](https://applink.larkoffice.com/client/chat/chatter/add_by_link?link_token=772jd4f1-cd91-441a-a820-498c6614126a).)
- [ ] If your PR is related to the `recipe` submodule, please also update the reference to the submodule commit via `git submodule update --remote` or `cd recipe && git pull origin main`.

---

AI-assistance disclosure: this branch was prepared by an automated nightly
CI triage agent (log analysis + code reading; no NPU execution). A human
must review every changed line and run the relevant tests before opening
the PR. Duplicate-work check performed: no open PR/issue addresses this
regression (search link above).
