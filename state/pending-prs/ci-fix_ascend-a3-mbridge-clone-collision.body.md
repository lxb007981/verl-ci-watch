> Branch auto-prepared by the nightly Ascend CI triage (log analysis only,
> no NPU validation). PR to be opened by a human after review.

### What does this PR do?

Fixes the `nightlyCI_grpo_qwen3_5_2b_fsdp2_vllm_ascend` nightly job, which
has failed every scheduled run since the Ascend a3 image was rebuilt on the
Megatron 0.18.0 stack (#7604): the job now dies in setup at the "Clone
Megatron Bridge" step with

```
fatal: destination path '/Megatron-Bridge' already exists and is not an empty directory.
##[error]Error: ... command terminated with exit code: 128
```

The rebuilt image (`verl:latest-vllm-a3-ubuntu`) now bakes Megatron-Bridge
into the container: `docker/ascend/Dockerfile.ascend_9.1.0_a3` clones
`Megatron-Bridge` (tag v0.5.0) to `/Megatron-Bridge` and
`scripts/install_vllm_mcore_npu.sh` pip-installs it editable. The workflow
step (unchanged since #7081) assumes the path is absent and unconditionally
`git clone`s into it.

The fix removes any pre-baked checkout before cloning, so the step keeps
placing the pinned commit `de93536e` at `/Megatron-Bridge` on both the old
image (where `rm -rf` is a no-op) and the new one. The image's baked
checkout is v0.5.0 tip `fcbb603` — a different commit than the pin — so
simply dropping the step would silently change the version under test.

Evidence (first failing run 33904257189 / job 101125321989, main 23af6a7a):

- initial `pip list` (before any install step) shows
  `megatron-bridge 0.5.0+fcbb603  /Megatron-Bridge` and
  `megatron-core 0.18.3+dc0ee41 /Megatron-LM` → the new image contents.
- the same step on the last green run (33788722446 / job 100759772698,
  2026-09-03) shows `megatron-core 0.16.2` and no megatron-bridge, and
  `Cloning into '/Megatron-Bridge'...` succeeds.

### Checklist Before Starting

- [ ] Search for similar PRs. Paste at least one query link here: https://github.com/verl-project/verl/pulls?q=is%3A+pr+%22Megatron-Bridge%22+already+exists (no open PR or issue tracks this failure; #7604 introduced it)
- [x] Format the PR title as `[{modules}] {type}: {description}`: `[ci] fix: clear pre-baked /Megatron-Bridge before cloning pinned commit`

### Test

Validation was **log analysis only** — no NPU hardware was available, so the
fix was not executed. What was checked without hardware:

- the workflow YAML parses (`python3 -c "import yaml; yaml.safe_load(...)"`);
- `rm -rf` of a non-existent path is a no-op, so old images are unaffected;
- the pinned-commit `git fetch`/`git checkout` lines are untouched, so the
  runtime content of `/Megatron-Bridge` is exactly what previous green runs
  used (the image's editable install points at the same path, and the job
  additionally prepends `/Megatron-Bridge/src` to `PYTHONPATH`).

The change should be verified by the next scheduled run of
`nightlyCI_grpo_qwen3_5_2b_fsdp2_vllm_ascend` (18:00 UTC nightly): the
"Clone Megatron Bridge" step must succeed and the job must reach training
(it previously trained 15/15 steps and passed).

### API and Usage Example

No API change.

### Design & Code Changes

One line added to the "Clone Megatron Bridge" step of
`nightlyCI_grpo_qwen3_5_2b_fsdp2_vllm_ascend` in
`.github/workflows/nightly_ascend.yml`:

```diff
       - name: Clone Megatron Bridge
         run: |
+          rm -rf /Megatron-Bridge
           git clone --depth 1 https://github.com/NVIDIA-NeMo/Megatron-Bridge.git /Megatron-Bridge
```

Note for reviewers: the disabled (commented-out) `dapo-moonlight-16b` job
carries a copy of the same clone step; if it is ever re-enabled on an image
that bakes `/Megatron-Bridge`, it needs the same guard.

### Checklist Before Submitting

- [ ] Read the [Contribute Guide](https://github.com/verl-project/verl/blob/main/CONTRIBUTING.md).
- [ ] Apply [pre-commit checks](https://github.com/verl-project/verl/blob/main/CONTRIBUTING.md#code-linting-and-code-style): YAML only; `pre-commit run --all-files` should be run by the human opener.
- [ ] Add / Update [the documentation](https://github.com/verl-project/verl/tree/main/docs). — N/A (CI workflow fix)
- [ ] Add unit or end-to-end test(s) to the CI workflow. — N/A; this *is* the CI workflow; the nightly itself is the test.
- [ ] Once your PR is ready for CI, send a message in the [`ci-request` channel](https://verl-project.slack.com/archives/C091TCESWB1). (left unchecked for the human opener)
- [ ] `recipe` submodule — N/A.

---

AI assistance disclosure: this branch was prepared automatically by the
nightly Ascend CI triage kit (log analysis; no NPU validation). A human
must review every line and run the relevant checks before opening the PR.
