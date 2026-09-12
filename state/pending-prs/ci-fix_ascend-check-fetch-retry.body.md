> Branch auto-prepared by the nightly Ascend CI triage (log analysis only,
> no NPU validation). PR to be opened by a human after review.

### What does this PR do?

Makes the nightly Ascend check-step fetches (check_npu.py + per-job
`baseline.txt` from `raw.githubusercontent.com/verl-project/verl-ascend-recipe`)
survive the runner cluster's recurring egress brownouts instead of
discarding a fully healthy training run at the last step.

Observed failures this fixes (both on the a2b3 runner cluster, both after a
healthy 15/15-step run):

- 2026-09-11, `nightlyCI_ppo-qwen3-8b-fsdp-vllm_ascend` ([run 34626310730](https://github.com/verl-project/verl/actions/runs/34626310730/job/103352157796)):
  the baseline.txt curl stalled at 0 bytes for 15.5 min, then
  `curl: (56) OpenSSL SSL_read: Connection timed out, errno 110` → step exit 1.
- 2026-09-04, same job ([run 33783219400](https://github.com/verl-project/verl/actions/runs/33783219400/job/100741676218)):
  `curl: (52) Empty reply from server` after a 12.6-min hang.

Root cause of the wasted time: `--retry 3` does NOT retry transfer errors
like exit 52/56 (curl only auto-retries timeouts, FTP 4xx and HTTP 5xx/6xx),
so the step made exactly ONE attempt that sat in a blocked `SSL_read` until
the OS TCP timeout fired (~15 min). Two more brownout evenings (2026-09-09,
2026-09-11) stalled the sibling job's check curls for 2-3 min but recovered,
corroborating a degraded-egress window of roughly 10-15 min that simple
bounded retries would ride out.

Change (all 5 active check steps in `.github/workflows/nightly_ascend.yml`,
2 curl lines each):

```
- curl --fail --location --retry 3 --output ...
+ curl --fail --location --retry 5 --retry-all-errors --retry-delay 5 --connect-timeout 15 --max-time 120 --output ...
```

- `--retry-all-errors`: retry exit 52/56-class transfer errors (curl ≥ 7.71.1;
  the CI images are Ubuntu 22.04-based, curl ≥ 7.81).
- `--connect-timeout 15` / `--max-time 120`: bound each attempt so a stalled
  read fails fast and retries, instead of one 15-min hang.
- `--retry 5 --retry-delay 5`: 6 attempts spanning ~12.5 min worst case —
  comparable to the 15.5 min wasted tonight, but with 6 real chances.
  Files are tiny (6 KB / ~155 B), so 120 s per attempt is generous.

The commented-out (disabled) dapo check step is left untouched.

### Checklist Before Starting

- [x] Search for similar PRs. Paste at least one query link here:
  https://github.com/verl-project/verl/pulls?q=is%3Apr+nightly_ascend+curl+retry
  (also searched `check_npu baseline`, `retry-all-errors` — no open PR/issue
  tracks this)
- [x] Format the PR title as `[{modules}] {type}: {description}`:
  `[ci] fix: harden nightly Ascend check-step fetches against runner egress brownouts`

### Test

Validation for this branch was **log analysis only — no NPU hardware was
available**. Concretely:

- `yaml.safe_load` on the modified workflow: parses cleanly.
- The exact new curl command line was executed against the real URL
  (`.../baseline/check_npu.py`, 6188 B) on this workstation with curl 8.5.0:
  fetches successfully.
  (Note: an earlier draft used `--maximum-time`, which is not a curl option —
  the dry-run caught it; the committed spelling `--max-time` is verified.)
- The failure evidence comes from the nightly logs referenced above
  (single progress-meter cycle + single error line proves no retry occurred).

The authoritative test is the next nights of `nightlyCI_ascend` on the NPU
cluster: on a brownout evening the check step should show repeated
progress-meter cycles (retries) and eventually succeed, and no run should end
in `exit code 56/52` at the fetch line.

### API and Usage Example

No API change (workflow yaml only).

### Design & Code Changes

See "What does this PR do?" — a one-flag-set change applied uniformly to the
10 curl lines of the 5 active check steps in `.github/workflows/nightly_ascend.yml`.

### Checklist Before Submitting

- [ ] Read the [Contribute Guide](https://github.com/verl-project/verl/blob/main/CONTRIBUTING.md).
- [ ] Apply pre-commit checks.
- [ ] Add / Update the documentation.
- [ ] Add unit or end-to-end test(s) to the CI workflow to cover all the code. If not feasible, explain why: change is to the CI workflow itself; coverage is the nightly runs observing retry behavior.
- [ ] Once your PR is ready for CI, send a message in the `ci-request` channel in the `verl` Slack workspace.
- [ ] If this PR is related to the `recipe` submodule, please also update the reference to the submodule commit.

---

AI assistance disclosure: this branch was prepared by an automated CI-triage
agent (nightly Ascend watch) from the failure logs cited above; the opening
human has reviewed and takes responsibility for the change per the repo's
contribution policy.
