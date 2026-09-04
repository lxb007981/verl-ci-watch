# ci-fix/fsdp-no-sync-default-true — audit record

- **Date pushed:** 2026-08-29 (analyzing nightly window of 2026-08-28 UTC evening)
- **PR title (for the human to reuse):** `[fsdp] fix: restore deferred gradient sync as the default`
- **Branch:** `ci-fix/fsdp-no-sync-default-true` (from `origin/main` = `24f25b03`, head `bd7e6a85`)
- **Fork branch URL:** https://github.com/lxb007981/verl/tree/ci-fix/fsdp-no-sync-default-true
- **Compare link:** https://github.com/verl-project/verl/compare/main...lxb007981:ci-fix/fsdp-no-sync-default-true
- **PR body:** `state/pending-prs/ci-fix_fsdp-no-sync-default-true.body.md`
- **Target jobs/runs:**
  - nightlyCI_gspo-qwen3-8b-fsdp2-vllm_ascend — run 33214313669, job 98994426047 (VERL_BUG, primary evidence)
  - nightlyCI_ppo-qwen3-8b-fsdp-vllm_ascend — run 33210244232, job 98981439535 (FSDP1 corroborating evidence: flag composed False, memory unchanged)

## Root cause

#7458 (commit `a0feb78f`, merged 2026-08-28, in the window between the green
nightly on `662507f9` and the failing nightly on `24f25b03`) added
`use_no_sync_for_gradient_accumulation` with dataclass default `True`
("preserve the current runtime behavior" of #7095) but shipped the Hydra YAMLs
with `false`: `verl/trainer/config/engine/fsdp.yaml` (1×) and
`verl/trainer/config/_generated_ppo_trainer.yaml` (3×: actor, ref, critic).
Hydra-launched jobs compose the YAML, so every FSDP job silently switched to
per-micro-batch gradient sync + reshard. On the FSDP2 gspo-8b nightly this
removed the unsharded-gradient retention: peak memory 47.87 → 20.82 GB
(−27.04 GB, threshold 1) against a 24 h-old baseline, failing `check_npu.py`;
throughput/step/rewards/probs all in band. The FSDP1 ppo-8b job composed the
same `False` with memory unchanged to 6 decimals (FSDP1 accumulates in the
flat sharded buffer either way), which rules out environment/hardware causes
for the FSDP2 drop. Recipe repo unchanged since Aug 27 (`17cabaa4`); nightly
scripts unchanged in the commit window.

## Change

Four YAML booleans `false` → `true` (fsdp.yaml + three flattened occurrences).
No code change; #7458's runtime gating and tests untouched (tests assert the
dataclass default `True`, which is consistent with the restored YAML).

## Validation status

Log analysis only — no NPU hardware; no training run executed with the fix.
Verification path: nightlyCI_gspo-qwen3-8b-fsdp2-vllm_ascend should compose
`True`, return to ≈ 47.9 GB peak memory and pass the baseline check. The
generated YAML was hand-edited to match `scripts/generate_trainer_config.sh`
output; human should re-run that script to confirm byte-identical.

## Status update — 2026-09-04: branch no longer on the fork

`git ls-remote --heads lxb` on `lxb007981/verl` today shows no `ci-fix/*` heads — the branch
(`bd7e6a85`, pushed 2026-08-29) was deleted at some point after that. No PR was ever opened
from it (searched upstream by title, by `use_no_sync_for_gradient_accumulation`, and over the
author's PR list — nothing), and the fix has not landed: main `84e014b4` still ships `false`
in all 4 YAML spots (`verl/trainer/config/engine/fsdp.yaml:61` + 3× `_generated_ppo_trainer.yaml`)
while the dataclass default remains `True`.

The kit did **not** re-push: the deletion looks like an out-of-band human decision, and the
underlying gspo-8b failure has been dormant (job green again 2026-09-03 19:13 UTC,
run 33795055058 / job 100780629515, still composing `false`). The PR body in
`ci-fix_fsdp-no-sync-default-true.body.md` is preserved verbatim for reuse; to resurrect,
re-create `ci-fix/fsdp-no-sync-default-true` from `origin/main` with the same four
`false`→`true` edits.

## Alternative (if the new default was intentional)

If maintainers prefer per-micro-batch sync as the default (tonight's FSDP2 job
was marginally faster with it), then instead: flip the dataclass default and
docs to match `false`, and regenerate the Ascend recipe baselines — but do it
deliberately; as shipped, `main` contradicts its own documented default.
