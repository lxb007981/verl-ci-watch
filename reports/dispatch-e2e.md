# verl nightly Ascend CI watch — dispatch-e2e

## Summary

| job | run | verdict | action |
|---|---|---|---|
| nightlyCI_gspo-qwen3-8b-fsdp2-vllm_ascend | 31966689363 | INFRA (carried over) | none — dedup hit, state updated (day 2) |

## New failures

None. The single failed job in the window matched an already-recorded signature (see below).

## Still failing

- `nightlyCI_gspo-qwen3-8b-fsdp2-vllm_ascend` — Ray host-memory OOM at `actor_rollout_wg.init_model()` (`2 worker(s) were killed due to the node running low on memory … 498.84GB / 512.00GB`), still failing, day 2 since first seen (2026-08-17). Verdict INFRA: node RAM exhausted during model init on the NPU runner; no verl-code traceback, not a `check_npu.py` baseline failure. Run 31966689363 (created 2026-08-16T19:08Z) is likely the same run already covered by yesterday's window. Correlation check: current `origin/main` HEAD c4b389ad ("[fsdp] enable non-blocking FSDP2 model transfers") landed 2026-08-18, *after* this run — not implicated.

## Draft PRs opened

None — no `VERL_BUG` verdicts today. `state/pending-prs/` is empty.

## Infra noise

- 32060816134 — nightly_ci_ascend, cancelled (2026-08-17 19:31)
- 32055042929 — nightly_ci_ascend, cancelled (2026-08-17 18:28)
- 32050452602 — nightly_ci_ascend, cancelled (2026-08-17 17:28)
- 31963453856 — nightly_ci_ascend, cancelled (2026-08-16 18:03)
- 31960599846 — nightly_ci_ascend, cancelled (2026-08-16 17:06)
- 31903075505 — nightly_ci_ascend, cancelled (2026-08-15 19:08)
