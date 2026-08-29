> Branch auto-prepared by the nightly Ascend CI triage (log analysis only,
> no NPU validation). PR to be opened by a human after review.

### What does this PR do?

Restores deferred FSDP gradient synchronization as the shipped default, as
documented. #7458 introduced `use_no_sync_for_gradient_accumulation` with a
dataclass default of `True` — the PR description says this "keeps its default
`true` to preserve the current runtime behavior" of #7095 — but the Hydra YAMLs
landed with the value `false`:

- `verl/workers/config/engine.py`: `use_no_sync_for_gradient_accumulation: bool = True`
- `verl/trainer/config/engine/fsdp.yaml`: `use_no_sync_for_gradient_accumulation: false` ← flipped here
- `verl/trainer/config/_generated_ppo_trainer.yaml`: `false` for actor, ref **and** critic ← flipped here
- `docs/perf/perf_tuning.rst`: "By default, the FSDP engine defers gradient synchronization on the non-final micro-batches"
- the PR's own "API and Usage Example": "# Default: defer gradient synchronization until the final micro-batch."

Because every Hydra-launched trainer composes the YAML (not the dataclass
default), this silently disabled the M→1 gradient-sync-round reduction from
#7095 for all FSDP jobs and changed their memory profile.

Observed on the Ascend nightly (evidence, 2026-08-28 UTC evening, `main` =
`24f25b03`): `nightlyCI_gspo-qwen3-8b-fsdp2-vllm_ascend` (run 33214313669,
job 98994426047) composed the flag as `'use_no_sync_for_gradient_accumulation': False`
for actor/ref/critic, and its FSDP2 actor peak memory dropped
47.87 → 20.82 GB (−27.04 GB) against a baseline recorded ~24 h earlier on the
identical recipe (green on `662507f9`), failing `check_npu.py` on the single
metric `actor/perf/max_memory_allocated_gb` while throughput (+1.36 %), step
time (−2.32 %), rewards and probs_diff all stayed in band. This is the exact
signature "sync + reshard after every micro-batch no longer retains unsharded
gradients": FSDP2 with deferred sync keeps per-parameter unsharded grads until
the final backward. The corroborating FSDP1 nightly
(`nightlyCI_ppo-qwen3-8b-fsdp-vllm_ascend`, run 33210244232) also composed
`False` but its peak memory is unchanged to 6 decimals (Δ −0.016 GB) — FSDP1
accumulates into the flat sharded grad buffer either way — which rules out any
environmental/hardware explanation for the FSDP2 drop.

The fix flips the four YAML booleans back to `true` so the shipped default
matches the dataclass, the documentation, and pre-#7458 behavior. No code
change; the runtime gating added by #7458 is untouched.

Alternative if maintainers actually prefer per-micro-batch sync as the new
default (tonight's FSDP2 job was marginally *faster* with it, step −2.32 %):
then please make that deliberate — dataclass default `False`, docs updated,
and the five Ascend recipe baselines regenerated — instead of the current
state where main contradicts itself. This branch takes the conservative path
of restoring the documented contract.

### Checklist Before Starting

- [x] Search for similar PRs:
  https://github.com/verl-project/verl/pulls?q=is%3Apr+use_no_sync_for_gradient_accumulation
  (only merged #7458 and #7095) and
  https://github.com/verl-project/verl/issues?q=use_no_sync_for_gradient_accumulation
  (no results). No open PR/issue covers the flipped default.
- [x] Format the PR title as `[{modules}] {type}: {description}`:
  `[fsdp] fix: restore deferred gradient sync as the default`

### Test

Validation for this branch was **log analysis only** — no NPU hardware was
available to the triage agent, and no training run was executed with this
change applied. Concretely verified from the CI logs of runs 33214313669 and
33210244232:

- Both nightly jobs' composed Hydra configs dump
  `'use_no_sync_for_gradient_accumulation': False` for actor/ref/critic at
  startup, proving the YAML value (not the `True` dataclass default) drives
  runtime behavior.
- The gspo-8b FSDP2 job's per-step `actor/perf/max_memory_allocated_gb` is a
  flat 20.67–20.82 GB for all 15 steps vs the baseline's 47.87 GB.
- The FSDP1 ppo-8b job's memory is byte-stable vs its baseline (22.2156 vs
  22.2318), isolating the change to the FSDP2 unsharded-gradient retention
  path gated by this flag.
- `python3 -c "import yaml; yaml.safe_load(...)"` passes for both edited
  YAMLs; no Python files changed, so the #7458 CPU tests
  (`tests/workers/config/test_engine_config_on_cpu.py`,
  `tests/workers/test_fsdp_gradient_accumulation_sync_on_cpu.py`) are
  unaffected — they assert the dataclass default `True` and the gating
  behavior, neither of which moves.

The nightly job that should verify this fix: **nightlyCI_gspo-qwen3-8b-fsdp2-vllm_ascend**
(expected: composed config shows `True`, memory returns to ≈ 47.9 GB ± 1 and
the baseline check passes again). Secondary observers of the same default:
`nightlyCI_grpo_qwen3_vl_8b_Instruct_fsdp2_vllm_ascend`,
`nightlyCI_grpo_qwen3_5_2b_fsdp_turbo_vllm_ascend`,
`nightlyCI_grpo_qwen3_5_2b_fsdp2_vllm_ascend`, and the fsdp2 quick_start jobs.
Also worth running locally (not run by the triage agent): 
`scripts/generate_trainer_config.sh` — the generated file was hand-edited to
match the flattened output of the corrected `fsdp.yaml`; the script should
produce a byte-identical diff (the key carries no `oc.select` indirection).

### API and Usage Example

No API change. Opt-out for memory-constrained jobs is unchanged from #7458:

```bash
# Default (after this PR): defer gradient sync until the final micro-batch.
actor_rollout_ref.actor.fsdp_config.use_no_sync_for_gradient_accumulation=True

# Memory-constrained opt-out: synchronize and reshard after every micro-batch.
actor_rollout_ref.actor.fsdp_config.use_no_sync_for_gradient_accumulation=False
```

### Design & Code Changes

- `verl/trainer/config/engine/fsdp.yaml`:
  `use_no_sync_for_gradient_accumulation: false` → `true`.
- `verl/trainer/config/_generated_ppo_trainer.yaml`: the three flattened
  occurrences (actor, ref, critic) `false` → `true`, matching what
  `scripts/generate_trainer_config.sh` emits from the engine YAML.
- Nothing else. The `FSDPEngine._gradient_sync_context` gating from #7458 and
  the `getattr(..., True)` legacy fallback are left as-is.

### Checklist Before Submitting

> [!IMPORTANT]
> Please check all the following items before requesting a review,
> otherwise the reviewer may deprioritize this PR for review.

- [ ] Read the [Contribute Guide](https://github.com/verl-project/verl/blob/main/CONTRIBUTING.md).
- [ ] Apply [pre-commit checks](https://github.com/verl-project/verl/blob/main/CONTRIBUTING.md#code-linting-and-pre-commit): `pre-commit install && pre-commit run --all-files --show-diff-on-failure --color=always`. (YAML-only change; triage agent could not run the repo's pre-commit env.)
- [ ] Add / Update [the documentation](https://github.com/verl-project/verl/tree/main/docs). (No update needed — `docs/perf/perf_tuning.rst` already documents defer-as-default; this PR makes the config match it.)
- [ ] Add unit or end-to-end test(s) to the CI workflow to cover all the code. If not feasible, explain why: the existing `tests/workers/config/test_engine_config_on_cpu.py` covers the dataclass default; a YAML-vs-dataclass consistency assertion would be the natural follow-up but is beyond this minimal revert of the flipped default.
- [ ] Once your PR is ready for CI, send a message in [the `ci-request` channel](https://verl-project.slack.com/archives/C091TCESWB1) in [the `verl` Slack workspace](https://join.verl-project.slack.com). (If not accessible, please try the [Feishu group (飞书群)](https://applink.larkoffice.com/client/chat/chatter/add_by_link?link_token=772jd4f1-cd91-441e-a820-498c6614126a).)
- [ ] If your PR is related to the `recipe` submodule, please also update the reference to the submodule commit via `git submodule update --remote` or `cd recipe && git pull origin main`. (Not related.)
