> Draft auto-prepared by the nightly Ascend CI triage (log analysis only,
> no NPU validation). @maintainer-friendly: it will be marked ready after
> human review.

### What does this PR do?

Fixes the `nightlyCI_gspo-qwen3-8b-fsdp2-vllm_ascend` nightly job, which has
failed deterministically at startup every night since #7444 merged
(2026-08-17): that PR moved the job from the 16-NPU `linux-aarch64-a3-16`
runner to the 8-NPU `linux-aarch64-a2b3-8` runner, but
`tests/special_npu/nightly_ci_ascend/run_gspo_qwen3_8b_fsdp2_npu.sh` still
defaults to `NGPUS_PER_NODE=16`.

Evidence from last night's run (run 32293302531, job 96198832871,
`r32293302531_nightlyCI_gspo-qwen3-8b-fsdp2-vllm_ascend.log`):

- `npu-smi info` at job start lists exactly 8 × 910B3, all healthy.
- The launch overrides include `trainer.n_gpus_per_node=16` (script default,
  not overridden by the workflow).
- verl aborts in `ResourcePoolManager.create_resource_pool` before any worker
  starts:

  ```
  File "/__w/verl/verl/verl/single_controller/ray/base.py", line 240, in _check_resource_available
      raise ValueError(
  ValueError: Total available GPUs 8.0 is less than total desired GPUs 16
  ```

This changes the script default to `NGPUS_PER_NODE=8`, matching the runner it
is scheduled on and the sibling `run_ppo_qwen3-8b_fsdp_npu.sh` (same Qwen3-8B
model, same `a2b3-8` runner label, same 910B image, which hardcodes
`trainer.n_gpus_per_node=8`). The 16-NPU jobs (e.g. `run_gspo_qwen3_30b_megatron_npu.sh`)
were not moved by #7444 and are unaffected.

Divisibility of the remaining defaults was checked by inspection and holds for
8 GPUs: `SP_SIZE=2`, `ROLLOUT_TP=2`, `FSDP_SIZE=-1`,
`train_batch_size=32` (× `n=4` → 16 samples/GPU), `ppo_mini_batch_size=16`
(2/GPU). `ppo_max_token_len_per_gpu` derives from `seq_len/SP_SIZE` and is
unchanged.

### Checklist Before Starting

- [x] Search for similar PRs:
  - Issues: https://github.com/verl-project/verl/issues?q=%22Total+available+GPUs+is+less+than+total+desired+GPUs%22 (no hits)
  - PRs: https://github.com/verl-project/verl/pulls?q=is%3Apr+gspo+ascend (no open fix)
  - Open PRs touching this script: `gh pr list --search run_gspo_qwen3_8b` (none)
- [x] Title formatted as `[ci] fix: ...`.

### Test

**No NPU hardware was available to the triage agent; validation was log
analysis only.** Specifically:

- Root-caused from the failed nightly log (run 32293302531): 8 NPUs present,
  16 requested → startup `ValueError` before training begins.
- `bash -n tests/special_npu/nightly_ci_ascend/run_gspo_qwen3_8b_fsdp2_npu.sh`
  passes (syntax check).
- Verified by inspection that all parallelism/batch defaults divide evenly
  with 8 GPUs (see above), and that the workflow invokes the script without a
  `NGPUS_PER_NODE` env override, so the default is what the nightly uses.

The change should be verified by the next run of
`nightlyCI_gspo-qwen3-8b-fsdp2-vllm_ascend` (cron `0 19 * * *` on
`linux-aarch64-a2b3-8`). Note for the reviewer: the job's
`check_npu.py` baseline (`baseline_gspo_qwen3_8b_fsdp2_npu.txt`, stored on the
runner, not in this repo) was recorded on the 16-NPU a3 runner — if the
checking step flags throughput metrics after this fix, the baseline needs a
one-time refresh from the first green 8-NPU run.

### API and Usage Example

No API change. Behavior only via the script default:
`NGPUS_PER_NODE=${NGPUS_PER_NODE:-8}` (still overridable, e.g.
`NGPUS_PER_NODE=16 bash run_gspo_qwen3_8b_fsdp2_npu.sh` on a 16-card machine).

### Design & Code Changes

One-line default change in
`tests/special_npu/nightly_ci_ascend/run_gspo_qwen3_8b_fsdp2_npu.sh`:
`NGPUS_PER_NODE` 16 → 8. The alternative (moving the job back to
`linux-aarch64-a3-16`) was rejected because #7444 explicitly moved lightweight
tests to the smaller A2 instances; only the script was left behind.

### Checklist Before Submitting

> [!IMPORTANT]
> The triage agent left these unchecked for the human reviewer.

- [ ] Read the [Contribute Guide](https://github.com/verl-project/verl/blob/main/CONTRIBUTING.md).
- [ ] Apply [pre-commit checks](https://github.com/verl-project/verl/blob/main/CONTRIBUTING.md#code-linting-and-formatting).
- [ ] Add / Update [the documentation](https://github.com/verl-project/verl/tree/main/docs).
- [ ] Add unit or end-to-end test(s) to the CI workflow. If not feasible, explain why: this *is* the fix for a CI workflow job; verification is the nightly run itself.
- [ ] Once this PR is ready for CI, send a message in [the `ci-request` channel](https://verl-project.slack.com/archives/C091TCESWB1) in the [verl Slack workspace](https://join.slack.com/t/verl-project/shared_invite/zt-3855yhg8g-CTkqXu~hKojPCmo7k_yXTQ).
- [ ] Not related to the `recipe` submodule.

---

AI assistance disclosure: this draft was prepared automatically by the nightly
Ascend CI triage agent (log analysis; no NPU execution). A human maintainer
reviewed-list is expected to own, verify, and mark it ready.
