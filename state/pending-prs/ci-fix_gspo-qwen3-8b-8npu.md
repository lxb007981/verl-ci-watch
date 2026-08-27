# ci-fix/gspo-qwen3-8b-8npu — LANDED UPSTREAM (no PR awaited)

- Status: **resolved** — merged upstream as verl PR
  [#7456](https://github.com/verl-project/verl/pull/7456)
  (commit `6cbca9ce`, merged 2026-08-20 13:30:17 UTC), authored by the fork
  owner (re-authored on top of main; not a merge of this branch verbatim).
- Prepared: 2026-08-20 (kit run; audit record reconstructed 2026-08-27 after
  the runner workspace lost `state/pending-prs/`). Branch:
  `ci-fix/gspo-qwen3-8b-8npu` (head `84e85d6b`).
- Fork URL: https://github.com/lxb007981/verl/tree/ci-fix/gspo-qwen3-8b-8npu
- Root cause targeted: PR #7444 moved `nightlyCI_gspo-qwen3-8b-fsdp2-vllm_ascend`
  from a 16-NPU runner to the 8-NPU `a2b3-8` runner while
  `run_gspo_qwen3_8b_fsdp2_npu.sh` still defaulted `NGPUS_PER_NODE=16`, so every
  nightly aborted at startup with
  `ValueError: Total available GPUs 8.0 is less than total desired GPUs 16`.
- Fix: `NGPUS_PER_NODE=${NGPUS_PER_NODE:-8}`. #7456 landed the same default
  (plus a trailing-newline fix) with the note "A2 machines have 8 npus per node."

No PR remains to be opened for this branch. Context for the current
gspo-8b nightly failures: this 16→8 NPU move is why the recipe baseline
(`baseline_gspo_qwen3_8b_fsdp2_npu.txt`, still recording a 16-NPU run) no
longer matches the job — see the 2026-08-27 report.
